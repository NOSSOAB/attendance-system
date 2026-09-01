from __future__ import annotations

import time
from typing import Any

import cv2
import numpy as np

from modules.face_detector import FaceDetectionResult
from modules.face_quality import score_recognition_frame

from .domain import AuthSession, VerificationFrameSample
from .runtime import InferenceRuntime
from .settings import BackendSettings


VALID_ROTATIONS = {0, 90, 180, 270}


class FrameProcessor:
    """Decodes frames, normalizes camera orientation and selects quality frames."""

    def __init__(self, settings: BackendSettings, runtime: InferenceRuntime, logger: Any) -> None:
        self.settings = settings
        self.runtime = runtime
        self.logger = logger

    def decode_frame(self, content: bytes) -> np.ndarray:
        if not content:
            raise ValueError("Uploaded image is empty")
        array = np.frombuffer(content, dtype=np.uint8)
        frame = cv2.imdecode(array, cv2.IMREAD_COLOR)
        if frame is None:
            raise ValueError("Cannot decode uploaded image")
        height, width = frame.shape[:2]
        longest = max(height, width)
        if longest > self.settings.max_frame_dimension:
            scale = self.settings.max_frame_dimension / float(longest)
            frame = cv2.resize(
                frame,
                (max(1, int(width * scale)), max(1, int(height * scale))),
                interpolation=cv2.INTER_AREA,
            )
        return frame

    def prepare_and_detect(
        self,
        session: AuthSession,
        frame: np.ndarray,
        mirror: bool,
        rotation_degrees: int,
    ) -> tuple[np.ndarray, FaceDetectionResult, str]:
        if rotation_degrees != -1 and rotation_degrees not in VALID_ROTATIONS:
            raise ValueError("rotation_degrees must be -1, 0, 90, 180 or 270")

        previous_mirror = session.metadata.get("mirror")
        if previous_mirror is not None and previous_mirror != mirror:
            session.rotation_degrees = None

        if rotation_degrees in VALID_ROTATIONS:
            selected = self._apply_transform(frame, rotation_degrees, mirror)
            detection = self.runtime.detect(selected)
            session.rotation_degrees = rotation_degrees
            return selected, detection, self._orientation_label(rotation_degrees, "client")

        if session.rotation_degrees is not None:
            selected = self._apply_transform(frame, session.rotation_degrees, mirror)
            detection = self.runtime.detect(selected)
            return selected, detection, self._orientation_label(session.rotation_degrees, "cached")

        if not self.settings.auto_orient:
            selected = self._apply_transform(frame, 0, mirror)
            detection = self.runtime.detect(selected)
            return selected, detection, self._orientation_label(0, "default")

        best_frame = frame
        best_detection: FaceDetectionResult | None = None
        best_rotation = 0
        best_score = float("-inf")
        for candidate_rotation in (0, 90, 270, 180):
            candidate = self._apply_transform(frame, candidate_rotation, mirror)
            detection = self.runtime.detect(candidate)
            score = self._orientation_score(detection)
            if score > best_score:
                best_frame = candidate
                best_detection = detection
                best_rotation = candidate_rotation
                best_score = score

        assert best_detection is not None
        if best_detection.primary_face is not None:
            session.rotation_degrees = best_rotation
            source = "calibrated"
            self.logger.info(
                "Orientation calibrated id=%s rotation=%d mirror=%s",
                session.session_id,
                best_rotation,
                mirror,
            )
        else:
            source = "calibration_pending"
        return best_frame, best_detection, self._orientation_label(best_rotation, source)

    def dominant_face_ok(self, detection: FaceDetectionResult) -> bool:
        if detection.face_count <= 1:
            return True
        areas = sorted(
            (max(0, face.bbox_xywh[2]) * max(0, face.bbox_xywh[3]) for face in detection.faces),
            reverse=True,
        )
        return len(areas) < 2 or areas[1] <= 0 or areas[0] / areas[1] >= self.settings.dominant_face_ratio

    def has_face_for_liveness(self, detection: FaceDetectionResult) -> bool:
        face = detection.primary_face
        return bool(
            face
            and face.checks.get("detected")
            and self.dominant_face_ok(detection)
            and face.checks.get("face_size")
            and face.checks.get("centered")
            and face.checks.get("brightness")
        )

    def remember_best_frame(
        self,
        session: AuthSession,
        frame: np.ndarray,
        detection: FaceDetectionResult,
    ) -> None:
        face = detection.primary_face
        if face is None:
            return
        quality = score_recognition_frame(detection, self.settings.final_pose_limit)
        if quality > session.best_frame_quality:
            session.best_frame = frame.copy()
            session.best_bbox = face.bbox
            session.best_frame_quality = quality

    def remember_verification_sample(
        self,
        session: AuthSession,
        frame: np.ndarray,
        detection: FaceDetectionResult,
        challenge_index: int,
        captured_at: float | None = None,
    ) -> bool:
        """Keep a small, compressed and temporally spaced frame sample."""
        face = detection.primary_face
        if face is None:
            return False
        quality = score_recognition_frame(detection, self.settings.final_pose_limit)
        if quality < 0:
            return False

        captured_at = time.monotonic() if captured_at is None else captured_at
        if (
            session.last_sample_at is not None
            and captured_at - session.last_sample_at < self.settings.sample_interval_seconds
        ):
            return False

        same_challenge = [
            sample
            for sample in session.verification_samples
            if sample.challenge_index == challenge_index
        ]
        if len(same_challenge) >= self.settings.samples_per_challenge:
            weakest = min(same_challenge, key=lambda sample: sample.quality)
            if quality <= weakest.quality:
                return False
            session.verification_samples.remove(weakest)

        ok, encoded = cv2.imencode(
            ".jpg",
            frame,
            [int(cv2.IMWRITE_JPEG_QUALITY), self.settings.sample_jpeg_quality],
        )
        if not ok:
            return False
        session.verification_samples.append(
            VerificationFrameSample(
                jpeg_bytes=encoded.tobytes(),
                bbox=face.bbox,
                quality=quality,
                captured_at=captured_at,
                challenge_index=challenge_index,
                recognition_keypoints=_insightface_keypoints(face.landmarks_px),
            )
        )
        session.verification_samples.sort(key=lambda sample: sample.captured_at)
        while len(session.verification_samples) > self.settings.max_verification_samples:
            session.verification_samples.pop(0)
        session.last_sample_at = captured_at
        session.best_frame_quality = max(session.best_frame_quality, quality)
        return True

    @staticmethod
    def face_waiting_message(detection: FaceDetectionResult) -> str:
        if detection.face_count == 0:
            return "Khong phat hien khuon mat"
        if detection.face_count > 1:
            return "Chi de 1 khuon mat chinh trong khung hinh"
        return detection.messages[0] if detection.messages else "Khuon mat chua dat yeu cau"

    def maybe_save_debug_frame(self, session: AuthSession, frame: np.ndarray) -> None:
        if not self.settings.debug_save_frames:
            return
        if session.frame_count % self.settings.debug_frame_interval != 1:
            return
        self.settings.output_path.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(self.settings.output_path / f"session_{session.session_id}_last.jpg"), frame)

    @staticmethod
    def _apply_transform(frame: np.ndarray, rotation_degrees: int, mirror: bool) -> np.ndarray:
        if rotation_degrees == 90:
            transformed = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
        elif rotation_degrees == 180:
            transformed = cv2.rotate(frame, cv2.ROTATE_180)
        elif rotation_degrees == 270:
            transformed = cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
        else:
            transformed = frame
        if mirror:
            transformed = cv2.flip(transformed, 1)
        return transformed

    @staticmethod
    def _orientation_label(rotation_degrees: int, source: str) -> str:
        return f"rotate_{rotation_degrees}_{source}"

    def _orientation_score(self, detection: FaceDetectionResult) -> float:
        face = detection.primary_face
        if face is None:
            return -1000.0
        height, width = detection.frame_shape[:2]
        area = max(0, face.bbox_xywh[2]) * max(0, face.bbox_xywh[3])
        area_ratio = area / max(width * height, 1)
        dominant_bonus = 200.0 if self.dominant_face_ok(detection) else -250.0
        quality_bonus = 250.0 if detection.ok else 0.0
        pose_penalty = abs(face.roll) * 12.0 + abs(face.yaw) * 2.0 + abs(face.pitch) * 2.0
        return 1000.0 + dominant_bonus + quality_bonus + area_ratio * 500.0 - pose_penalty


def _insightface_keypoints(
    landmarks: list[tuple[int, int]],
) -> tuple[tuple[float, float], ...] | None:
    """Map MediaPipe Face Mesh landmarks to ArcFace's five alignment points."""
    required = (1, 33, 61, 133, 263, 291, 362)
    if not landmarks or max(required) >= len(landmarks):
        return None

    def midpoint(first: int, second: int) -> tuple[float, float]:
        return (
            (landmarks[first][0] + landmarks[second][0]) / 2.0,
            (landmarks[first][1] + landmarks[second][1]) / 2.0,
        )

    eyes = sorted((midpoint(33, 133), midpoint(362, 263)), key=lambda point: point[0])
    mouth = sorted(
        (
            (float(landmarks[61][0]), float(landmarks[61][1])),
            (float(landmarks[291][0]), float(landmarks[291][1])),
        ),
        key=lambda point: point[0],
    )
    nose = (float(landmarks[1][0]), float(landmarks[1][1]))
    return (eyes[0], eyes[1], nose, mouth[0], mouth[1])
