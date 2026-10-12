from __future__ import annotations

import contextlib
from dataclasses import asdict, is_dataclass
from datetime import datetime
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
import time
from typing import Any, Iterator

import cv2
import numpy as np
import yaml


DEMO_ROOT = Path(__file__).resolve().parents[1]
PROJECTS_ROOT = DEMO_ROOT.parent


def load_config(config_path: str | Path | None = None) -> dict[str, Any]:
    path = Path(config_path) if config_path else DEMO_ROOT / "config.yaml"
    with path.open("r", encoding="utf-8") as file:
        return yaml.safe_load(file) or {}


def get_nested(data: dict[str, Any], path: str, default: Any = None) -> Any:
    current: Any = data
    for key in path.split("."):
        if not isinstance(current, dict) or key not in current:
            return default
        current = current[key]
    return current


def resolve_demo_path(config: dict[str, Any], key: str, default: str) -> Path:
    value = get_nested(config, f"paths.{key}", default)
    path = Path(value)
    if not path.is_absolute():
        path = DEMO_ROOT / path
    return path


def ensure_runtime_dirs(config: dict[str, Any]) -> None:
    for key, default in (
        ("database_path", "database_faces"),
        ("models_path", "models"),
        ("output_path", "outputs"),
        ("log_path", "logs"),
    ):
        resolve_demo_path(config, key, default).mkdir(parents=True, exist_ok=True)


def setup_logging(config: dict[str, Any], name: str = "face_auth") -> logging.Logger:
    ensure_runtime_dirs(config)
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    if logger.handlers:
        return logger

    formatter = logging.Formatter(
        "%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    log_dir = resolve_demo_path(config, "log_path", "logs")
    # At most 20 MiB per process with defaults, including the active file.
    # Docker's stdout rotation does not cover this optional local log file.
    file_handler = RotatingFileHandler(
        log_dir / "face_auth.log", encoding="utf-8",
        maxBytes=max(1024, int(get_nested(config, "logging.max_bytes", 5 * 1024 * 1024))),
        backupCount=max(1, int(get_nested(config, "logging.backup_count", 3))),
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    return logger


@contextlib.contextmanager
def timed_step(logger: logging.Logger, label: str) -> Iterator[None]:
    started_at = time.perf_counter()
    try:
        yield
    finally:
        elapsed_ms = (time.perf_counter() - started_at) * 1000
        logger.info("%s completed in %.1f ms", label, elapsed_ms)


@contextlib.contextmanager
def pushd(path: Path) -> Iterator[None]:
    import os

    previous = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


def clamp_bbox(bbox: tuple[int, int, int, int], width: int, height: int) -> tuple[int, int, int, int]:
    x1, y1, x2, y2 = bbox
    return (
        max(0, min(width - 1, x1)),
        max(0, min(height - 1, y1)),
        max(0, min(width - 1, x2)),
        max(0, min(height - 1, y2)),
    )


def xyxy_to_xywh(bbox: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    x1, y1, x2, y2 = bbox
    return x1, y1, max(1, x2 - x1), max(1, y2 - y1)


def crop_face(frame_bgr: np.ndarray, bbox: tuple[int, int, int, int], margin: float = 0.18) -> np.ndarray:
    height, width = frame_bgr.shape[:2]
    x1, y1, x2, y2 = clamp_bbox(bbox, width, height)
    box_w = x2 - x1
    box_h = y2 - y1
    pad_x = int(box_w * margin)
    pad_y = int(box_h * margin)
    x1, y1, x2, y2 = clamp_bbox((x1 - pad_x, y1 - pad_y, x2 + pad_x, y2 + pad_y), width, height)
    return frame_bgr[y1:y2, x1:x2].copy()


def bgr_to_rgb(frame_bgr: np.ndarray) -> np.ndarray:
    return cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)


def save_frame(frame_bgr: np.ndarray, output_dir: Path, prefix: str = "capture") -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    path = output_dir / f"{prefix}_{timestamp}.jpg"
    cv2.imwrite(str(path), frame_bgr)
    return path


def to_plain_dict(value: Any) -> Any:
    if is_dataclass(value):
        return asdict(value)
    if isinstance(value, dict):
        return {key: to_plain_dict(item) for key, item in value.items()}
    if isinstance(value, list):
        return [to_plain_dict(item) for item in value]
    if isinstance(value, tuple):
        return tuple(to_plain_dict(item) for item in value)
    if isinstance(value, np.ndarray):
        return value.tolist()
    return value


def draw_detection_overlay(
    frame_bgr: np.ndarray,
    face: Any | None,
    show_box: bool = True,
    show_landmarks: bool = True,
    message: str | None = None,
) -> np.ndarray:
    annotated = frame_bgr.copy()
    if face is not None:
        if show_box and getattr(face, "bbox", None):
            x1, y1, x2, y2 = face.bbox
            cv2.rectangle(annotated, (x1, y1), (x2, y2), (20, 180, 60), 2)
        if show_landmarks:
            for x, y in getattr(face, "landmarks_px", [])[::2]:
                cv2.circle(annotated, (int(x), int(y)), 1, (30, 30, 230), -1)

    if message:
        cv2.rectangle(annotated, (18, 18), (min(annotated.shape[1] - 18, 760), 68), (0, 0, 0), -1)
        cv2.putText(
            annotated,
            message,
            (30, 52),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.72,
            (255, 255, 255),
            2,
            cv2.LINE_AA,
        )
    return annotated
