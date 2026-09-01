from __future__ import annotations

from dataclasses import dataclass, field
from math import atan2, degrees, sqrt
from pathlib import Path
from typing import Any

import cv2
import numpy as np

from .utils import clamp_bbox, get_nested, resolve_demo_path


@dataclass
class FaceCandidate:
    bbox: tuple[int, int, int, int]
    bbox_xywh: tuple[int, int, int, int]
    landmarks: list[tuple[float, float, float]]
    landmarks_px: list[tuple[int, int]]
    blendshapes: dict[str, float]
    yaw: float
    pitch: float
    roll: float
    brightness: float
    face_size_ratio: float
    center_offset_ratio: tuple[float, float]
    eye_aspect_ratio: float
    blink_score: float
    smile_score: float
    mouth_open_score: float
    checks: dict[str, bool] = field(default_factory=dict)


@dataclass
class FaceDetectionResult:
    face_count: int
    faces: list[FaceCandidate]
    primary_face: FaceCandidate | None
    frame_shape: tuple[int, int, int]
    messages: list[str]
    raw_result: Any | None = None

    @property
    def ok(self) -> bool:
        if self.primary_face is None:
            return False
        required = (
            "detected",
            "single_face",
            "face_size",
            "centered",
            "brightness",
            "pose",
        )
        return all(self.primary_face.checks.get(key, False) for key in required)


