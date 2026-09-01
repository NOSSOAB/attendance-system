from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
from typing import Any

from modules.utils import get_nested, resolve_demo_path


@dataclass(frozen=True)
class BackendSettings:
    """Typed server settings derived from the existing YAML configuration."""

    config: dict[str, Any]
    session_ttl_seconds: float
    max_sessions: int
    max_upload_bytes: int
    max_frame_dimension: int
    max_inflight_frames: int
    detector_workers: int
    queue_timeout_seconds: float
    verification_workers: int
    verification_queue_capacity: int
    auto_orient: bool
    dominant_face_ratio: float
    final_pose_limit: float
    debug_save_frames: bool
    debug_frame_interval: int
    allow_skip_liveness: bool
    require_client_api_key: bool
    client_api_key: str
    admin_api_key: str
    production: bool
    expose_health_details: bool
    cors_origins: tuple[str, ...]
    build_version: str
    session_start_rate_per_minute: float
    session_start_burst: int
    frame_rate_per_second: float
    frame_rate_burst: int
    api_real_face_threshold: float
    min_verification_samples: int
    max_verification_samples: int
    samples_per_challenge: int
    sample_interval_seconds: float
    sample_jpeg_quality: int
    recognition_sample_count: int
    min_recognition_pass_ratio: float
    output_path: Path

    @classmethod
    def from_config(cls, config: dict[str, Any]) -> "BackendSettings":
        return cls(
            config=config,
            session_ttl_seconds=max(30.0, float(get_nested(config, "backend.session_ttl_seconds", 300))),
            max_sessions=max(1, int(get_nested(config, "backend.max_sessions", 32))),
            max_upload_bytes=max(100_000, int(get_nested(config, "backend.max_upload_bytes", 2_500_000))),
            max_frame_dimension=max(320, int(get_nested(config, "backend.max_frame_dimension", 960))),
            max_inflight_frames=max(1, int(get_nested(config, "backend.max_inflight_frames", 2))),
            detector_workers=max(1, int(get_nested(config, "backend.detector_workers", 1))),
            queue_timeout_seconds=max(0.01, float(get_nested(config, "backend.queue_timeout_seconds", 0.25))),
            verification_workers=max(1, int(get_nested(config, "backend.verification_workers", 1))),
            verification_queue_capacity=max(
                0, int(get_nested(config, "backend.verification_queue_capacity", 16))
            ),
            auto_orient=bool(get_nested(config, "backend.auto_orient", True)),
            dominant_face_ratio=max(1.0, float(get_nested(config, "backend.dominant_face_ratio", 1.60))),
            final_pose_limit=max(5.0, float(get_nested(config, "backend.final_pose_limit", 20.0))),
            debug_save_frames=bool(get_nested(config, "backend.debug_save_frames", False)),
            debug_frame_interval=max(1, int(get_nested(config, "backend.debug_frame_interval", 20))),
            allow_skip_liveness=bool(get_nested(config, "backend.allow_skip_liveness", False)),
            require_client_api_key=bool(
                get_nested(config, "security.require_client_api_key", False)
            ),
            client_api_key=os.environ.get("FACE_CLIENT_API_KEY", "").strip(),
            admin_api_key=os.environ.get("FACE_ADMIN_API_KEY", "").strip(),
            production=_env_bool("FACE_PRODUCTION", False),
            expose_health_details=_env_bool("FACE_EXPOSE_HEALTH_DETAILS", False),
            cors_origins=_cors_origins(),
            build_version=os.environ.get("FACE_BUILD_VERSION", "dev").strip() or "dev",
            session_start_rate_per_minute=max(
                1.0,
                float(get_nested(config, "security.session_start_rate_per_minute", 12.0)),
            ),
            session_start_burst=max(
                1, int(get_nested(config, "security.session_start_burst", 5))
            ),
            frame_rate_per_second=max(
                1.0, float(get_nested(config, "security.frame_rate_per_second", 20.0))
            ),
            frame_rate_burst=max(
                1, int(get_nested(config, "security.frame_rate_burst", 30))
            ),
            api_real_face_threshold=float(
                get_nested(
                    config,
                    "thresholds.mobile_real_face_threshold",
                    get_nested(config, "thresholds.real_face_threshold", 0.80),
                )
            ),
            min_verification_samples=max(1, int(get_nested(config, "multi_frame.min_samples", 6))),
            max_verification_samples=max(1, int(get_nested(config, "multi_frame.max_samples", 12))),
            samples_per_challenge=max(1, int(get_nested(config, "multi_frame.samples_per_challenge", 4))),
            sample_interval_seconds=max(
                0.0, float(get_nested(config, "multi_frame.sample_interval_seconds", 0.20))
            ),
            sample_jpeg_quality=min(
                95, max(50, int(get_nested(config, "multi_frame.jpeg_quality", 82)))
            ),
            recognition_sample_count=max(
                1, int(get_nested(config, "multi_frame.recognition_sample_count", 3))
            ),
            min_recognition_pass_ratio=min(
                1.0,
                max(0.0, float(get_nested(config, "multi_frame.min_recognition_pass_ratio", 0.67))),
            ),
            output_path=resolve_demo_path(config, "output_path", "outputs"),
        )


def env_bool(name: str, default: bool = False) -> bool:
    """Read a strict boolean environment flag without treating arbitrary text as true."""
    raw = os.environ.get(name)
    if raw is None:
        return default
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"{name} must be one of: true, false, 1, 0, yes, no, on, off")


def _env_bool(name: str, default: bool = False) -> bool:
    return env_bool(name, default)


def _cors_origins() -> tuple[str, ...]:
    raw = os.environ.get("FACE_CORS_ORIGINS")
    if raw is None:
        return () if _env_bool("FACE_PRODUCTION", False) else ("*",)
    return tuple(item.strip() for item in raw.split(",") if item.strip())
