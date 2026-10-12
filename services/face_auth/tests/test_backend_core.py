from __future__ import annotations

import time
import tempfile
import unittest
from threading import Event
import json
import asyncio
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

import cv2
import numpy as np

from camera_demo import better_verified_sample, mirror_bbox
from backend.domain import AuthSession, SessionAuthError, SessionNotFoundError
from backend.bounded_executor import BoundedExecutor, ExecutorQueueFullError
from backend.admission import FrameAdmissionController
from backend.pipeline import AuthenticationPipeline
from backend.resource_pool import ResourcePool
from backend.runtime import VerificationOutcome
from backend.rate_limit import TokenBucketRateLimiter
from backend.session_store import SessionStore
from backend.settings import BackendSettings, env_bool
from backend.presenter import _serialize_recognition
from modules.face_detector import FaceCandidate, FaceDetectionResult
from modules.face_quality import score_recognition_frame
from modules.face_recognizer import (
    InsightFaceRecognizer,
    RecognitionResult,
    load_face_database,
    save_face_database,
)
from modules.anti_spoofing import AntiSpoofingResult
from modules.liveness_challenge import LivenessChallengeEngine
from modules.utils import load_config


class QuietLogger:
    def info(self, *_args, **_kwargs) -> None:
        pass

    def error(self, *_args, **_kwargs) -> None:
        pass

    def exception(self, *_args, **_kwargs) -> None:
        pass


class ProductionHardeningTests(unittest.TestCase):
    def test_production_disables_interactive_api_docs_by_default(self) -> None:
        with patch.dict(os.environ, {"FACE_PRODUCTION": "true"}, clear=True):
            from backend.app import create_app

            app = create_app()
            self.assertIsNone(app.docs_url)
            self.assertIsNone(app.redoc_url)
            self.assertIsNone(app.openapi_url)

    def test_strict_environment_boolean_rejects_invalid_value(self) -> None:
        with patch.dict(os.environ, {"FACE_PRODUCTION": "sometimes"}, clear=True):
            with self.assertRaises(ValueError):
                env_bool("FACE_PRODUCTION")

    def test_api_recognition_omits_server_path_and_internal_error(self) -> None:
        result = RecognitionResult(
            best_match_name="person_A",
            similarity_percent=90.0,
            similarity=0.9,
            distance=0.1,
            recognition_threshold=0.6,
            is_recognized=True,
            candidate_image=r"C:\\private\\enrollment.jpg",
            error="native stack detail",
        )
        payload = _serialize_recognition(result)
        self.assertIsNotNone(payload)
        self.assertNotIn("candidate_image", payload)
        self.assertNotIn("error", payload)


