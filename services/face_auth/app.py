from __future__ import annotations

from datetime import datetime
import time
from typing import Any

import cv2
import numpy as np
import streamlit as st

from modules.anti_spoofing import AntiSpoofingResult, LightweightOnnxAntiSpoofing
from modules.face_detector import FaceDetectionResult, MediaPipeFaceDetector
from modules.face_recognizer import InsightFaceRecognizer, RecognitionResult
from modules.liveness_challenge import LivenessChallengeEngine, LivenessSnapshot
from modules.utils import (
    bgr_to_rgb,
    crop_face,
    draw_detection_overlay,
    ensure_runtime_dirs,
    get_nested,
    load_config,
    resolve_demo_path,
    save_frame,
    setup_logging,
)


st.set_page_config(page_title="Face Auth Demo", layout="wide")


def main() -> None:
    config = load_config()
    ensure_runtime_dirs(config)
    logger = setup_logging(config)
    install_styles()

    st.title("Demo xác thực khuôn mặt local")
    st.caption("MediaPipe -> Liveness challenge -> MobileNetV3 ONNX PAD -> InsightFace Recognition")

    with st.sidebar:
        st.header("Điều khiển")
        mode = st.radio("Chế độ test", ["Camera realtime", "Upload ảnh"], index=0)
        max_runtime_seconds = st.slider("Giới hạn phiên camera", 30, 180, 90, 10)
        start_camera = st.button("Bắt đầu xác thực", type="primary", use_container_width=True)
        reset_challenge = st.button("Reset thử thách", use_container_width=True)
        capture_frame = st.button("Chụp frame hiện tại", use_container_width=True)
        st.divider()
        st.metric("Real face threshold", f"{get_nested(config, 'thresholds.real_face_threshold', 0.8):.0%}")
        st.metric("Recognition threshold", f"{get_nested(config, 'thresholds.recognition_threshold', 0.6):.0%}")
        st.metric("Số challenge", int(get_nested(config, "liveness.number_of_challenges", 5)))

    if reset_challenge:
        for key in ("liveness_engine", "last_anti_result", "last_recognition_result", "last_final"):
            st.session_state.pop(key, None)
        st.success("Đã reset thử thách. Phiên camera kế tiếp sẽ sinh challenge mới.")

    if capture_frame:
        frame = st.session_state.get("last_frame")
        if frame is None:
            st.warning("Chưa có frame nào để lưu.")
        else:
            saved_path = save_frame(frame, resolve_demo_path(config, "output_path", "outputs"))
            st.success(f"Đã lưu frame: {saved_path}")

    camera_slot = st.empty()
    checklist_slot = st.empty()
    liveness_slot = st.empty()
    anti_slot = st.empty()
    recognition_slot = st.empty()
    final_slot = st.empty()

    if mode == "Upload ảnh":
        uploaded = st.file_uploader("Upload ảnh để test pipeline ảnh tĩnh", type=["jpg", "jpeg", "png", "bmp", "webp"])
        if uploaded is not None:
            frame = decode_uploaded_image(uploaded.getvalue())
            if frame is None:
                st.error("Không đọc được ảnh upload.")
                return
            logger.info("Bắt đầu xác thực ảnh tĩnh: %s", uploaded.name)
            process_static_image(
                frame=frame,
                config=config,
                logger=logger,
                camera_slot=camera_slot,
                checklist_slot=checklist_slot,
                liveness_slot=liveness_slot,
                anti_slot=anti_slot,
                recognition_slot=recognition_slot,
                final_slot=final_slot,
            )
        else:
            render_empty_state(camera_slot, checklist_slot, liveness_slot, anti_slot, recognition_slot, final_slot)
        return

    render_empty_state(camera_slot, checklist_slot, liveness_slot, anti_slot, recognition_slot, final_slot)
    if start_camera:
        run_camera_session(
            config=config,
            logger=logger,
            max_runtime_seconds=max_runtime_seconds,
            camera_slot=camera_slot,
            checklist_slot=checklist_slot,
            liveness_slot=liveness_slot,
            anti_slot=anti_slot,
            recognition_slot=recognition_slot,
            final_slot=final_slot,
        )


def get_detector(config: dict[str, Any]) -> MediaPipeFaceDetector:
    if "detector" not in st.session_state:
        st.session_state.detector = MediaPipeFaceDetector(config)
    return st.session_state.detector


def get_anti_spoofing(config: dict[str, Any]) -> LightweightOnnxAntiSpoofing:
    if "anti_spoofing" not in st.session_state:
        st.session_state.anti_spoofing = LightweightOnnxAntiSpoofing(config)
    return st.session_state.anti_spoofing


