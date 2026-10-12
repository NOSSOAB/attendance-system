from __future__ import annotations

import copy
from collections import Counter
import hashlib
import secrets
from threading import Lock
import time
import uuid
from typing import Any

from modules.face_detector import FaceDetectionResult
from modules.liveness_challenge import LivenessChallengeEngine

from .bounded_executor import BoundedExecutor, ExecutorQueueFullError
from .domain import AuthSession, SessionBusyError, SessionStage, VerificationFrameSample
from .frame_processor import FrameProcessor
from .presenter import build_response
from .runtime import InferenceRuntime, VerificationOutcome
from .session_store import SessionStore
from .settings import BackendSettings


class AuthenticationPipeline:
    """State machine coordinating detection, liveness and final verification."""

    def __init__(
        self,
        settings: BackendSettings,
        runtime: InferenceRuntime,
        sessions: SessionStore,
        logger: Any,
    ) -> None:
        self.settings = settings
        self.runtime = runtime
        self.sessions = sessions
        self.logger = logger
        self.frames = FrameProcessor(settings, runtime, logger)
        self._verification_pool = BoundedExecutor(
            max_workers=settings.verification_workers,
            max_queue_size=settings.verification_queue_capacity,
            thread_name_prefix="face-verification",
        )
        self._metrics_lock = Lock()
        self._outcome_counts: Counter[str] = Counter()
        self._frame_issue_counts: Counter[str] = Counter()
        self._duplicate_frames_rejected = 0

    def create_session(self, target_name: str, skip_liveness: bool = False) -> dict[str, Any]:
        identities = self.runtime.list_identities()
        if target_name not in identities:
            raise ValueError(f"Unknown target_name '{target_name}'. Available: {identities}")
        if skip_liveness and not self.settings.allow_skip_liveness:
            raise ValueError("skip_liveness is disabled; active liveness is required")
        session_token = secrets.token_urlsafe(32)
        session = AuthSession(
            session_id=uuid.uuid4().hex,
            target_name=target_name,
            engine=self._new_engine(skip_liveness),
            session_token_digest=hashlib.sha256(session_token.encode("utf-8")).hexdigest(),
            skip_liveness=skip_liveness,
        )
        self.sessions.add(session)
        challenges = [item.label for item in session.engine.challenges]
        self.logger.info(
            "Session started id=%s target=%s skip_liveness=%s challenges=%s",
            session.session_id,
            target_name,
            skip_liveness,
            challenges,
        )
        response = self._response(session)
        response["session_token"] = session_token
        return response

    def get_status(self, session_id: str) -> dict[str, Any]:
        session = self.sessions.get(session_id)
        with session.lock:
            return self._response(session, session.latest_detection)

    def reset_session(self, session_id: str) -> dict[str, Any]:
        session = self.sessions.get(session_id)
        with session.lock:
            session.generation += 1
            session.engine = self._new_engine(session.skip_liveness)
            session.stage = SessionStage.LIVENESS
            session.final_message = ""
            session.frame_count = 0
            session.rotation_degrees = None
            session.last_orientation = "uncalibrated"
            session.best_frame = None
            session.best_bbox = None
            session.best_frame_quality = -1.0
            session.verification_samples.clear()
            session.identity_samples.clear()
            session.last_sample_at = None
            session.latest_detection = None
            session.recognition_result = None
            session.last_processing_ms = 0.0
            session.verification_ms = 0.0
            session.verification_started_at = None
            session.identity_precheck_started = False
            session.identity_precheck_outcome = None
            session.identity_retry_started = False
            session.result_code = "IN_PROGRESS"
            session.recent_frame_digests.clear()
            session.duplicate_frames_rejected = 0
            session.metadata.clear()
            session.touch()
            self.logger.info("Session reset id=%s generation=%d", session.session_id, session.generation)
            return self._response(session)

    def delete_session(self, session_id: str) -> bool:
        return self.sessions.remove(session_id)

    def process_frame(
        self,
        session_id: str,
        content: bytes,
        mirror: bool = False,
        rotation_degrees: int = -1,
    ) -> dict[str, Any]:
        session = self.sessions.get(session_id)
        if not session.lock.acquire(blocking=False):
            raise SessionBusyError("A frame for this session is already being processed")

        verification_payload: tuple[
            int,
            list[VerificationFrameSample],
            str,
            bool,
        ] | None = None
        try:
            session.touch()
            if session.stage != SessionStage.LIVENESS:
                return self._response(session, session.latest_detection)

            frame_digest = hashlib.sha256(content).hexdigest()
            if frame_digest in session.recent_frame_digests:
                session.duplicate_frames_rejected += 1
                with self._metrics_lock:
                    self._duplicate_frames_rejected += 1
                session.touch()
                return build_response(
                    session,
                    session.latest_detection,
                    session.engine.snapshot("Frame trùng đã bị từ chối để chống phát lại"),
                    self.frames.dominant_face_ok,
                )
            session.recent_frame_digests.append(frame_digest)
            del session.recent_frame_digests[:-24]

            started = time.perf_counter()
            frame = self.frames.decode_frame(content)
            frame, detection, orientation = self.frames.prepare_and_detect(
                session,
                frame,
                mirror=mirror,
                rotation_degrees=rotation_degrees,
            )
            session.frame_count += 1
            session.last_orientation = orientation
            session.latest_detection = detection
            session.metadata["mirror"] = mirror
            self.frames.maybe_save_debug_frame(session, frame)

            metrics = self.runtime.detector.detection_metrics(detection) if self.runtime.detector else {}
            valid_face = self.frames.has_face_for_liveness(detection)
            if not valid_face:
                self._record_frame_issue(detection)
            if valid_face:
                already_passed = session.engine.passed
                previous_index = session.engine.current_index
                previous_challenge = session.engine.current_challenge()
                had_baseline = bool(previous_challenge and previous_challenge.baseline_seen)
                sample_group = previous_index
                if not session.engine.enabled:
                    sample_group = (session.frame_count - 1) // self.settings.samples_per_challenge
                self.frames.remember_verification_sample(
                    session,
                    frame,
                    detection,
                    challenge_index=sample_group,
                )
                liveness = session.engine.update_challenge_status(metrics, has_valid_face=True)
                if session.engine.enabled:
                    self._remember_identity_evidence(
                        session, frame, detection, previous_index,
                        previous_challenge, had_baseline, already_passed,
                    )
                if session.engine.current_index > previous_index and previous_challenge is not None:
                    self.logger.info(
                        "Liveness challenge passed id=%s action=%s confidence=%.3f yaw=%.1f pitch=%.1f roll=%.1f",
                        session.session_id,
                        previous_challenge.action_id,
                        previous_challenge.confidence,
                        float(metrics.get("yaw", 0.0)),
                        float(metrics.get("pitch", 0.0)),
                        float(metrics.get("roll", 0.0)),
                    )

                if (
                    not session.engine.passed
                    and not session.engine.failed
                    and not session.identity_precheck_started
                    and len(session.verification_samples)
                    >= self.settings.recognition_sample_count
                ):
                    session.identity_precheck_started = True
                    session.verification_started_at = time.monotonic()
                    verification_payload = (
                        session.generation,
                        list(session.verification_samples),
                        session.target_name,
                        True,
                    )
                    self.logger.info(
                        "Early identity recognition queued id=%s target=%s samples=%d",
                        session.session_id,
                        session.target_name,
                        len(session.verification_samples),
                    )
            else:
                session.engine.pause_current_challenge()
                if not session.engine.passed:
                    self._clear_identity_evidence(session, session.engine.current_index)
                liveness = session.engine.snapshot(self.frames.face_waiting_message(detection))

            if session.engine.failed:
                session.stage = SessionStage.FAILED
                session.result_code = "LIVENESS_FAILED"
                session.final_message = "FAILED: liveness challenge failed"
                self._record_terminal_locked(session)
                self.logger.info("Liveness failed id=%s target=%s", session.session_id, session.target_name)
            elif session.engine.passed:
                if session.engine.enabled and (-1, "final") not in session.identity_samples:
                    session.final_message = "Nhìn thẳng vào camera để xác nhận danh tính cuối phiên"
                elif len(session.verification_samples) < self.settings.min_verification_samples:
                    session.final_message = (
                        "Giữ khuôn mặt trong khung hình để thu đủ mẫu "
                        f"({len(session.verification_samples)}/{self.settings.min_verification_samples})"
                    )
                else:
                    session.stage = SessionStage.VERIFYING
                    session.identity_retry_started = session.identity_precheck_started
                    session.final_message = "Đang xác minh danh tính xuyên suốt các thử thách"
                    session.verification_started_at = time.monotonic()
                    verification_payload = (
                        session.generation,
                        list(session.verification_samples) + list(session.identity_samples.values()),
                        session.target_name,
                        False,
                    )

            session.last_processing_ms = (time.perf_counter() - started) * 1000
            response = build_response(
                session,
                detection,
                liveness,
                self.frames.dominant_face_ok,
            )
        finally:
            session.lock.release()

        if verification_payload is not None:
            generation, samples, target_name, early = verification_payload
            try:
                self._verification_pool.submit(
                    self._verify_in_background,
                    session,
                    generation,
                    samples,
                    target_name,
                    early,
                )
            except ExecutorQueueFullError:
                with session.lock:
                    if (
                        early
                        and session.generation == generation
                        and session.stage == SessionStage.LIVENESS
                    ):
                        session.identity_precheck_started = False
                        session.verification_started_at = None
                    elif session.generation == generation and session.stage == SessionStage.VERIFYING:
                        session.stage = SessionStage.FAILED
                        session.result_code = "SERVER_BUSY"
                        session.final_message = "FAILED: server busy; vui lòng thử lại"
                        self._record_terminal_locked(session)
                        session.touch()
        return response

    def close(self) -> None:
        self._verification_pool.shutdown(wait=True, cancel_futures=True)

    @staticmethod
    def _clear_identity_evidence(session: AuthSession, index: int, actions_only: bool = False) -> None:
        for key in list(session.identity_samples):
            if key[0] == index and (not actions_only or key[1].startswith("action_")):
                del session.identity_samples[key]

    def _remember_identity_evidence(
        self, session: AuthSession, frame: Any, detection: FaceDetectionResult,
        index: int, challenge: Any, had_baseline: bool, already_passed: bool,
    ) -> None:
        if already_passed:
            face = detection.primary_face
            if face and max(abs(face.yaw), abs(face.pitch), abs(face.roll)) <= self.settings.final_pose_limit:
                self.frames.remember_identity_sample(session, frame, detection, -1, "final")
            return
        if challenge is None:
            return
        if not challenge.baseline_seen:
            self._clear_identity_evidence(session, index)
        elif not had_baseline:
            self._clear_identity_evidence(session, index)
            self.frames.remember_identity_sample(session, frame, detection, index, "baseline")
        if challenge.evidence_frames == 0:
            self._clear_identity_evidence(session, index, actions_only=True)
        else:
            self.frames.remember_identity_sample(
                session, frame, detection, index, f"action_{challenge.evidence_frames}"
            )

    @property
    def verification_queue_pending(self) -> int:
        return self._verification_pool.pending

    @property
    def verification_queue_waiting(self) -> int:
        return self._verification_pool.waiting

    @property
    def verification_queue_peak(self) -> int:
        return self._verification_pool.peak_pending

    @property
    def outcome_counts(self) -> dict[str, int]:
        with self._metrics_lock:
            return dict(sorted(self._outcome_counts.items()))

    @property
    def duplicate_frames_rejected(self) -> int:
        with self._metrics_lock:
            return self._duplicate_frames_rejected

    @property
    def frame_issue_counts(self) -> dict[str, int]:
        with self._metrics_lock:
            return dict(sorted(self._frame_issue_counts.items()))

    def _new_engine(self, skip_liveness: bool) -> LivenessChallengeEngine:
        config = copy.deepcopy(self.settings.config)
        if skip_liveness:
            config.setdefault("liveness", {})["enabled"] = False
        return LivenessChallengeEngine(config)

    def _response(
        self,
        session: AuthSession,
        detection: FaceDetectionResult | None = None,
    ) -> dict[str, Any]:
        return build_response(
            session,
            detection,
            session.engine.snapshot(),
            self.frames.dominant_face_ok,
        )

    def _verify_in_background(
        self,
        session: AuthSession,
        generation: int,
        samples: list[VerificationFrameSample],
        target_name: str,
        early: bool = False,
    ) -> None:
        with session.lock:
            if session.generation != generation:
                return
            challenge_frame_counts = (
                tuple(
                    1 if item.action_id == "blink" else session.engine.confirmation_frames
                    for item in session.engine.challenges
                )
                if not early and session.engine.enabled else None
            )
        try:
            outcome = self.runtime.verify_frames(
                samples,
                target_name,
                minimum_samples=(self.settings.recognition_sample_count if early else None),
                challenge_frame_counts=challenge_frame_counts,
            )
        except Exception as exc:  # pragma: no cover - defensive boundary around native runtimes
            self.logger.exception(
                "Backend inference failed id=%s target=%s",
                session.session_id,
                target_name,
            )
            outcome = VerificationOutcome(
                recognition=None,
                passed=False,
                message="FAILED: backend inference error",
                elapsed_ms=0.0,
                code="INFERENCE_ERROR",
            )

        with session.lock:
            if session.generation != generation:
                return
            if early:
                # An early result is provisional even if it arrives after liveness.
                # Only the separate job containing challenge evidence may finish a session.
                if not session.terminal:
                    session.identity_precheck_outcome = outcome
                    session.touch()
                return
            if session.stage != SessionStage.VERIFYING:
                return
            self._apply_verification_outcome_locked(session, outcome, target_name)

    def _apply_verification_outcome_locked(
        self,
        session: AuthSession,
        outcome: VerificationOutcome,
        target_name: str,
    ) -> None:
        session.recognition_result = outcome.recognition
        session.verification_ms = outcome.elapsed_ms
        session.stage = SessionStage.SUCCESS if outcome.passed else SessionStage.FAILED
        session.result_code = outcome.code or (
            "SUCCESS" if outcome.passed else "IDENTITY_NOT_MATCHED"
        )
        session.final_message = outcome.message
        session.best_frame = None
        session.best_bbox = None
        session.verification_samples.clear()
        session.identity_samples.clear()
        session.identity_precheck_outcome = None
        self._record_terminal_locked(session)
        session.touch()
        similarity = outcome.recognition.similarity if outcome.recognition else 0.0
        self.logger.info(
            "Verification completed id=%s target=%s stage=%s code=%s similarity=%.3f elapsed=%.1fms message=%s",
            session.session_id,
            target_name,
            session.stage.value,
            session.result_code,
            similarity,
            outcome.elapsed_ms,
            outcome.message,
        )

    def _record_terminal_locked(self, session: AuthSession) -> None:
        if session.metadata.get("terminal_recorded"):
            return
        session.metadata["terminal_recorded"] = True
        with self._metrics_lock:
            self._outcome_counts[session.result_code] += 1

    def _record_frame_issue(self, detection: FaceDetectionResult) -> None:
        face = detection.primary_face
        if detection.face_count == 0 or face is None:
            code = "NO_FACE"
        elif detection.face_count > 1 and not self.frames.dominant_face_ok(detection):
            code = "MULTIPLE_FACES"
        elif not face.checks.get("face_size", False):
            code = "FACE_SIZE"
        elif not face.checks.get("centered", False):
            code = "NOT_CENTERED"
        elif not face.checks.get("brightness", False):
            code = "LIGHTING"
        else:
            code = "FACE_QUALITY"
        with self._metrics_lock:
            self._frame_issue_counts[code] += 1
