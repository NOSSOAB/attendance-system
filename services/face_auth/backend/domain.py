from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from threading import Lock
import time
from typing import Any

import numpy as np

from modules.face_detector import FaceDetectionResult
from modules.face_recognizer import RecognitionResult
from modules.liveness_challenge import LivenessChallengeEngine


class SessionStage(str, Enum):
    LIVENESS = "LIVENESS"
    VERIFYING = "VERIFYING"
    SUCCESS = "SUCCESS"
    FAILED = "FAILED"


@dataclass
class VerificationFrameSample:
    """Compressed, bounded sample retained for server-side multi-frame verification."""

    jpeg_bytes: bytes
    bbox: tuple[int, int, int, int]
    quality: float
    captured_at: float
    challenge_index: int
    recognition_keypoints: tuple[tuple[float, float], ...] | None = None


@dataclass
class AuthSession:
    session_id: str
    target_name: str
    engine: LivenessChallengeEngine
    session_token_digest: str = ""
    skip_liveness: bool = False
    created_at: float = field(default_factory=time.monotonic)
    updated_at: float = field(default_factory=time.monotonic)
    lock: Lock = field(default_factory=Lock)
    stage: SessionStage = SessionStage.LIVENESS
    final_message: str = ""
    frame_count: int = 0
    generation: int = 0
    rotation_degrees: int | None = None
    last_orientation: str = "uncalibrated"
    best_frame: np.ndarray | None = None
    best_bbox: tuple[int, int, int, int] | None = None
    best_frame_quality: float = -1.0
    verification_samples: list[VerificationFrameSample] = field(default_factory=list)
    last_sample_at: float | None = None
    latest_detection: FaceDetectionResult | None = None
    recognition_result: RecognitionResult | None = None
    last_processing_ms: float = 0.0
    verification_ms: float = 0.0
    verification_started_at: float | None = None
    identity_precheck_started: bool = False
    identity_precheck_outcome: Any | None = None
    identity_retry_started: bool = False
    result_code: str = "IN_PROGRESS"
    recent_frame_digests: list[str] = field(default_factory=list)
    duplicate_frames_rejected: int = 0
    metadata: dict[str, Any] = field(default_factory=dict)

    def touch(self) -> None:
        self.updated_at = time.monotonic()

    @property
    def terminal(self) -> bool:
        return self.stage in {SessionStage.SUCCESS, SessionStage.FAILED}


class SessionNotFoundError(KeyError):
    pass


class SessionCapacityError(RuntimeError):
    pass


class SessionBusyError(RuntimeError):
    pass


class SessionAuthError(PermissionError):
    pass