def get_recognizer(config: dict[str, Any]) -> InsightFaceRecognizer:
    if "recognizer" not in st.session_state:
        st.session_state.recognizer = InsightFaceRecognizer(config)
    return st.session_state.recognizer


def run_camera_session(
    config: dict[str, Any],
    logger: Any,
    max_runtime_seconds: int,
    camera_slot: Any,
    checklist_slot: Any,
    liveness_slot: Any,
    anti_slot: Any,
    recognition_slot: Any,
    final_slot: Any,
) -> None:
    camera_id = int(get_nested(config, "camera.camera_id", 0))
    width = int(get_nested(config, "camera.frame_width", 1280))
    height = int(get_nested(config, "camera.frame_height", 720))

    try:
        detector = get_detector(config)
    except Exception as exc:
        st.error(str(exc))
        return

    engine = LivenessChallengeEngine(config)
    st.session_state.liveness_engine = engine
    logger.info("Thời gian bắt đầu xác thực: %s", datetime.now().isoformat(timespec="seconds"))
    logger.info("Liveness challenge list: %s", [item.label for item in engine.challenges])

    cap = cv2.VideoCapture(camera_id, getattr(cv2, "CAP_DSHOW", 0))
    if not cap.isOpened():
        cap = cv2.VideoCapture(camera_id)
    if not cap.isOpened():
        final_slot.error(f"Không mở được camera_id={camera_id}. Kiểm tra webcam hoặc đổi camera.camera_id trong config.yaml.")
        logger.error("Không mở được camera_id=%s", camera_id)
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

    anti_result: AntiSpoofingResult | None = None
    recognition_result: RecognitionResult | None = None
    final_message = "Đang xác thực"
    final_ok = False
    started_at = time.perf_counter()
    last_log_at = 0.0
    last_challenge_status = ""
    annotated = None

    try:
        while time.perf_counter() - started_at < max_runtime_seconds:
            ok, frame = cap.read()
            if not ok or frame is None:
                final_message = "XÁC THỰC THẤT BẠI: không đọc được frame từ camera"
                logger.error(final_message)
                break

            frame = cv2.flip(frame, 1)
            detection = detector.detect(frame)
            metrics = detector.detection_metrics(detection)
            face = detection.primary_face
            has_face_for_liveness = bool(
                face
                and face.checks.get("detected")
                and face.checks.get("single_face")
                and face.checks.get("face_size")
                and face.checks.get("centered")
                and face.checks.get("brightness")
            )
            liveness_snapshot = engine.update_challenge_status(metrics, has_valid_face=has_face_for_liveness)
            metrics["challenge_confidence"] = _current_confidence(liveness_snapshot)

            message = detection.messages[0] if detection.messages else liveness_snapshot.current_instruction
            if detection.face_count == 1 and not engine.passed and not engine.failed:
                message = liveness_snapshot.current_instruction
            annotated = draw_detection_overlay(
                frame,
                face,
                show_box=bool(get_nested(config, "ui.show_bounding_box", True)),
                show_landmarks=bool(get_nested(config, "ui.show_landmarks", True)),
                message=message,
            )
            st.session_state.last_frame = annotated.copy()

            if time.perf_counter() - last_log_at > 1.0:
                log_detection(logger, detection, metrics)
                last_log_at = time.perf_counter()

            current_status = _challenge_status_signature(liveness_snapshot)
            if current_status != last_challenge_status:
                logger.info("Challenge status: %s", current_status)
                last_challenge_status = current_status

            render_camera(camera_slot, annotated)
            render_checklist(checklist_slot, detection, liveness_snapshot, anti_result, recognition_result)
            render_liveness(liveness_slot, liveness_snapshot)
            render_anti_spoofing(anti_slot, anti_result)
            render_recognition(recognition_slot, recognition_result)
            render_final(final_slot, final_message, final_ok, pending=True)

            if engine.failed:
                final_message = "XÁC THỰC THẤT BẠI: không vượt qua thử thách sống"
                logger.info("Final decision: %s", final_message)
                break

            if engine.passed:
                if not face:
                    final_message = "XÁC THỰC THẤT BẠI: không còn khuôn mặt ở bước anti-spoofing"
                    logger.info("Final decision: %s", final_message)
                    break

                anti_result = get_anti_spoofing(config).predict(frame, face.bbox)
                logger.info(
                    "Anti-spoofing scores: real=%.3f printed=%.3f screen=%.3f unknown=%.3f threshold=%.3f label=%s error=%s",
                    anti_result.real_score,
                    anti_result.printed_photo_score,
                    anti_result.screen_replay_score,
                    anti_result.unknown_spoof_score,
                    anti_result.threshold,
                    anti_result.label,
                    anti_result.error,
                )
                render_anti_spoofing(anti_slot, anti_result)
                if not anti_result.is_real:
                    final_message = "XÁC THỰC THẤT BẠI: khuôn mặt có dấu hiệu giả mạo"
                    logger.info("Final decision: %s", final_message)
                    break

                face_crop = crop_face(frame, face.bbox)
                recognition_result = get_recognizer(config).recognize(face_crop)
                logger.info(
                    "Recognition similarity: name=%s similarity=%.3f distance=%.3f threshold=%.3f pass=%s error=%s",
                    recognition_result.best_match_name,
                    recognition_result.similarity,
                    recognition_result.distance,
                    recognition_result.recognition_threshold,
                    recognition_result.is_recognized,
                    recognition_result.error,
                )
                render_recognition(recognition_slot, recognition_result)
                if recognition_result.is_recognized:
                    final_message = "XÁC THỰC THÀNH CÔNG"
                    final_ok = True
                else:
                    final_message = "XÁC THỰC THẤT BẠI: không khớp danh tính"
                logger.info("Final decision: %s", final_message)
                break

            time.sleep(0.03)
        else:
            final_message = "XÁC THỰC THẤT BẠI: phiên camera quá thời gian"
            logger.info("Final decision: %s", final_message)
    finally:
        cap.release()

    if annotated is not None:
        render_camera(camera_slot, annotated)
    render_checklist(checklist_slot, detection if "detection" in locals() else None, engine.snapshot(), anti_result, recognition_result)
    render_liveness(liveness_slot, engine.snapshot())
    render_anti_spoofing(anti_slot, anti_result)
    render_recognition(recognition_slot, recognition_result)
    render_final(final_slot, final_message, final_ok)