class FakeRuntime:
    def __init__(self) -> None:
        self.detector = self
        self.detect_calls = 0

    def list_identities(self) -> list[str]:
        return ["person_A"]

    def detect(self, frame: np.ndarray) -> FaceDetectionResult:
        self.detect_calls += 1
        height, width = frame.shape[:2]
        if width <= height:
            return FaceDetectionResult(0, [], None, frame.shape, ["no face"])
        bbox = (width // 4, height // 5, width * 3 // 4, height * 4 // 5)
        face = FaceCandidate(
            bbox=bbox,
            bbox_xywh=(bbox[0], bbox[1], bbox[2] - bbox[0], bbox[3] - bbox[1]),
            landmarks=[],
            landmarks_px=[],
            blendshapes={},
            yaw=0.0,
            pitch=0.0,
            roll=0.0,
            brightness=120.0,
            face_size_ratio=0.60,
            center_offset_ratio=(0.0, 0.0),
            eye_aspect_ratio=0.35,
            blink_score=0.0,
            smile_score=1.0,
            mouth_open_score=0.0,
            checks={
                "detected": True,
                "single_face": True,
                "face_size": True,
                "centered": True,
                "brightness": True,
                "pose": True,
            },
        )
        return FaceDetectionResult(1, [face], face, frame.shape, ["PASS"])

    def detection_metrics(self, result: FaceDetectionResult) -> dict[str, float]:
        face = result.primary_face
        return {
            "yaw": face.yaw if face else 0.0,
            "pitch": face.pitch if face else 0.0,
            "roll": face.roll if face else 0.0,
            "brightness": face.brightness if face else 0.0,
            "eye_aspect_ratio": face.eye_aspect_ratio if face else 0.0,
            "blink_score": face.blink_score if face else 0.0,
            "smile_score": face.smile_score if face else 1.0,
            "mouth_open_score": face.mouth_open_score if face else 0.0,
        }

    def verify_frames(self, *_args, **_kwargs) -> VerificationOutcome:
        time.sleep(0.05)
        return VerificationOutcome(None, True, "SUCCESS: test", 50.0, "SUCCESS")


def jpeg_bytes(width: int = 120, height: int = 240, value: int = 128) -> bytes:
    frame = np.full((height, width, 3), value, dtype=np.uint8)
    ok, encoded = cv2.imencode(".jpg", frame)
    if not ok:
        raise RuntimeError("test JPEG encoding failed")
    return encoded.tobytes()


class SessionStoreTests(unittest.TestCase):
    def test_expired_session_is_removed(self) -> None:
        clock = [100.0]
        config = load_config()
        store = SessionStore(10.0, 2, clock=lambda: clock[0])
        session = AuthSession("id", "person_A", LivenessChallengeEngine(config))
        session.updated_at = clock[0]
        store.add(session)
        clock[0] += 11.0
        with self.assertRaises(SessionNotFoundError):
            store.get("id")

    def test_session_token_is_required(self) -> None:
        import hashlib

        config = load_config()
        token = "one-time-session-secret"
        session = AuthSession(
            "id",
            "person_A",
            LivenessChallengeEngine(config),
            session_token_digest=hashlib.sha256(token.encode("utf-8")).hexdigest(),
        )
        store = SessionStore(60.0, 2)
        store.add(session)
        store.require_token("id", token)
        with self.assertRaises(SessionAuthError):
            store.require_token("id", "wrong-token")


class BoundedExecutorTests(unittest.TestCase):
    def test_rejects_work_when_running_and_queue_slots_are_full(self) -> None:
        started = Event()
        release = Event()
        executor = BoundedExecutor(1, 0, "bounded-test")

        def blocking_job() -> None:
            started.set()
            release.wait(1.0)

        try:
            executor.submit(blocking_job)
            self.assertTrue(started.wait(1.0))
            with self.assertRaises(ExecutorQueueFullError):
                executor.submit(lambda: None)
        finally:
            release.set()
            executor.shutdown()


class CapacityPrimitiveTests(unittest.TestCase):
    def test_token_bucket_rate_limiter_rejects_burst(self) -> None:
        clock = [100.0]
        limiter = TokenBucketRateLimiter(1.0, 2, clock=lambda: clock[0])
        self.assertTrue(limiter.allow("client"))
        self.assertTrue(limiter.allow("client"))
        self.assertFalse(limiter.allow("client"))
        clock[0] += 1.0
        self.assertTrue(limiter.allow("client"))
        self.assertEqual(1, limiter.rejected)

    def test_resource_pool_tracks_parallel_native_workers(self) -> None:
        pool = ResourcePool(["first", "second"])
        release = Event()
        started = Event()

        def hold_resource() -> None:
            with pool.checkout():
                started.set()
                release.wait(1.0)

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(hold_resource) for _ in range(2)]
            deadline = time.monotonic() + 1.0
            while pool.in_use < 2 and time.monotonic() < deadline:
                time.sleep(0.005)
            self.assertTrue(started.is_set())
            self.assertEqual(2, pool.in_use)
            self.assertEqual(2, pool.peak_in_use)
            release.set()
            for future in futures:
                future.result(timeout=1.0)
        self.assertEqual(0, pool.in_use)

    def test_frame_admission_rejects_quickly_when_full(self) -> None:
        async def scenario() -> None:
            admission = FrameAdmissionController(1)
            self.assertTrue(await admission.acquire(0.01))
            self.assertFalse(await admission.acquire(0.01))
            self.assertEqual(1, admission.rejected)
            admission.release()
            self.assertTrue(await admission.acquire(0.01))
            admission.release()

        asyncio.run(scenario())


