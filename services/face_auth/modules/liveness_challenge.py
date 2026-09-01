from __future__ import annotations

from dataclasses import dataclass
import random
import time
from typing import Any

from .utils import get_nested


ACTION_CATALOG: dict[str, dict[str, str]] = {
    "turn_left": {
        "label": "Quay mặt sang trái",
        "instruction": "Vui lòng quay mặt sang trái",
    },
    "turn_right": {
        "label": "Quay mặt sang phải",
        "instruction": "Vui lòng quay mặt sang phải",
    },
    "look_up": {
        "label": "Nhìn lên",
        "instruction": "Vui lòng nhìn lên",
    },
    "look_down": {
        "label": "Nhìn xuống",
        "instruction": "Vui lòng nhìn xuống",
    },
    "blink": {
        "label": "Chớp mắt",
        "instruction": "Vui lòng chớp mắt",
    },
    "smile": {
        "label": "Cười",
        "instruction": "Vui lòng cười",
    },
    "mouth_open": {
        "label": "Há miệng",
        "instruction": "Vui lòng há miệng",
    },
    "tilt_left": {
        "label": "Nghiêng đầu sang trái",
        "instruction": "Vui lòng nghiêng đầu sang trái",
    },
    "tilt_right": {
        "label": "Nghiêng đầu sang phải",
        "instruction": "Vui lòng nghiêng đầu sang phải",
    },
}


@dataclass
class ChallengeState:
    action_id: str
    label: str
    instruction: str
    status: str = "PENDING"
    attempts_used: int = 0
    confidence: float = 0.0
    started_at: float | None = None
    completed_at: float | None = None
    message: str = ""
    baseline_seen: bool = False
    baseline_at: float | None = None
    evidence_frames: int = 0


@dataclass
class LivenessSnapshot:
    challenges: list[dict[str, Any]]
    current_index: int
    current_instruction: str
    passed: bool
    failed: bool
    time_left_seconds: float
    retries_left: int
    metrics: dict[str, float]
    message: str


def generate_random_challenges(config: dict[str, Any] | None = None) -> list[dict[str, str]]:
    config = config or {}
    configured_actions = get_nested(config, "liveness.challenge_actions", list(ACTION_CATALOG))
    if not isinstance(configured_actions, list):
        configured_actions = list(ACTION_CATALOG)
    actions = [str(item) for item in configured_actions if str(item) in ACTION_CATALOG]
    if not actions:
        actions = list(ACTION_CATALOG)
    actions = list(dict.fromkeys(actions))
    number = int(get_nested(config, "liveness.number_of_challenges", 3))
    number = max(1, min(number, len(actions)))
    selected = random.SystemRandom().sample(actions, number)
    return [
        {
            "action_id": action_id,
            "label": ACTION_CATALOG[action_id]["label"],
            "instruction": ACTION_CATALOG[action_id]["instruction"],
        }
        for action_id in selected
    ]


def detect_head_turn(metrics: dict[str, Any], direction: str, config: dict[str, Any]) -> tuple[bool, float]:
    yaw = float(metrics.get("yaw", 0.0))
    if direction == "left":
        threshold = float(get_nested(config, "liveness.yaw_left_threshold", -20))
        confidence = min(1.0, abs(min(0.0, yaw)) / max(abs(threshold), 1.0))
        return yaw <= threshold, confidence
    threshold = float(get_nested(config, "liveness.yaw_right_threshold", 20))
    confidence = min(1.0, max(0.0, yaw) / max(abs(threshold), 1.0))
    return yaw >= threshold, confidence


def detect_head_pitch(metrics: dict[str, Any], direction: str, config: dict[str, Any]) -> tuple[bool, float]:
    pitch = float(metrics.get("pitch", 0.0))
    if direction == "up":
        threshold = float(get_nested(config, "liveness.pitch_up_threshold", -15))
        confidence = min(1.0, abs(min(0.0, pitch)) / max(abs(threshold), 1.0))
        return pitch <= threshold, confidence
    threshold = float(get_nested(config, "liveness.pitch_down_threshold", 15))
    confidence = min(1.0, max(0.0, pitch) / max(abs(threshold), 1.0))
    return pitch >= threshold, confidence


