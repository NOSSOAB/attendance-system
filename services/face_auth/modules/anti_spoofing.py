"""Legacy desktop-only PAD adapter; the FastAPI backend intentionally does not import it."""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
from pathlib import Path
import time
from typing import Any

import cv2
import numpy as np

from .utils import get_nested


class AntiSpoofingModelError(RuntimeError):
    pass


@dataclass
class AntiSpoofingResult:
    real_score: float
    printed_photo_score: float
    screen_replay_score: float
    unknown_spoof_score: float
    is_real: bool
    threshold: float
    label: str
    model_count: int
    inference_time_ms: float
    error: str = ""
    engine: str = "mobilenetv3_onnx"
    sample_count: int = 1
    passed_count: int = 0
    median_score: float = 0.0
    min_score: float = 0.0
    diagnostics: dict[str, float] = field(default_factory=dict)


class LightweightOnnxAntiSpoofing:
    """MobileNetV3 face PAD adapter using the small Open Model Zoo ONNX model."""

    INPUT_SIZE = (128, 128)
    RGB_MEAN = np.asarray([151.2405, 119.5950, 107.8395], dtype=np.float32)
    RGB_SCALE = np.asarray([63.0105, 56.4570, 55.0035], dtype=np.float32)

    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        self.threshold = float(get_nested(config, "thresholds.real_face_threshold", 0.80))
        model_value = str(get_nested(config, "anti_spoofing.model_path", "models/anti-spoof-mn3.onnx"))
        model_path = Path(model_value)
        if not model_path.is_absolute():
            model_path = Path(__file__).resolve().parents[1] / model_path
        self.model_path = model_path
        self.expected_sha384 = str(get_nested(config, "anti_spoofing.model_sha384", "")).lower()
        self.crop_scale = max(1.0, float(get_nested(config, "anti_spoofing.crop_scale", 1.35)))
        self.diagnostics_enabled = bool(get_nested(config, "anti_spoofing.diagnostics", False))
        self.intra_op_threads = max(1, int(get_nested(config, "anti_spoofing.intra_op_threads", 1)))
        self._session = None
        self._input_name = ""
        self._validated = False

    def validate_files(self) -> None:
        if not self.model_path.is_file():
            raise AntiSpoofingModelError(
                f"Không tìm thấy model PAD ONNX: {self.model_path}. "
                "Hãy tải anti-spoof-mn3.onnx theo hướng dẫn trong models/README.md."
            )
        if self.expected_sha384:
            actual = _sha384(self.model_path)
            if actual != self.expected_sha384:
                raise AntiSpoofingModelError(
                    "Checksum model PAD không khớp. "
                    f"expected={self.expected_sha384} actual={actual}"
                )
        self._validated = True

    def predict(
        self,
        frame_bgr: np.ndarray,
        face_bbox: tuple[int, int, int, int] | None = None,
    ) -> AntiSpoofingResult:
        started_at = time.perf_counter()
        try:
            self._ensure_loaded()
            if face_bbox is None:
                raise AntiSpoofingModelError("PAD ONNX requires a detected face bounding box")
            assert self._session is not None

            real_score = self._infer_real_score(
                frame_bgr,
                face_bbox,
                scale=self.crop_scale,
                rgb_input=True,
            )
            spoof_score = 1.0 - real_score
            diagnostics: dict[str, float] = {}
            if self.diagnostics_enabled:
                for scale in (1.0, 1.2, 1.35, 1.6):
                    key = f"crop_{scale:.2f}_rgb".replace(".", "_")
                    diagnostics[key] = (
                        real_score
                        if abs(scale - self.crop_scale) < 1e-6
                        else self._infer_real_score(
                            frame_bgr,
                            face_bbox,
                            scale=scale,
                            rgb_input=True,
                        )
                    )
                diagnostics["crop_1_20_bgr"] = self._infer_real_score(
                    frame_bgr,
                    face_bbox,
                    scale=1.2,
                    rgb_input=False,
                )
                diagnostics.update(_bbox_diagnostics(frame_bgr, face_bbox))
            is_real = real_score >= self.threshold
            elapsed_ms = (time.perf_counter() - started_at) * 1000
            return AntiSpoofingResult(
                real_score=real_score,
                printed_photo_score=0.0,
                screen_replay_score=0.0,
                unknown_spoof_score=spoof_score,
                is_real=is_real,
                threshold=self.threshold,
                label="REAL" if is_real else "SPOOF",
                model_count=1,
                inference_time_ms=elapsed_ms,
                engine="mobilenetv3_onnx",
                sample_count=1,
                passed_count=1 if is_real else 0,
                median_score=real_score,
                min_score=real_score,
                diagnostics=diagnostics,
            )
        except Exception as exc:
            elapsed_ms = (time.perf_counter() - started_at) * 1000
            return AntiSpoofingResult(
                real_score=0.0,
                printed_photo_score=0.0,
                screen_replay_score=0.0,
                unknown_spoof_score=1.0,
                is_real=False,
                threshold=self.threshold,
                label="ERROR",
                model_count=0,
                inference_time_ms=elapsed_ms,
                error=str(exc),
                engine="mobilenetv3_onnx",
                sample_count=0,
                passed_count=0,
            )

    def _infer_real_score(
        self,
        frame_bgr: np.ndarray,
        face_bbox: tuple[int, int, int, int],
        *,
        scale: float,
        rgb_input: bool,
    ) -> float:
        assert self._session is not None
        crop = _expanded_square_crop(frame_bgr, face_bbox, scale)
        resized = cv2.resize(crop, self.INPUT_SIZE, interpolation=cv2.INTER_AREA)
        pixels = (
            cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
            if rgb_input
            else resized
        ).astype(np.float32)
        normalized = (pixels - self.RGB_MEAN) / self.RGB_SCALE
        tensor = np.transpose(normalized, (2, 0, 1))[None, ...].astype(np.float32)
        output = np.asarray(
            self._session.run(None, {self._input_name: tensor})[0],
            dtype=np.float32,
        ).reshape(-1)
        probabilities = _as_probabilities(output)
        if probabilities.size < 2:
            raise AntiSpoofingModelError(f"Unexpected PAD output shape: {output.shape}")
        # Original ONNX contract: RGB input; class 0 = real, class 1 = spoof.
        return float(probabilities[0])

    def _ensure_loaded(self) -> None:
        if self._session is not None:
            return
        if not self._validated:
            self.validate_files()
        try:
            import onnxruntime as ort
        except Exception as exc:  # pragma: no cover - environment dependency
            raise AntiSpoofingModelError(
                "Không import được onnxruntime cho model PAD MobileNetV3"
            ) from exc

        options = ort.SessionOptions()
        options.intra_op_num_threads = self.intra_op_threads
        options.inter_op_num_threads = 1
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        self._session = ort.InferenceSession(
            str(self.model_path),
            sess_options=options,
            providers=["CPUExecutionProvider"],
        )
        inputs = self._session.get_inputs()
        if len(inputs) != 1:
            raise AntiSpoofingModelError(f"PAD model must have one input, found {len(inputs)}")
        self._input_name = inputs[0].name