class RecognitionSampleTests(unittest.TestCase):
    @staticmethod
    def anti_result(is_real: bool = True) -> AntiSpoofingResult:
        return AntiSpoofingResult(
            real_score=0.99 if is_real else 0.20,
            printed_photo_score=0.01,
            screen_replay_score=0.0,
            unknown_spoof_score=0.0,
            is_real=is_real,
            threshold=0.80,
            label="real" if is_real else "fake",
            model_count=1,
            inference_time_ms=1.0,
        )

    @staticmethod
    def recognition_result(similarity: float) -> RecognitionResult:
        return RecognitionResult(
            best_match_name="person_A",
            similarity_percent=similarity * 100.0,
            similarity=similarity,
            distance=1.0 - similarity,
            recognition_threshold=0.60,
            is_recognized=similarity >= 0.60,
        )

    def test_failed_late_sample_does_not_replace_verified_sample(self) -> None:
        verified = better_verified_sample(
            None,
            self.anti_result(),
            self.recognition_result(0.66),
            1.0,
        )
        selected = better_verified_sample(
            verified,
            self.anti_result(),
            self.recognition_result(0.52),
            2.0,
        )
        self.assertIs(selected, verified)
        self.assertAlmostEqual(0.66, selected.recognition_result.similarity)

    def test_face_quality_prefers_frontal_frame(self) -> None:
        detection = FakeRuntime().detect(np.zeros((720, 1280, 3), dtype=np.uint8))
        frontal_score = score_recognition_frame(detection, pose_limit=20.0)
        detection.primary_face.pitch = 30.0
        detection.primary_face.roll = 20.0
        posed_score = score_recognition_frame(detection, pose_limit=20.0)
        self.assertGreater(frontal_score, posed_score)

    def test_centroid_template_can_match_when_individual_templates_do_not(self) -> None:
        config = load_config()
        recognizer = InsightFaceRecognizer(config)
        angle = np.deg2rad(40.0)
        references = np.asarray(
            [
                [np.cos(angle), np.sin(angle)],
                [np.cos(angle), -np.sin(angle)],
            ],
            dtype=np.float32,
        )
        recognizer._database = {
            "persons": {
                "person_A": {
                    "embeddings": references,
                    "mean_embedding": np.asarray([1.0, 0.0], dtype=np.float32),
                    "images": [],
                }
            }
        }
        recognizer.get_embedding = lambda _image: (np.asarray([1.0, 0.0], dtype=np.float32), 1)  # type: ignore[method-assign]
        result = recognizer.recognize(
            np.zeros((32, 32, 3), dtype=np.uint8),
            threshold=0.90,
            target_name="person_A",
        )
        self.assertTrue(result.is_recognized)
        self.assertEqual("centroid", result.match_strategy)
        self.assertAlmostEqual(1.0, result.similarity)

    def test_mirror_bbox_maps_display_coordinates_to_sensor_frame(self) -> None:
        self.assertEqual((900, 20, 1100, 220), mirror_bbox((180, 20, 380, 220), 1280))

    def test_liveness_timeout_pauses_while_face_is_missing(self) -> None:
        config = load_config()
        engine = LivenessChallengeEngine(config)
        empty_metrics = {
            "yaw": 0.0,
            "pitch": 0.0,
            "roll": 0.0,
            "eye_aspect_ratio": 0.3,
            "blink_score": 0.0,
            "smile_score": 1.0,
            "mouth_open_score": 0.0,
        }
        engine.update_challenge_status(empty_metrics, has_valid_face=True, now=100.0)
        engine.pause_current_challenge()
        paused = engine.current_challenge()
        self.assertIsNone(paused.started_at)
        self.assertEqual("PENDING", paused.status)

        engine.update_challenge_status(empty_metrics, has_valid_face=True, now=1000.0)
        resumed = engine.current_challenge()
        self.assertFalse(engine.failed)
        self.assertEqual(0, resumed.attempts_used)
        self.assertEqual(1000.0, resumed.started_at)

    def test_liveness_uses_three_unique_actions_from_configured_pool(self) -> None:
        config = load_config()
        engine = LivenessChallengeEngine(config)
        action_ids = [item.action_id for item in engine.challenges]
        self.assertEqual(3, len(action_ids))
        self.assertEqual(3, len(set(action_ids)))
        self.assertTrue(set(action_ids).issubset(set(config["liveness"]["challenge_actions"])))

    def test_blink_requires_open_eye_baseline_before_closed_eye_frame(self) -> None:
        config = load_config()
        config["liveness"]["challenge_actions"] = ["blink"]
        config["liveness"]["number_of_challenges"] = 1
        engine = LivenessChallengeEngine(config)
        closed = {
            "yaw": 0.0,
            "pitch": 0.0,
            "roll": 0.0,
            "eye_aspect_ratio": 0.10,
            "blink_score": 0.90,
            "smile_score": 1.0,
            "mouth_open_score": 0.0,
        }
        open_eye = {**closed, "eye_aspect_ratio": 0.35, "blink_score": 0.0}

        engine.update_challenge_status(closed, now=100.0)
        self.assertFalse(engine.current_challenge().baseline_seen)
        engine.update_challenge_status(open_eye, now=100.2)
        self.assertTrue(engine.current_challenge().baseline_seen)
        engine.update_challenge_status(closed, now=100.5)
        self.assertTrue(engine.passed)

    def test_safe_face_database_round_trip_and_checksum(self) -> None:
        payload = {
            "version": 2,
            "persons": {
                "person_A": {
                    "embeddings": np.asarray([[1.0, 0.0]], dtype=np.float32),
                    "mean_embedding": np.asarray([1.0, 0.0], dtype=np.float32),
                    "images": [],
                    "valid_image_count": 1,
                }
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "face_db.json"
            save_face_database(path, payload)
            loaded = load_face_database(path)
            self.assertEqual([1.0, 0.0], loaded["persons"]["person_A"]["mean_embedding"])
            envelope = json.loads(path.read_text(encoding="utf-8"))
            envelope["payload"]["persons"]["person_A"]["mean_embedding"][0] = 0.5
            path.write_text(json.dumps(envelope), encoding="utf-8")
            with self.assertRaises(Exception):
                load_face_database(path)


class PipelineTests(unittest.TestCase):
    def setUp(self) -> None:
        config = load_config()
        config["backend"]["max_frame_dimension"] = 960
        config["backend"]["allow_skip_liveness"] = True
        config["multi_frame"]["min_samples"] = 1
        config["multi_frame"]["sample_interval_seconds"] = 0.0
        self.settings = BackendSettings.from_config(config)
        self.runtime = FakeRuntime()
        self.store = SessionStore(60.0, 4)
        self.pipeline = AuthenticationPipeline(
            self.settings,
            self.runtime,  # type: ignore[arg-type]
            self.store,
            QuietLogger(),
        )

    def tearDown(self) -> None:
        self.pipeline.close()

    def test_orientation_is_calibrated_once_then_cached(self) -> None:
        created = self.pipeline.create_session("person_A")
        session_id = created["session_id"]
        first = self.pipeline.process_frame(session_id, jpeg_bytes(), False, -1)
        second = self.pipeline.process_frame(session_id, jpeg_bytes(value=129), False, -1)
        self.assertIn("calibrated", first["frame_orientation"])
        self.assertIn("cached", second["frame_orientation"])
        self.assertEqual(5, self.runtime.detect_calls)

    def test_verification_runs_in_background(self) -> None:
        created = self.pipeline.create_session("person_A", skip_liveness=True)
        session_id = created["session_id"]
        response = self.pipeline.process_frame(session_id, jpeg_bytes(240, 120), False, 0)
        self.assertEqual("VERIFYING", response["stage"])
        deadline = time.monotonic() + 1.0
        status = response
        while time.monotonic() < deadline:
            status = self.pipeline.get_status(session_id)
            if status["stage"] != "VERIFYING":
                break
            time.sleep(0.01)
        self.assertEqual("SUCCESS", status["stage"])

    def test_identity_recognition_starts_while_liveness_is_still_running(self) -> None:
        class TrackingRuntime(FakeRuntime):
            def __init__(self) -> None:
                super().__init__()
                self.verification_started = Event()

            def verify_frames(self, *_args, **_kwargs) -> VerificationOutcome:
                self.verification_started.set()
                return VerificationOutcome(None, True, "SUCCESS: test", 10.0, "SUCCESS")

        config = load_config()
        config["backend"]["max_frame_dimension"] = 960
        config["multi_frame"]["min_samples"] = 1
        config["multi_frame"]["recognition_sample_count"] = 1
        config["multi_frame"]["sample_interval_seconds"] = 0.0
        settings = BackendSettings.from_config(config)
        runtime = TrackingRuntime()
        store = SessionStore(60.0, 4)
        pipeline = AuthenticationPipeline(
            settings,
            runtime,  # type: ignore[arg-type]
            store,
            QuietLogger(),
        )
        try:
            created = pipeline.create_session("person_A")
            session_id = created["session_id"]
            first = pipeline.process_frame(session_id, jpeg_bytes(), False, -1)
            self.assertEqual("LIVENESS", first["stage"])
            self.assertTrue(runtime.verification_started.wait(1.0))

            deadline = time.monotonic() + 1.0
            session = store.get(session_id)
            while session.identity_precheck_outcome is None and time.monotonic() < deadline:
                time.sleep(0.005)
            self.assertIsNotNone(session.identity_precheck_outcome)

            with session.lock:
                session.engine.passed = True
            # A passing early check is only provisional. The final frontal frame
            # is deliberately verified in a separate background job together
            # with the liveness evidence, so no identity can be swapped during
            # a challenge.
            final = pipeline.process_frame(session_id, jpeg_bytes(value=129), False, -1)
            self.assertEqual("VERIFYING", final["stage"])
            deadline = time.monotonic() + 1.0
            while final["stage"] == "VERIFYING" and time.monotonic() < deadline:
                time.sleep(0.01)
                final = pipeline.get_status(session_id)
            self.assertEqual("SUCCESS", final["stage"])
        finally:
            pipeline.close()

    def test_failed_early_recognition_retries_with_all_samples(self) -> None:
        class RetryRuntime(FakeRuntime):
            def __init__(self) -> None:
                super().__init__()
                self.verify_calls = 0

            def verify_frames(self, *_args, **_kwargs) -> VerificationOutcome:
                self.verify_calls += 1
                if self.verify_calls == 1:
                    return VerificationOutcome(
                        None,
                        False,
                        "FAILED: early sample did not match",
                        10.0,
                        "IDENTITY_NOT_MATCHED",
                    )
                return VerificationOutcome(None, True, "SUCCESS: retry", 20.0, "SUCCESS")

        config = load_config()
        config["backend"]["max_frame_dimension"] = 960
        config["multi_frame"]["min_samples"] = 2
        config["multi_frame"]["recognition_sample_count"] = 1
        config["multi_frame"]["sample_interval_seconds"] = 0.0
        settings = BackendSettings.from_config(config)
        runtime = RetryRuntime()
        store = SessionStore(60.0, 4)
        pipeline = AuthenticationPipeline(
            settings,
            runtime,  # type: ignore[arg-type]
            store,
            QuietLogger(),
        )
        try:
            created = pipeline.create_session("person_A")
            session_id = created["session_id"]
            pipeline.process_frame(session_id, jpeg_bytes(), False, -1)
            session = store.get(session_id)
            deadline = time.monotonic() + 1.0
            while session.identity_precheck_outcome is None and time.monotonic() < deadline:
                time.sleep(0.005)
            self.assertFalse(session.identity_precheck_outcome.passed)

            with session.lock:
                session.engine.passed = True
            response = pipeline.process_frame(
                session_id,
                jpeg_bytes(value=129),
                False,
                -1,
            )
            self.assertEqual("VERIFYING", response["stage"])
            deadline = time.monotonic() + 1.0
            while time.monotonic() < deadline:
                response = pipeline.get_status(session_id)
                if response["stage"] != "VERIFYING":
                    break
                time.sleep(0.005)
            self.assertEqual("SUCCESS", response["stage"])
            self.assertEqual(2, runtime.verify_calls)
        finally:
            pipeline.close()


class HundredSessionCapacityTests(unittest.TestCase):
    def test_one_hundred_sessions_are_accepted_without_unbounded_queue(self) -> None:
        config = load_config()
        config["backend"]["max_sessions"] = 150
        config["backend"]["allow_skip_liveness"] = True
        config["backend"]["verification_workers"] = 8
        config["backend"]["verification_queue_capacity"] = 100
        config["multi_frame"]["min_samples"] = 1
        config["multi_frame"]["sample_interval_seconds"] = 0.0
        settings = BackendSettings.from_config(config)
        runtime = FakeRuntime()
        store = SessionStore(60.0, settings.max_sessions)
        pipeline = AuthenticationPipeline(
            settings,
            runtime,  # type: ignore[arg-type]
            store,
            QuietLogger(),
        )
        try:
            session_ids = [
                pipeline.create_session("person_A", skip_liveness=True)["session_id"]
                for _ in range(100)
            ]
            payload = jpeg_bytes(240, 120)
            with ThreadPoolExecutor(max_workers=25) as executor:
                responses = list(
                    executor.map(
                        lambda session_id: pipeline.process_frame(
                            session_id,
                            payload,
                            False,
                            0,
                        ),
                        session_ids,
                    )
                )
            self.assertTrue(all(response["stage"] == "VERIFYING" for response in responses))

            deadline = time.monotonic() + 3.0
            stages: list[str] = []
            while time.monotonic() < deadline:
                stages = [pipeline.get_status(session_id)["stage"] for session_id in session_ids]
                if all(stage == "SUCCESS" for stage in stages):
                    break
                time.sleep(0.01)
            self.assertEqual(100, stages.count("SUCCESS"))
            self.assertLessEqual(pipeline.verification_queue_pending, settings.verification_queue_capacity)
        finally:
            pipeline.close()


if __name__ == "__main__":
    unittest.main()