def detect_head_tilt(metrics: dict[str, Any], direction: str, config: dict[str, Any]) -> tuple[bool, float]:
    roll = float(metrics.get("roll", 0.0))
    if direction == "left":
        threshold = float(get_nested(config, "liveness.roll_left_threshold", -15))
        confidence = min(1.0, abs(min(0.0, roll)) / max(abs(threshold), 1.0))
        return roll <= threshold, confidence
    threshold = float(get_nested(config, "liveness.roll_right_threshold", 15))
    confidence = min(1.0, max(0.0, roll) / max(abs(threshold), 1.0))
    return roll >= threshold, confidence


def detect_blink(metrics: dict[str, Any], config: dict[str, Any]) -> tuple[bool, float]:
    threshold = float(get_nested(config, "liveness.blink_threshold", 0.20))
    blink_score = float(metrics.get("blink_score", 0.0))
    ear = float(metrics.get("eye_aspect_ratio", 0.0))
    blendshape_confidence = blink_score / max(threshold, 1e-6)
    ear_confidence = (threshold - ear) / max(threshold, 1e-6) if ear > 0 else 0.0
    confidence = min(1.0, max(blendshape_confidence, ear_confidence))
    return blink_score >= threshold or (0 < ear <= threshold), confidence


def detect_smile(metrics: dict[str, Any], config: dict[str, Any]) -> tuple[bool, float]:
    threshold = float(get_nested(config, "liveness.smile_threshold", 1.30))
    score = float(metrics.get("smile_score", 1.0))
    confidence = min(1.0, max(0.0, (score - 1.0) / max(threshold - 1.0, 1e-6)))
    return score >= threshold, confidence


def detect_mouth_open(metrics: dict[str, Any], config: dict[str, Any]) -> tuple[bool, float]:
    threshold = float(get_nested(config, "liveness.mouth_open_threshold", 0.60))
    score = float(metrics.get("mouth_open_score", 0.0))
    confidence = min(1.0, score / max(threshold, 1e-6))
    return score >= threshold, confidence


def detect_straight_face(metrics: dict[str, Any], config: dict[str, Any]) -> tuple[bool, float]:
    yaw = abs(float(metrics.get("yaw", 0.0)))
    pitch = abs(float(metrics.get("pitch", 0.0)))
    roll = abs(float(metrics.get("roll", 0.0)))
    yaw_limit = float(get_nested(config, "liveness.straight_yaw_limit", 8))
    pitch_limit = float(get_nested(config, "liveness.straight_pitch_limit", 8))
    roll_limit = float(get_nested(config, "liveness.straight_roll_limit", 8))
    max_ratio = max(
        yaw / max(yaw_limit, 1.0),
        pitch / max(pitch_limit, 1.0),
        roll / max(roll_limit, 1.0),
    )
    confidence = min(1.0, max(0.0, 1.0 - max_ratio))
    return yaw <= yaw_limit and pitch <= pitch_limit and roll <= roll_limit, confidence