def process_static_image(
    frame: np.ndarray,
    config: dict[str, Any],
    logger: Any,
    camera_slot: Any,
    checklist_slot: Any,
    liveness_slot: Any,
    anti_slot: Any,
    recognition_slot: Any,
    final_slot: Any,
) -> None:
    detector = get_detector(config)
    detection = detector.detect(frame)
    metrics = detector.detection_metrics(detection)
    log_detection(logger, detection, metrics)
    face = detection.primary_face
    annotated = draw_detection_overlay(
        frame,
        face,
        show_box=bool(get_nested(config, "ui.show_bounding_box", True)),
        show_landmarks=bool(get_nested(config, "ui.show_landmarks", True)),
        message=detection.messages[0] if detection.messages else "Ảnh upload",
    )
    st.session_state.last_frame = annotated.copy()
    render_camera(camera_slot, annotated)

    liveness_snapshot = static_liveness_snapshot(config)
    anti_result: AntiSpoofingResult | None = None
    recognition_result: RecognitionResult | None = None
    final_message = "Ảnh tĩnh: liveness challenge chỉ hỗ trợ camera realtime"
    final_ok = False

    if detection.face_count != 1 or face is None:
        final_message = "XÁC THỰC THẤT BẠI: không phát hiện đúng 1 khuôn mặt"
    else:
        anti_result = get_anti_spoofing(config).predict(frame, face.bbox)
        logger.info(
            "Anti-spoofing scores: real=%.3f printed=%.3f screen=%.3f unknown=%.3f threshold=%.3f label=%s error=%s",
            anti_result.real_score,
            anti_result.printed_photo_score,
            anti_result.screen_replay_score,
            anti_result.unknown_spoof_score,
            anti_result.threshold,
            anti_result.label,
            anti_result.error,
        )
        if anti_result.is_real:
            recognition_result = get_recognizer(config).recognize(crop_face(frame, face.bbox))
            logger.info(
                "Recognition similarity: name=%s similarity=%.3f distance=%.3f threshold=%.3f pass=%s error=%s",
                recognition_result.best_match_name,
                recognition_result.similarity,
                recognition_result.distance,
                recognition_result.recognition_threshold,
                recognition_result.is_recognized,
                recognition_result.error,
            )
            if recognition_result.is_recognized:
                final_message = "XÁC THỰC THÀNH CÔNG (ảnh tĩnh, bỏ qua liveness realtime)"
                final_ok = True
            else:
                final_message = "XÁC THỰC THẤT BẠI: không khớp danh tính"
        else:
            final_message = "XÁC THỰC THẤT BẠI: khuôn mặt có dấu hiệu giả mạo"

    logger.info("Final decision: %s", final_message)
    render_checklist(checklist_slot, detection, liveness_snapshot, anti_result, recognition_result)
    render_liveness(liveness_slot, liveness_snapshot, static_mode=True)
    render_anti_spoofing(anti_slot, anti_result)
    render_recognition(recognition_slot, recognition_result)
    render_final(final_slot, final_message, final_ok)


