from __future__ import annotations

from dataclasses import asdict
from typing import Any, Callable

from modules.face_detector import FaceDetectionResult
from modules.liveness_challenge import LivenessSnapshot

from .domain import AuthSession, SessionStage


def build_response(
    session: AuthSession,
    detection: FaceDetectionResult | None,
    liveness: LivenessSnapshot,
    dominant_face_ok: Callable[[FaceDetectionResult], bool],
) -> dict[str, Any]:
    return {
        "api_version": "v1",
        "session_id": session.session_id,
        "target_name": session.target_name,
        "stage": session.stage.value,
        "frame_count": session.frame_count,
        "frame_orientation": session.last_orientation,
        "processing_time_ms": round(session.last_processing_ms, 1),
        "performance": {
            "frame_processing_ms": round(session.last_processing_ms, 1),
            "verification_ms": round(session.verification_ms, 1),
            "best_frame_quality": round(max(0.0, session.best_frame_quality), 3),
            "collected_samples": len(session.verification_samples),
            "duplicate_frames_rejected": session.duplicate_frames_rejected,
            "identity_precheck_status": (
                "retrying"
                if session.identity_retry_started and session.stage == SessionStage.VERIFYING
                else
                "ready"
                if session.identity_precheck_outcome is not None
                else "running"
                if session.identity_precheck_started
                else "waiting"
            ),
        },
        "detection": _serialize_detection(detection, dominant_face_ok),
        "liveness": _serialize_liveness(liveness),
        "recognition": _serialize_recognition(session.recognition_result),
        "final": {
            "status": session.stage.value,
            "code": session.result_code,
            "ok": session.stage == SessionStage.SUCCESS,
            "message": session.final_message,
        },
    }


def _serialize_recognition(recognition: Any | None) -> dict[str, Any] | None:
    if recognition is None:
        return None
    payload = asdict(recognition)
    # Source enrollment paths and native exception text are server-side details.
    payload.pop("candidate_image", None)
    payload.pop("error", None)
    return payload


def _serialize_detection(
    detection: FaceDetectionResult | None,
    dominant_face_ok: Callable[[FaceDetectionResult], bool],
) -> dict[str, Any] | None:
    if detection is None:
        return None
    face = detection.primary_face
    return {
        "face_count": detection.face_count,
        "ok": detection.ok,
        "dominant_face_ok": dominant_face_ok(detection),
        "messages": detection.messages,
        "face": None
        if face is None
        else {
            "bbox": list(face.bbox),
            "yaw": face.yaw,
            "pitch": face.pitch,
            "roll": face.roll,
            "brightness": face.brightness,
            "face_size_ratio": face.face_size_ratio,
            "eye_aspect_ratio": face.eye_aspect_ratio,
            "blink_score": face.blink_score,
            "smile_score": face.smile_score,
            "mouth_open_score": face.mouth_open_score,
            "checks": face.checks,
        },
    }


def _serialize_liveness(snapshot: LivenessSnapshot) -> dict[str, Any]:
    return {
        "challenges": snapshot.challenges,
        "current_index": snapshot.current_index,
        "current_instruction": snapshot.current_instruction,
        "passed": snapshot.passed,
        "failed": snapshot.failed,
        "time_left_seconds": snapshot.time_left_seconds,
        "retries_left": snapshot.retries_left,
        "metrics": snapshot.metrics,
        "message": snapshot.message,
    }