class LivenessChallengeEngine:
    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        self.enabled = bool(get_nested(config, "liveness.enabled", True))
        self.timeout_seconds = float(get_nested(config, "liveness.challenge_timeout_seconds", 8))
        self.retry_per_challenge = int(get_nested(config, "liveness.retry_per_challenge", 2))
        self.confirmation_frames = max(1, int(get_nested(config, "liveness.confirmation_frames", 2)))
        self.min_action_delay_seconds = max(
            0.0, float(get_nested(config, "liveness.min_action_delay_seconds", 0.25))
        )
        self.straight_face_seconds = float(get_nested(config, "liveness.straight_face_seconds", 2))
        self.challenges: list[ChallengeState] = []
        self.current_index = 0
        self.failed = False
        self.passed = False
        self.started_at = time.monotonic()
        self.straight_started_at: float | None = None
        self.last_metrics: dict[str, float] = {}
        self.reset()

    def reset(self) -> None:
        self.challenges = [
            ChallengeState(
                action_id=item["action_id"],
                label=item["label"],
                instruction=item["instruction"],
            )
            for item in generate_random_challenges(self.config)
        ]
        self.current_index = 0
        self.failed = False
        self.passed = not self.enabled
        self.started_at = time.monotonic()
        self.straight_started_at = None
        self.last_metrics = {}

    def current_challenge(self) -> ChallengeState | None:
        if self.current_index >= len(self.challenges):
            return None
        return self.challenges[self.current_index]

    def pause_current_challenge(self) -> None:
        challenge = self.current_challenge()
        if challenge is not None and challenge.status in {"PENDING", "RUNNING", "RETRY"}:
            challenge.started_at = None
            challenge.status = "PENDING"
            challenge.baseline_seen = False
            challenge.baseline_at = None
            challenge.evidence_frames = 0
            self.straight_started_at = None

    def update_challenge_status(
        self,
        metrics: dict[str, Any],
        has_valid_face: bool = True,
        now: float | None = None,
    ) -> LivenessSnapshot:
        now = time.monotonic() if now is None else now
        self.last_metrics = _metric_subset(metrics)
        if not self.enabled:
            self.passed = True
            return self.snapshot("Liveness challenge đã tắt trong config")
        if self.failed or self.passed:
            return self.snapshot()

        challenge = self.current_challenge()
        if challenge is None:
            self.passed = True
            return self.snapshot("Hoàn thành toàn bộ thử thách sống")

        if challenge.started_at is None:
            challenge.started_at = now
            challenge.status = "RUNNING"
            challenge.message = "Giữ mặt thẳng trước khi thực hiện hành động"

        if not has_valid_face:
            return self.snapshot("Không thấy khuôn mặt hợp lệ")

        if not challenge.baseline_seen:
            baseline_ok, confidence = self._baseline_ready(challenge, metrics)
            challenge.confidence = confidence
            if baseline_ok:
                challenge.baseline_seen = True
                challenge.baseline_at = now
                challenge.evidence_frames = 0
                challenge.message = challenge.instruction
                return self.snapshot("Đã ghi nhận trạng thái ban đầu")
        else:
            condition, confidence = self._evaluate_current(challenge, metrics, now)
            challenge.confidence = confidence
            action_delay_ok = (
                challenge.baseline_at is not None
                and now - challenge.baseline_at >= self.min_action_delay_seconds
            )
            if condition and action_delay_ok:
                challenge.evidence_frames += 1
            else:
                challenge.evidence_frames = 0
                if condition and not action_delay_ok:
                    challenge.message = "Thực hiện hành động tự nhiên sau khi nhìn thẳng"
            required_frames = 1 if challenge.action_id == "blink" else self.confirmation_frames
            if challenge.evidence_frames >= required_frames:
                return self._complete_current(challenge, now)

        elapsed = now - challenge.started_at
        if elapsed >= self.timeout_seconds:
            return self._handle_timeout(challenge, now)
        return self.snapshot(challenge.message or challenge.instruction)

    def is_liveness_passed(self) -> bool:
        return self.passed

    def snapshot(self, message: str = "") -> LivenessSnapshot:
        challenge = self.current_challenge()
        now = time.monotonic()
        if challenge and not self.failed and not self.passed:
            started_at = challenge.started_at or now
            time_left = max(0.0, self.timeout_seconds - (now - started_at))
            retries_left = max(0, self.retry_per_challenge - challenge.attempts_used)
            instruction = (
                challenge.instruction
                if challenge.baseline_seen
                else "Giữ mặt thẳng trong khung hình"
            )
        else:
            time_left = 0.0
            retries_left = 0
            instruction = "Đã hoàn thành" if self.passed else "Đã dừng"

        serialized = []
        for index, item in enumerate(self.challenges):
            hidden = index > self.current_index and item.status == "PENDING"
            serialized.append(
                {
                    "action_id": "" if hidden else item.action_id,
                    "label": "Ẩn đến lượt" if hidden else item.label,
                    "instruction": "" if hidden else item.instruction,
                    "status": item.status,
                    "attempts_used": item.attempts_used,
                    "confidence": item.confidence,
                    "message": item.message,
                    "baseline_seen": item.baseline_seen,
                    "baseline_at": item.baseline_at,
                    "evidence_frames": item.evidence_frames,
                }
            )

        return LivenessSnapshot(
            challenges=serialized,
            current_index=self.current_index,
            current_instruction=instruction,
            passed=self.passed,
            failed=self.failed,
            time_left_seconds=time_left,
            retries_left=retries_left,
            metrics=self.last_metrics,
            message=message,
        )

    def _complete_current(self, challenge: ChallengeState, now: float) -> LivenessSnapshot:
        challenge.status = "PASS"
        challenge.completed_at = now
        challenge.message = "PASS"
        self.current_index += 1
        self.straight_started_at = None
        if self.current_index >= len(self.challenges):
            self.passed = True
            return self.snapshot("Liveness challenge PASS")
        next_challenge = self.challenges[self.current_index]
        next_challenge.started_at = now
        next_challenge.status = "RUNNING"
        next_challenge.message = "Trở về nhìn thẳng trước hành động tiếp theo"
        return self.snapshot("PASS, chuyển sang thử thách tiếp theo")

    def _handle_timeout(self, challenge: ChallengeState, now: float) -> LivenessSnapshot:
        if challenge.attempts_used < self.retry_per_challenge:
            challenge.attempts_used += 1
            challenge.started_at = now
            challenge.status = "RETRY"
            challenge.confidence = 0.0
            challenge.baseline_seen = False
            challenge.baseline_at = None
            challenge.evidence_frames = 0
            challenge.message = "Chưa đạt, vui lòng nhìn thẳng rồi thử lại"
            self.straight_started_at = None
            return self.snapshot(challenge.message)
        challenge.status = "FAIL"
        challenge.completed_at = now
        challenge.message = "FAIL do quá thời gian hoặc hành động chưa đúng"
        self.failed = True
        self.straight_started_at = None
        return self.snapshot(challenge.message)

    def _baseline_ready(
        self,
        challenge: ChallengeState,
        metrics: dict[str, Any],
    ) -> tuple[bool, float]:
        straight, pose_confidence = detect_straight_face(metrics, self.config)
        if not straight:
            return False, pose_confidence
        if challenge.action_id == "blink":
            threshold = float(get_nested(self.config, "liveness.blink_threshold", 0.20))
            blink_score = float(metrics.get("blink_score", 0.0))
            ear = float(metrics.get("eye_aspect_ratio", 0.0))
            eyes_open = blink_score < threshold * 0.5 and (ear <= 0 or ear > threshold * 1.1)
            return eyes_open, 1.0 if eyes_open else 0.0
        if challenge.action_id == "smile":
            threshold = float(get_nested(self.config, "liveness.smile_threshold", 1.30))
            score = float(metrics.get("smile_score", 1.0))
            neutral_limit = 1.0 + (threshold - 1.0) * 0.35
            return score <= neutral_limit, pose_confidence
        if challenge.action_id == "mouth_open":
            threshold = float(get_nested(self.config, "liveness.mouth_open_threshold", 0.60))
            score = float(metrics.get("mouth_open_score", 0.0))
            return score <= threshold * 0.35, pose_confidence
        return True, pose_confidence

    def _evaluate_current(
        self,
        challenge: ChallengeState,
        metrics: dict[str, Any],
        now: float,
    ) -> tuple[bool, float]:
        action_id = challenge.action_id
        if action_id == "turn_left":
            return detect_head_turn(metrics, "left", self.config)
        if action_id == "turn_right":
            return detect_head_turn(metrics, "right", self.config)
        if action_id == "look_up":
            return detect_head_pitch(metrics, "up", self.config)
        if action_id == "look_down":
            return detect_head_pitch(metrics, "down", self.config)
        if action_id == "tilt_left":
            return detect_head_tilt(metrics, "right", self.config)
        if action_id == "tilt_right":
            return detect_head_tilt(metrics, "left", self.config)
        if action_id == "blink":
            return detect_blink(metrics, self.config)
        if action_id == "smile":
            return detect_smile(metrics, self.config)
        if action_id == "mouth_open":
            return detect_mouth_open(metrics, self.config)
        if action_id == "straight_face":
            is_straight, confidence = detect_straight_face(metrics, self.config)
            if is_straight:
                if self.straight_started_at is None:
                    self.straight_started_at = now
                held_seconds = now - self.straight_started_at
                hold_confidence = min(1.0, held_seconds / max(self.straight_face_seconds, 1e-6))
                return held_seconds >= self.straight_face_seconds, min(1.0, max(confidence, hold_confidence))
            self.straight_started_at = None
            return False, confidence
        return False, 0.0


def update_challenge_status(
    engine: LivenessChallengeEngine,
    metrics: dict[str, Any],
    has_valid_face: bool = True,
) -> LivenessSnapshot:
    return engine.update_challenge_status(metrics, has_valid_face=has_valid_face)


def is_liveness_passed(engine: LivenessChallengeEngine) -> bool:
    return engine.is_liveness_passed()


def _metric_subset(metrics: dict[str, Any]) -> dict[str, float]:
    return {
        "yaw": float(metrics.get("yaw", 0.0)),
        "pitch": float(metrics.get("pitch", 0.0)),
        "roll": float(metrics.get("roll", 0.0)),
        "eye_aspect_ratio": float(metrics.get("eye_aspect_ratio", 0.0)),
        "blink_score": float(metrics.get("blink_score", 0.0)),
        "smile_score": float(metrics.get("smile_score", 1.0)),
        "mouth_open_score": float(metrics.get("mouth_open_score", 0.0)),
        "challenge_confidence": float(metrics.get("challenge_confidence", 0.0)),
    }