def render_empty_state(
    camera_slot: Any,
    checklist_slot: Any,
    liveness_slot: Any,
    anti_slot: Any,
    recognition_slot: Any,
    final_slot: Any,
) -> None:
    camera_slot.info("Chọn chế độ test, sau đó bấm bắt đầu hoặc upload ảnh.")
    render_checklist(checklist_slot, None, None, None, None)
    render_liveness(liveness_slot, None)
    render_anti_spoofing(anti_slot, None)
    render_recognition(recognition_slot, None)
    render_final(final_slot, "Chưa bắt đầu xác thực", False, pending=True)


def render_camera(slot: Any, frame_bgr: np.ndarray) -> None:
    slot.image(bgr_to_rgb(frame_bgr), channels="RGB", use_container_width=True)


def render_checklist(
    slot: Any,
    detection: FaceDetectionResult | None,
    liveness: LivenessSnapshot | None,
    anti: AntiSpoofingResult | None,
    recognition: RecognitionResult | None,
) -> None:
    face = detection.primary_face if detection else None
    checks = face.checks if face else {}
    rows = [
        ("Phát hiện khuôn mặt", detection.face_count > 0 if detection else None),
        ("Chỉ có 1 khuôn mặt", detection.face_count == 1 if detection else None),
        ("Mặt đủ lớn", checks.get("face_size") if detection else None),
        ("Mặt nằm giữa khung hình", checks.get("centered") if detection else None),
        ("Ánh sáng đạt", checks.get("brightness") if detection else None),
        ("Góc mặt hợp lệ", checks.get("pose") if detection else None),
        ("Liveness challenge", liveness.passed if liveness else None),
        ("Anti-spoofing", anti.is_real if anti else None),
        ("Recognition", recognition.is_recognized if recognition else None),
    ]
    with slot.container():
        st.subheader("Checklist")
        for label, status in rows:
            st.markdown(f"{badge(status)} {label}", unsafe_allow_html=True)


def render_liveness(slot: Any, snapshot: LivenessSnapshot | None, static_mode: bool = False) -> None:
    with slot.container():
        st.subheader("Liveness challenge")
        if snapshot is None:
            st.info("Chưa sinh thử thách.")
            return
        if static_mode:
            st.warning("Liveness challenge chỉ hỗ trợ camera realtime. Ảnh upload sẽ bỏ qua bước này.")
        st.write(f"Thử thách hiện tại: **{snapshot.current_instruction}**")
        col1, col2, col3 = st.columns(3)
        col1.metric("Thời gian còn lại", f"{snapshot.time_left_seconds:.1f}s")
        col2.metric("Retry còn lại", snapshot.retries_left)
        col3.metric("Challenge confidence", f"{_current_confidence(snapshot) * 100:.1f}%")
        st.dataframe(
            [
                {
                    "Thử thách": item["label"],
                    "Trạng thái": item["status"],
                    "Retry đã dùng": item["attempts_used"],
                    "Confidence": f"{item['confidence'] * 100:.1f}%",
                }
                for item in snapshot.challenges
            ],
            use_container_width=True,
            hide_index=True,
        )
        metrics = snapshot.metrics
        metric_cols = st.columns(6)
        metric_cols[0].metric("Head yaw", f"{metrics.get('yaw', 0.0):.1f}°")
        metric_cols[1].metric("Head pitch", f"{metrics.get('pitch', 0.0):.1f}°")
        metric_cols[2].metric("Head roll", f"{metrics.get('roll', 0.0):.1f}°")
        metric_cols[3].metric("Eye aspect ratio", f"{metrics.get('eye_aspect_ratio', 0.0):.3f}")
        metric_cols[4].metric("Smile score", f"{metrics.get('smile_score', 0.0):.3f}")
        metric_cols[5].metric("Mouth open", f"{metrics.get('mouth_open_score', 0.0):.3f}")