class MediaPipeFaceDetector:
    """MediaPipe Tasks wrapper for face detection, landmarks, pose and quality checks."""

    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        self.model_path = self._resolve_landmarker_model()
        try:
            import mediapipe as mp
            from mediapipe.tasks import python
            from mediapipe.tasks.python import vision
        except Exception as exc:  # pragma: no cover - depends on local env
            raise RuntimeError(
                "Thiếu thư viện mediapipe. Hãy chạy: pip install -r requirements.txt"
            ) from exc

        self.mp = mp
        base_options = python.BaseOptions(model_asset_path=str(self.model_path))
        options = vision.FaceLandmarkerOptions(
            base_options=base_options,
            running_mode=vision.RunningMode.IMAGE,
            output_face_blendshapes=True,
            output_facial_transformation_matrixes=True,
            num_faces=4,
        )
        self.landmarker = vision.FaceLandmarker.create_from_options(options)

    def _resolve_landmarker_model(self) -> Path:
        models_path = resolve_demo_path(self.config, "models_path", "models")
        candidates = [models_path / "face_landmarker.task"]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        raise FileNotFoundError(
            "Thiếu MediaPipe face_landmarker.task. Hãy đặt file vào "
            f"{models_path / 'face_landmarker.task'}."
        )

    def detect(self, frame_bgr: np.ndarray) -> FaceDetectionResult:
        height, width = frame_bgr.shape[:2]
        rgb_image = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        mp_image = self.mp.Image(image_format=self.mp.ImageFormat.SRGB, data=rgb_image)
        raw = self.landmarker.detect(mp_image)

        face_landmarks = raw.face_landmarks or []
        face_count = len(face_landmarks)
        faces: list[FaceCandidate] = []
        blendshape_sets = raw.face_blendshapes or []
        matrices = getattr(raw, "facial_transformation_matrixes", None)
        if matrices is None:
            matrices = []

        for index, landmark_list in enumerate(face_landmarks):
            landmarks = [(float(lm.x), float(lm.y), float(lm.z)) for lm in landmark_list]
            landmarks_px = [
                (int(np.clip(lm.x * width, 0, width - 1)), int(np.clip(lm.y * height, 0, height - 1)))
                for lm in landmark_list
            ]
            bbox = self._landmarks_to_bbox(landmarks_px, width, height)
            bbox_xywh = (bbox[0], bbox[1], max(1, bbox[2] - bbox[0]), max(1, bbox[3] - bbox[1]))
            blendshapes = self._blendshapes_to_dict(blendshape_sets[index] if index < len(blendshape_sets) else [])
            matrix = matrices[index] if index < len(matrices) else None
            yaw, pitch, roll = self._estimate_pose(landmarks, matrix)
            metrics = self._landmark_metrics(landmarks, blendshapes)
            brightness = self._brightness(frame_bgr, bbox)
            face_size_ratio = max(bbox_xywh[2] / width, bbox_xywh[3] / height)
            center_offset_ratio = self._center_offset_ratio(bbox, width, height)
            checks = self._quality_checks(
                face_count=face_count,
                bbox=bbox,
                frame_width=width,
                frame_height=height,
                brightness=brightness,
                face_size_ratio=face_size_ratio,
                yaw=yaw,
                pitch=pitch,
                roll=roll,
                center_offset_ratio=center_offset_ratio,
            )
            faces.append(
                FaceCandidate(
                    bbox=bbox,
                    bbox_xywh=bbox_xywh,
                    landmarks=landmarks,
                    landmarks_px=landmarks_px,
                    blendshapes=blendshapes,
                    yaw=yaw,
                    pitch=pitch,
                    roll=roll,
                    brightness=brightness,
                    face_size_ratio=face_size_ratio,
                    center_offset_ratio=center_offset_ratio,
                    eye_aspect_ratio=metrics["eye_aspect_ratio"],
                    blink_score=metrics["blink_score"],
                    smile_score=metrics["smile_score"],
                    mouth_open_score=metrics["mouth_open_score"],
                    checks=checks,
                )
            )

        primary_face = max(faces, key=lambda item: item.bbox_xywh[2] * item.bbox_xywh[3]) if faces else None
        messages = self._messages(face_count, primary_face)
        return FaceDetectionResult(
            face_count=face_count,
            faces=faces,
            primary_face=primary_face,
            frame_shape=frame_bgr.shape,
            messages=messages,
            raw_result=raw,
        )

    def detection_metrics(self, result: FaceDetectionResult) -> dict[str, Any]:
        face = result.primary_face
        if face is None:
            return {
                "face_count": result.face_count,
                "yaw": 0.0,
                "pitch": 0.0,
                "roll": 0.0,
                "brightness": 0.0,
                "eye_aspect_ratio": 0.0,
                "blink_score": 0.0,
                "smile_score": 0.0,
                "mouth_open_score": 0.0,
                "checks": {},
            }
        return {
            "face_count": result.face_count,
            "bbox": face.bbox,
            "bbox_xywh": face.bbox_xywh,
            "yaw": face.yaw,
            "pitch": face.pitch,
            "roll": face.roll,
            "brightness": face.brightness,
            "face_size_ratio": face.face_size_ratio,
            "center_offset_ratio": face.center_offset_ratio,
            "eye_aspect_ratio": face.eye_aspect_ratio,
            "blink_score": face.blink_score,
            "smile_score": face.smile_score,
            "mouth_open_score": face.mouth_open_score,
            "blendshapes": face.blendshapes,
            "checks": face.checks,
        }

    def _messages(self, face_count: int, face: FaceCandidate | None) -> list[str]:
        if face_count == 0:
            return ["Không phát hiện khuôn mặt"]
        if face_count > 1:
            return ["Chỉ cho phép 1 khuôn mặt trong khung hình"]
        if face is None:
            return ["Không phát hiện khuôn mặt"]

        messages = []
        if not face.checks.get("face_size", False):
            messages.append("Khuôn mặt chưa đủ lớn")
        if not face.checks.get("centered", False):
            messages.append("Hãy đưa khuôn mặt vào giữa khung hình")
        if not face.checks.get("brightness", False):
            messages.append("Ánh sáng chưa đạt yêu cầu")
        if not face.checks.get("pose", False):
            messages.append("Góc mặt quá lệch cho bước kiểm tra ban đầu")
        return messages or ["MediaPipe PASS"]

    def _quality_checks(
        self,
        face_count: int,
        bbox: tuple[int, int, int, int],
        frame_width: int,
        frame_height: int,
        brightness: float,
        face_size_ratio: float,
        yaw: float,
        pitch: float,
        roll: float,
        center_offset_ratio: tuple[float, float],
    ) -> dict[str, bool]:
        min_face_size_ratio = float(get_nested(self.config, "thresholds.min_face_size_ratio", 0.20))
        brightness_threshold = float(get_nested(self.config, "thresholds.brightness_threshold", 50))
        center_x_limit = float(get_nested(self.config, "thresholds.center_x_limit", 0.22))
        center_y_limit = float(get_nested(self.config, "thresholds.center_y_limit", 0.25))
        pose_yaw_limit = float(get_nested(self.config, "thresholds.pose_yaw_limit", 35))
        pose_pitch_limit = float(get_nested(self.config, "thresholds.pose_pitch_limit", 30))
        pose_roll_limit = float(get_nested(self.config, "thresholds.pose_roll_limit", 28))
        x1, y1, x2, y2 = bbox
        valid_bbox = x2 > x1 and y2 > y1 and x1 < frame_width and y1 < frame_height
        return {
            "detected": valid_bbox,
            "single_face": face_count == 1,
            "face_size": face_size_ratio >= min_face_size_ratio,
            "centered": abs(center_offset_ratio[0]) <= center_x_limit and abs(center_offset_ratio[1]) <= center_y_limit,
            "brightness": brightness >= brightness_threshold,
            "pose": abs(yaw) <= pose_yaw_limit and abs(pitch) <= pose_pitch_limit and abs(roll) <= pose_roll_limit,
        }

    @staticmethod
    def _landmarks_to_bbox(
        landmarks_px: list[tuple[int, int]],
        width: int,
        height: int,
    ) -> tuple[int, int, int, int]:
        xs = [point[0] for point in landmarks_px]
        ys = [point[1] for point in landmarks_px]
        pad_x = int((max(xs) - min(xs)) * 0.08)
        pad_y = int((max(ys) - min(ys)) * 0.10)
        return clamp_bbox((min(xs) - pad_x, min(ys) - pad_y, max(xs) + pad_x, max(ys) + pad_y), width, height)

    @staticmethod
    def _blendshapes_to_dict(blendshapes: Any) -> dict[str, float]:
        values: dict[str, float] = {}
        for item in blendshapes:
            name = getattr(item, "category_name", "")
            if name:
                values[name] = float(getattr(item, "score", 0.0))
        return values

    @staticmethod
    def _brightness(frame_bgr: np.ndarray, bbox: tuple[int, int, int, int]) -> float:
        height, width = frame_bgr.shape[:2]
        x1, y1, x2, y2 = clamp_bbox(bbox, width, height)
        roi = frame_bgr[y1:y2, x1:x2]
        if roi.size == 0:
            roi = frame_bgr
        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        return float(np.mean(gray))

    @staticmethod
    def _center_offset_ratio(
        bbox: tuple[int, int, int, int],
        width: int,
        height: int,
    ) -> tuple[float, float]:
        x1, y1, x2, y2 = bbox
        face_cx = (x1 + x2) / 2
        face_cy = (y1 + y2) / 2
        return ((face_cx - width / 2) / width, (face_cy - height / 2) / height)

    def _estimate_pose(
        self,
        landmarks: list[tuple[float, float, float]],
        matrix: Any | None,
    ) -> tuple[float, float, float]:
        matrix_pose = self._pose_from_matrix(matrix)
        geometric_pose = self._pose_from_landmarks(landmarks)
        if matrix_pose is None:
            return geometric_pose

        yaw, pitch, roll = matrix_pose
        geo_yaw, geo_pitch, geo_roll = geometric_pose
        if abs(yaw) < 2 and abs(geo_yaw) > 8:
            yaw = geo_yaw
        if abs(pitch) < 2 and abs(geo_pitch) > 8:
            pitch = geo_pitch
        if abs(roll) < 2 and abs(geo_roll) > 8:
            roll = geo_roll
        return float(yaw), float(pitch), float(roll)

    @staticmethod
    def _pose_from_matrix(matrix: Any | None) -> tuple[float, float, float] | None:
        if matrix is None:
            return None
        try:
            rotation = np.asarray(matrix, dtype=np.float64)[:3, :3]
            sy = sqrt(rotation[0, 0] * rotation[0, 0] + rotation[1, 0] * rotation[1, 0])
            singular = sy < 1e-6
            if not singular:
                pitch = atan2(rotation[2, 1], rotation[2, 2])
                yaw = atan2(-rotation[2, 0], sy)
                roll = atan2(rotation[1, 0], rotation[0, 0])
            else:
                pitch = atan2(-rotation[1, 2], rotation[1, 1])
                yaw = atan2(-rotation[2, 0], sy)
                roll = 0
            return degrees(yaw), degrees(pitch), degrees(roll)
        except Exception:
            return None

    @staticmethod
    def _pose_from_landmarks(landmarks: list[tuple[float, float, float]]) -> tuple[float, float, float]:
        def point(index: int) -> np.ndarray:
            return np.asarray(landmarks[index][:2], dtype=np.float64)

        try:
            nose = point(1)
            left_eye = point(33)
            right_eye = point(263)
            chin = point(152)
            forehead = point(10)
            mouth_center = (point(13) + point(14)) / 2

            dist_left = np.linalg.norm(nose - left_eye)
            dist_right = np.linalg.norm(nose - right_eye)
            yaw = ((dist_left - dist_right) / max(dist_left + dist_right, 1e-6)) * 70.0

            eye_center = (left_eye + right_eye) / 2
            face_height = max(np.linalg.norm(chin - forehead), 1e-6)
            nose_vertical = (nose[1] - eye_center[1]) / face_height
            mouth_vertical = (mouth_center[1] - nose[1]) / face_height
            pitch = (nose_vertical - mouth_vertical * 0.62) * 85.0

            roll = degrees(atan2(right_eye[1] - left_eye[1], right_eye[0] - left_eye[0]))
            return float(yaw), float(pitch), float(roll)
        except Exception:
            return 0.0, 0.0, 0.0

    @staticmethod
    def _landmark_metrics(
        landmarks: list[tuple[float, float, float]],
        blendshapes: dict[str, float],
    ) -> dict[str, float]:
        def p(index: int) -> np.ndarray:
            return np.asarray(landmarks[index][:2], dtype=np.float64)

        def dist(a: int, b: int) -> float:
            return float(np.linalg.norm(p(a) - p(b)))

        def ear(points: tuple[int, int, int, int, int, int]) -> float:
            p1, p2, p3, p4, p5, p6 = points
            return (dist(p2, p6) + dist(p3, p5)) / max(2.0 * dist(p1, p4), 1e-6)

        try:
            left_ear = ear((33, 160, 158, 133, 153, 144))
            right_ear = ear((362, 385, 387, 263, 373, 380))
            eye_aspect_ratio = float((left_ear + right_ear) / 2.0)
        except Exception:
            eye_aspect_ratio = 0.0

        blink_score = float(
            (
                blendshapes.get("eyeBlinkLeft", 0.0)
                + blendshapes.get("eyeBlinkRight", 0.0)
            )
            / 2.0
        )
        raw_smile = float(
            (
                blendshapes.get("mouthSmileLeft", 0.0)
                + blendshapes.get("mouthSmileRight", 0.0)
            )
            / 2.0
        )
        smile_score = 1.0 + raw_smile * 1.2
        mouth_open_score = float(blendshapes.get("jawOpen", 0.0))
        return {
            "eye_aspect_ratio": eye_aspect_ratio,
            "blink_score": blink_score,
            "smile_score": smile_score,
            "mouth_open_score": mouth_open_score,
        }