def _sha384(path: Path) -> str:
    digest = hashlib.sha384()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _expanded_square_crop(
    frame: np.ndarray,
    bbox: tuple[int, int, int, int],
    scale: float,
) -> np.ndarray:
    if frame.ndim != 3 or frame.shape[0] < 2 or frame.shape[1] < 2:
        raise AntiSpoofingModelError("Invalid frame for PAD")
    x1, y1, x2, y2 = (int(value) for value in bbox)
    width = max(1, x2 - x1)
    height = max(1, y2 - y1)
    side = max(2, int(round(max(width, height) * scale)))
    center_x = (x1 + x2) / 2.0
    center_y = (y1 + y2) / 2.0
    left = int(round(center_x - side / 2.0))
    top = int(round(center_y - side / 2.0))
    right = left + side
    bottom = top + side

    frame_height, frame_width = frame.shape[:2]
    pad_left = max(0, -left)
    pad_top = max(0, -top)
    pad_right = max(0, right - frame_width)
    pad_bottom = max(0, bottom - frame_height)
    if pad_left or pad_top or pad_right or pad_bottom:
        frame = cv2.copyMakeBorder(
            frame,
            pad_top,
            pad_bottom,
            pad_left,
            pad_right,
            cv2.BORDER_REPLICATE,
        )
        left += pad_left
        right += pad_left
        top += pad_top
        bottom += pad_top
    crop = frame[top:bottom, left:right]
    if crop.size == 0:
        raise AntiSpoofingModelError("Face crop is empty")
    return crop


def _bbox_diagnostics(
    frame: np.ndarray,
    bbox: tuple[int, int, int, int],
) -> dict[str, float]:
    frame_height, frame_width = frame.shape[:2]
    x1, y1, x2, y2 = (int(value) for value in bbox)
    return {
        "bbox_width_ratio": max(0.0, (x2 - x1) / max(frame_width, 1)),
        "bbox_height_ratio": max(0.0, (y2 - y1) / max(frame_height, 1)),
        "bbox_center_x_ratio": ((x1 + x2) / 2.0) / max(frame_width, 1),
        "bbox_center_y_ratio": ((y1 + y2) / 2.0) / max(frame_height, 1),
    }


def _as_probabilities(values: np.ndarray) -> np.ndarray:
    values = np.asarray(values, dtype=np.float64).reshape(-1)
    if np.all(values >= 0.0) and np.all(values <= 1.0) and abs(float(values.sum()) - 1.0) < 0.05:
        return values
    shifted = values - np.max(values)
    exponent = np.exp(shifted)
    return exponent / max(float(exponent.sum()), 1e-12)