def render_anti_spoofing(slot: Any, result: AntiSpoofingResult | None) -> None:
    with slot.container():
        st.subheader("Anti-spoofing score")
        if result is None:
            st.info("Chưa chạy anti-spoofing.")
            return
        if result.error:
            st.error(result.error)
        cols = st.columns(4)
        cols[0].metric("Real face", f"{result.real_score * 100:.1f}%")
        cols[1].metric("Printed photo", f"{result.printed_photo_score * 100:.1f}%")
        cols[2].metric("Screen replay", f"{result.screen_replay_score * 100:.1f}%")
        cols[3].metric("Unknown spoof", f"{result.unknown_spoof_score * 100:.1f}%")
        st.progress(min(1.0, max(0.0, result.real_score)), text=f"Real threshold: {result.threshold:.0%}")
        st.markdown(f"{badge(result.is_real)} Kết luận anti-spoofing: **{result.label}**")


def render_recognition(slot: Any, result: RecognitionResult | None) -> None:
    with slot.container():
        st.subheader("Recognition score")
        if result is None:
            st.info("Chưa chạy nhận diện danh tính.")
            return
        if result.error:
            st.error(result.error)
        cols = st.columns(4)
        cols[0].metric("Candidate name", result.best_match_name)
        cols[1].metric("Similarity", f"{result.similarity_percent:.1f}%")
        cols[2].metric("Distance", f"{result.distance:.4f}")
        cols[3].metric("Threshold", f"{result.recognition_threshold * 100:.1f}%")
        st.markdown(f"{badge(result.is_recognized)} Kết luận recognition")


def render_final(slot: Any, message: str, ok: bool, pending: bool = False) -> None:
    with slot.container():
        st.subheader("Kết quả cuối")
        if pending:
            st.info(message)
        elif ok:
            st.success(message)
        else:
            st.error(message)


def badge(status: bool | None) -> str:
    if status is True:
        return "<span class='badge pass'>PASS</span>"
    if status is False:
        return "<span class='badge fail'>FAIL</span>"
    return "<span class='badge wait'>WAIT</span>"


def decode_uploaded_image(data: bytes) -> np.ndarray | None:
    array = np.frombuffer(data, dtype=np.uint8)
    return cv2.imdecode(array, cv2.IMREAD_COLOR)


def static_liveness_snapshot(config: dict[str, Any]) -> LivenessSnapshot:
    engine = LivenessChallengeEngine(config)
    snapshot = engine.snapshot("Liveness challenge chỉ hỗ trợ camera realtime")
    snapshot.passed = True
    snapshot.failed = False
    snapshot.current_instruction = "Bỏ qua với ảnh upload"
    for item in snapshot.challenges:
        item["status"] = "SKIP"
        item["message"] = "Ảnh tĩnh"
    return snapshot


def log_detection(logger: Any, detection: FaceDetectionResult, metrics: dict[str, Any]) -> None:
    logger.info("Có phát hiện mặt không: %s", detection.face_count > 0)
    logger.info("Số lượng khuôn mặt: %d", detection.face_count)
    if detection.primary_face:
        logger.info("Face bbox: %s", detection.primary_face.bbox)
        logger.info("Brightness score: %.2f", detection.primary_face.brightness)
        logger.info(
            "Yaw/Pitch/Roll: %.2f / %.2f / %.2f",
            metrics.get("yaw", 0.0),
            metrics.get("pitch", 0.0),
            metrics.get("roll", 0.0),
        )


def _current_confidence(snapshot: LivenessSnapshot) -> float:
    if snapshot.current_index < len(snapshot.challenges):
        return float(snapshot.challenges[snapshot.current_index].get("confidence", 0.0))
    if snapshot.challenges:
        return float(snapshot.challenges[-1].get("confidence", 1.0))
    return 0.0


def _challenge_status_signature(snapshot: LivenessSnapshot) -> str:
    statuses = [f"{item['label']}={item['status']}:{item['attempts_used']}" for item in snapshot.challenges]
    return " | ".join(statuses)


def install_styles() -> None:
    st.markdown(
        """
        <style>
        .badge {
            display: inline-block;
            min-width: 58px;
            padding: 2px 8px;
            border-radius: 6px;
            color: white;
            font-size: 12px;
            font-weight: 700;
            text-align: center;
            margin-right: 8px;
        }
        .pass { background: #16803c; }
        .fail { background: #b42318; }
        .wait { background: #667085; }
        div[data-testid="stMetricValue"] {
            font-size: 20px;
        }
        </style>
        """,
        unsafe_allow_html=True,
    )


if __name__ == "__main__":
    main()
