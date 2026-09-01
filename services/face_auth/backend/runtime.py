from __future__ import annotations

from dataclasses import dataclass
import math
from threading import Lock
import time
from typing import Any

import cv2
import numpy as np

from modules.face_detector import FaceDetectionResult, MediaPipeFaceDetector
from modules.face_recognizer import InsightFaceRecognizer, RecognitionResult

from .domain import VerificationFrameSample
from .resource_pool import ResourcePool
from .settings import BackendSettings


@dataclass
class VerificationOutcome:
    recognition: RecognitionResult | None
    passed: bool
    message: str
    elapsed_ms: float
    code: str = ""


@dataclass
class VerificationWorker:
    """One independent recognition model instance."""

    recognizer: InsightFaceRecognizer


class InferenceRuntime:
    """Owns PC-side models and runs bounded multi-frame verification."""

    def __init__(self, settings: BackendSettings, logger: Any) -> None:
        self.settings = settings
        self.config = settings.config
        self.logger = logger
        self.detector: MediaPipeFaceDetector | None = None
        self.recognizer: InsightFaceRecognizer | None = None
        self._detector_pool: ResourcePool[MediaPipeFaceDetector] | None = None
        self._verification_model_pool: ResourcePool[VerificationWorker] | None = None
        self._load_lock = Lock()
        self._database_reload_lock = Lock()
        self._face_db_mtime_ns = -1
        self.loaded_at: float | None = None
        self.load_seconds = 0.0

    def load(self) -> None:
        if self.ready:
            return
        with self._load_lock:
            if self.ready:
                return
            started = time.perf_counter()
            self.logger.info(
                "Loading model pools: detectors=%d verification_workers=%d",
                self.settings.detector_workers,
                self.settings.verification_workers,
            )
            detectors: list[MediaPipeFaceDetector] = []
            verification_workers: list[VerificationWorker] = []
            try:
                detectors = [
                    MediaPipeFaceDetector(self.config)
                    for _ in range(self.settings.detector_workers)
                ]
                for _ in range(self.settings.verification_workers):
                    recognizer = InsightFaceRecognizer(self.config)
                    recognizer.load_database()
                    recognizer._ensure_recognition_model()
                    verification_workers.append(
                        VerificationWorker(
                            recognizer=recognizer,
                        )
                    )
            except Exception:
                for detector in detectors:
                    close = getattr(getattr(detector, "landmarker", None), "close", None)
                    if callable(close):
                        close()
                raise

            self._detector_pool = ResourcePool(detectors)
            self._verification_model_pool = ResourcePool(verification_workers)
            self.detector = detectors[0]
            self.recognizer = verification_workers[0].recognizer
            self._face_db_mtime_ns = self._database_mtime_ns()
            self.loaded_at = time.time()
            self.load_seconds = time.perf_counter() - started
            self.logger.info("All backend models loaded in %.2f seconds", self.load_seconds)

    @property
    def ready(self) -> bool:
        return (
            self.detector is not None
            and self.recognizer is not None
            and self._detector_pool is not None
            and self._verification_model_pool is not None
        )

    @property
    def detector_worker_count(self) -> int:
        pool = self._detector_pool
        return pool.capacity if pool is not None else 0

    @property
    def detector_workers_in_use(self) -> int:
        pool = self._detector_pool
        return pool.in_use if pool is not None else 0

    @property
    def detector_workers_peak(self) -> int:
        pool = self._detector_pool
        return pool.peak_in_use if pool is not None else 0

    @property
    def verification_model_workers_in_use(self) -> int:
        pool = self._verification_model_pool
        return pool.in_use if pool is not None else 0

    @property
    def verification_model_workers_peak(self) -> int:
        pool = self._verification_model_pool
        return pool.peak_in_use if pool is not None else 0

    def detect(self, frame_bgr: np.ndarray) -> FaceDetectionResult:
        self.load()
        pool = self._detector_pool
        assert pool is not None
        with pool.checkout() as detector:
            return detector.detect(frame_bgr)

    def verify_frames(
        self,
        samples: list[VerificationFrameSample],
        target_name: str,
        minimum_samples: int | None = None,
    ) -> VerificationOutcome:
        self.load()
        pool = self._verification_model_pool
        assert pool is not None
        with pool.checkout() as worker:
            return self._verify_frames_on_worker(
                samples,
                target_name,
                worker,
                minimum_samples=minimum_samples,
            )

    def _verify_frames_on_worker(
        self,
        samples: list[VerificationFrameSample],
        target_name: str,
        worker: VerificationWorker,
        minimum_samples: int | None = None,
    ) -> VerificationOutcome:
        recognizer = worker.recognizer
        started = time.perf_counter()

        required_samples = (
            self.settings.min_verification_samples
            if minimum_samples is None
            else max(1, minimum_samples)
        )
        if len(samples) < required_samples:
            return VerificationOutcome(
                recognition=None,
                passed=False,
                message=(
                    "FAILED: insufficient multi-frame samples "
                    f"({len(samples)}/{required_samples})"
                ),
                elapsed_ms=(time.perf_counter() - started) * 1000,
                code="INSUFFICIENT_SAMPLES",
            )

        decoded = _decode_samples(samples)
        if len(decoded) < required_samples:
            return VerificationOutcome(
                recognition=None,
                passed=False,
                message="FAILED: cannot decode enough multi-frame samples",
                elapsed_ms=(time.perf_counter() - started) * 1000,
                code="FRAME_DECODE_FAILED",
            )

        recognition_inputs = _select_quality_across_time(
            decoded,
            self.settings.recognition_sample_count,
        )
        if recognition_inputs and all(
            sample.recognition_keypoints is not None for sample, _frame in recognition_inputs
        ):
            recognition_results = recognizer.recognize_many_with_keypoints(
                [frame for _sample, frame in recognition_inputs],
                [
                    sample.recognition_keypoints
                    for sample, _frame in recognition_inputs
                    if sample.recognition_keypoints is not None
                ],
                target_name=target_name,
            )
        else:
            recognition_results = []
            for sample, frame in recognition_inputs:
                if sample.recognition_keypoints is not None:
                    recognition_results.append(
                        recognizer.recognize_with_keypoints(
                            frame,
                            sample.recognition_keypoints,
                            target_name=target_name,
                        )
                    )
                else:
                    recognition_results.append(
                        recognizer.recognize(frame, target_name=target_name)
                    )

        recognition = _aggregate_recognition_results(
            recognition_results,
            target_name,
            recognizer.threshold,
            self.settings.min_recognition_pass_ratio,
        )
        if recognition.error:
            self.logger.error("Recognition failed target=%s error=%s", target_name, recognition.error)
            return VerificationOutcome(
                recognition=recognition,
                passed=False,
                message="FAILED: recognition error",
                elapsed_ms=(time.perf_counter() - started) * 1000,
                code="RECOGNITION_ERROR",
            )

        passed = recognition.is_recognized
        return VerificationOutcome(
            recognition=recognition,
            passed=passed,
            message=(
                "SUCCESS: active liveness and multi-frame face recognition passed"
                if passed
                else "FAILED: identity not matched across enough frames"
            ),
            elapsed_ms=(time.perf_counter() - started) * 1000,
            code="SUCCESS" if passed else "IDENTITY_NOT_MATCHED",
        )

    def verify(
        self,
        frame_bgr: np.ndarray,
        face_bbox: tuple[int, int, int, int],
        target_name: str,
    ) -> VerificationOutcome:
        """Compatibility wrapper for non-API desktop callers."""
        ok, encoded = cv2.imencode(".jpg", frame_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
        if not ok:
            return VerificationOutcome(
                None,
                False,
                "FAILED: cannot encode frame",
                0.0,
                "FRAME_ENCODE_FAILED",
            )
        sample = VerificationFrameSample(
            jpeg_bytes=encoded.tobytes(),
            bbox=face_bbox,
            quality=1.0,
            captured_at=time.monotonic(),
            challenge_index=0,
        )
        original_min = self.settings.min_verification_samples
        if original_min > 1:
            # A single-frame wrapper remains available only for legacy desktop tools.
            samples = [sample for _ in range(original_min)]
        else:
            samples = [sample]
        return self.verify_frames(samples, target_name)

    def list_identities(self, reload_if_changed: bool = True) -> list[str]:
        self.load()
        assert self.recognizer is not None
        if reload_if_changed:
            current_mtime = self._database_mtime_ns()
            if current_mtime != self._face_db_mtime_ns:
                self._reload_all_databases(current_mtime)
                self.logger.info("Reloaded face database after data change")
        return self.recognizer.list_people(force_reload=False)

    def reload_database(self) -> list[str]:
        self.load()
        assert self.recognizer is not None
        self._reload_all_databases(self._database_mtime_ns())
        return self.recognizer.list_people(force_reload=False)

    def close(self) -> None:
        pool = self._detector_pool
        if pool is None:
            return
        for detector in pool.resources:
            close = getattr(getattr(detector, "landmarker", None), "close", None)
            if callable(close):
                close()

    def _reload_all_databases(self, mtime_ns: int) -> None:
        pool = self._verification_model_pool
        if pool is None:
            return
        with self._database_reload_lock:
            for worker in pool.resources:
                worker.recognizer.load_database()
            self._face_db_mtime_ns = mtime_ns

    def _database_mtime_ns(self) -> int:
        recognizer = self.recognizer
        return recognizer.database_revision() if recognizer is not None else -1


def _decode_samples(
    samples: list[VerificationFrameSample],
) -> list[tuple[VerificationFrameSample, np.ndarray]]:
    decoded: list[tuple[VerificationFrameSample, np.ndarray]] = []
    for sample in sorted(samples, key=lambda item: item.captured_at):
        array = np.frombuffer(sample.jpeg_bytes, dtype=np.uint8)
        frame = cv2.imdecode(array, cv2.IMREAD_COLOR)
        if frame is not None:
            decoded.append((sample, frame))
    return decoded


def _select_temporal_samples(
    items: list[tuple[VerificationFrameSample, np.ndarray]],
    count: int,
) -> list[tuple[VerificationFrameSample, np.ndarray]]:
    if len(items) <= count:
        return items
    indices = np.linspace(0, len(items) - 1, num=count, dtype=int)
    return [items[int(index)] for index in indices]


def _select_quality_across_time(
    items: list[tuple[VerificationFrameSample, np.ndarray]],
    count: int,
) -> list[tuple[VerificationFrameSample, np.ndarray]]:
    if len(items) <= count:
        return sorted(items, key=lambda item: item[0].quality, reverse=True)
    boundaries = np.linspace(0, len(items), num=count + 1, dtype=int)
    selected: list[tuple[VerificationFrameSample, np.ndarray]] = []
    for index in range(count):
        bucket = items[int(boundaries[index]) : int(boundaries[index + 1])]
        if bucket:
            selected.append(max(bucket, key=lambda item: item[0].quality))
    return selected


def _aggregate_recognition_results(
    results: list[RecognitionResult],
    target_name: str,
    threshold: float,
    pass_ratio: float,
) -> RecognitionResult:
    errors = [result.error for result in results if result.error]
    if not results or errors:
        return RecognitionResult(
            best_match_name="UNKNOWN",
            similarity_percent=0.0,
            similarity=0.0,
            distance=1.0,
            recognition_threshold=threshold,
            is_recognized=False,
            error="; ".join(errors) if errors else "No recognition samples",
            sample_count=len(results),
            passed_count=0,
            similarities=[],
        )

    similarities = [float(result.similarity) for result in results]
    median = float(np.median(np.asarray(similarities, dtype=np.float64)))
    passed_count = sum(result.is_recognized for result in results)
    required = max(1, math.ceil(len(results) * pass_ratio))
    is_recognized = passed_count >= required and median >= threshold
    representative = max(results, key=lambda result: result.similarity)
    return RecognitionResult(
        best_match_name=target_name if is_recognized else f"{target_name} (dưới ngưỡng)",
        similarity_percent=max(0.0, min(100.0, median * 100.0)),
        similarity=median,
        distance=1.0 - median,
        recognition_threshold=threshold,
        is_recognized=is_recognized,
        candidate_image=representative.candidate_image,
        match_strategy="multi_frame_median",
        face_count=max(result.face_count for result in results),
        sample_count=len(results),
        passed_count=passed_count,
        median_similarity=median,
        similarities=similarities,
    )
