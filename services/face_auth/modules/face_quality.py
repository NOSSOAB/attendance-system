from __future__ import annotations

from .face_detector import FaceDetectionResult


def score_recognition_frame(
    detection: FaceDetectionResult,
    pose_limit: float = 20.0,
) -> float:
    """Score a detected face for later anti-spoofing and recognition."""
    face = detection.primary_face
    if detection.face_count != 1 or face is None:
        return -1.0
    if not all(
        face.checks.get(check, False)
        for check in ("detected", "single_face", "face_size", "centered", "brightness")
    ):
        return -1.0

    safe_pose_limit = max(1.0, float(pose_limit))
    center_distance = min(1.0, abs(face.center_offset_ratio[0]) + abs(face.center_offset_ratio[1]))
    pose_distance = min(
        1.0,
        (abs(face.yaw) + abs(face.pitch) + abs(face.roll)) / (safe_pose_limit * 3.0),
    )
    brightness_score = min(1.0, max(0.0, face.brightness / 100.0))
    size_score = min(1.0, face.face_size_ratio / 0.40)
    mouth_score = max(0.0, 1.0 - face.mouth_open_score)
    return (
        (1.0 - pose_distance) * 0.40
        + (1.0 - center_distance) * 0.20
        + brightness_score * 0.15
        + size_score * 0.15
        + mouth_score * 0.10
    )
