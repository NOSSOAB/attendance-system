from __future__ import annotations

import argparse
import concurrent.futures
from dataclasses import dataclass
from datetime import datetime
import time
from typing import Any
import unicodedata

import cv2

from modules.anti_spoofing import AntiSpoofingResult, LightweightOnnxAntiSpoofing
from modules.face_detector import FaceDetectionResult, MediaPipeFaceDetector
from modules.face_quality import score_recognition_frame
from modules.face_recognizer import InsightFaceRecognizer, RecognitionResult
from modules.liveness_challenge import LivenessChallengeEngine, LivenessSnapshot
from modules.utils import (
    crop_face,
    ensure_runtime_dirs,
    get_nested,
    load_config,
    resolve_demo_path,
    save_frame,
    setup_logging,
)


WINDOW_NAME = "Face Auth Demo - Local Camera"


@dataclass(frozen=True)
class VerifiedSample:
    anti_result: AntiSpoofingResult
    recognition_result: RecognitionResult
    completed_at: float


def better_verified_sample(
    current: VerifiedSample | None,
    anti_result: AntiSpoofingResult | None,
    recognition_result: RecognitionResult | None,
    completed_at: float,
) -> VerifiedSample | None:
    if (
        anti_result is None
        or recognition_result is None
        or not anti_result.is_real
        or not recognition_result.is_recognized
    ):
        return current
    candidate = VerifiedSample(anti_result, recognition_result, completed_at)
    if current is None or candidate.recognition_result.similarity > current.recognition_result.similarity:
        return candidate
    return current


def main() -> int:
    parser = argparse.ArgumentParser(description="Local OpenCV face authentication demo.")
    parser.add_argument("--config", default="config.yaml", help="Path to config.yaml")
    parser.add_argument("--camera-id", type=int, default=None, help="Override camera.camera_id")
    parser.add_argument("--skip-liveness", action="store_true", help="Skip liveness challenge for quick testing")
    parser.add_argument("--target", default=None, help="Person name in face_db.pkl. If omitted, choose before camera opens")
    args = parser.parse_args()

    config = load_config(args.config)
    ensure_runtime_dirs(config)
    logger = setup_logging(config, "face_auth_camera")
    if args.skip_liveness:
        config.setdefault("liveness", {})["enabled"] = False

    print("\n=== FACE AUTH DEMO - LOCAL CAMERA ===")
    print("Phim tat:")
    print("  R: reset xac thuc")
    print("  C: chup frame luu vao outputs/")
    print("  Q hoac ESC: thoat")
    print("=====================================\n")

    try:
        detector = MediaPipeFaceDetector(config)
        anti_spoofing = LightweightOnnxAntiSpoofing(config)
        recognizer = InsightFaceRecognizer(config)
        database = recognizer.load_database()
        target_name = choose_target_person(database, args.target)
        preload_started = time.perf_counter()
        print(f"[INFO] Target identity: {target_name}")
        logger.info("Target identity: %s", target_name)
        print("[INFO] Dang nap truoc model InsightFace/MobileNetV3 PAD, vui long doi...")
        anti_spoofing._ensure_loaded()
        recognizer._ensure_app()
        print(f"[INFO] Preload model xong sau {time.perf_counter() - preload_started:.1f}s")
    except Exception as exc:
        print(f"[ERROR] Khoi tao module that bai: {exc}")
        logger.exception("Khoi tao module that bai")
        return 1

    camera_id = args.camera_id if args.camera_id is not None else int(get_nested(config, "camera.camera_id", 0))
    frame_width = int(get_nested(config, "camera.frame_width", 1280))
    frame_height = int(get_nested(config, "camera.frame_height", 720))

    cap = open_camera(camera_id, frame_width, frame_height)
    if not cap.isOpened():
        print(f"[ERROR] Khong mo duoc camera_id={camera_id}. Hay doi camera_id trong config.yaml hoac dung --camera-id 1")
        logger.error("Khong mo duoc camera_id=%s", camera_id)
        return 1

    engine = new_liveness_engine(config, logger)
    anti_result: AntiSpoofingResult | None = None
    recognition_result: RecognitionResult | None = None
    final_message = ""
    final_ok = False
    mode = "LIVENESS"
    model_future: concurrent.futures.Future | None = None
    passive_future: concurrent.futures.Future | None = None
    last_passive_submit_at = 0.0
    last_passive_completed_at = 0.0
    processing_started_at: float | None = None
    best_verified_sample: VerifiedSample | None = None
    best_model_frame = None
    best_model_bbox: tuple[int, int, int, int] | None = None
    best_detection: FaceDetectionResult | None = None
    best_frame_quality = -1.0
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
    last_log_at = 0.0
    last_challenge_signature = ""
    last_frame = None
    last_raw_frame = None

    logger.info("Thoi gian bat dau xac thuc: %s", datetime.now().isoformat(timespec="seconds"))

    try:
        while True:
            ok, camera_frame = cap.read()
            if not ok or camera_frame is None:
                print("[ERROR] Khong doc duoc frame tu camera.")
                logger.error("Khong doc duoc frame tu camera")
                break

            frame = cv2.flip(camera_frame, 1)
            detection = detector.detect(frame)
            metrics = detector.detection_metrics(detection)
            face = detection.primary_face
            liveness_snapshot = engine.snapshot()

            if passive_future is not None and passive_future.done():
                try:
                    candidate_anti, candidate_recognition, _passive_ok, passive_message = passive_future.result()
                    last_passive_completed_at = time.perf_counter()
                    best_verified_sample = better_verified_sample(
                        best_verified_sample,
                        candidate_anti,
                        candidate_recognition,
                        last_passive_completed_at,
                    )
                    if (
                        candidate_recognition is not None
                        and (
                            recognition_result is None
                            or candidate_recognition.similarity > recognition_result.similarity
                        )
                    ):
                        anti_result = candidate_anti
                        recognition_result = candidate_recognition
                    logger.info("Passive model check: %s", passive_message)
                    if best_verified_sample is not None:
                        logger.info(
                            "Best verified live sample: similarity=%.3f real=%.3f",
                            best_verified_sample.recognition_result.similarity,
                            best_verified_sample.anti_result.real_score,
                        )
                except Exception as exc:
                    logger.exception("Passive model check failed")
                passive_future = None

            if mode == "PROCESSING":
                if model_future is not None and model_future.done():
                    try:
                        anti_result, recognition_result, final_ok, final_message = model_future.result()
                    except Exception as exc:
                        logger.exception("Model check worker failed")
                        anti_result = None
                        recognition_result = None
                        final_ok = False
                        final_message = f"FAILED: model worker error: {exc}"
                    mode = "DONE"
                    model_future = None
                    processing_started_at = None
                    logger.info("Final decision: %s", final_message)
                    print(f"[RESULT] {final_message}")
                else:
                    elapsed = time.perf_counter() - (processing_started_at or time.perf_counter())
                    final_message = f"Processing anti-spoofing/recognition... {elapsed:.1f}s"

            if mode == "LIVENESS":
                has_valid_face = bool(
                    face
                    and face.checks.get("detected")
                    and face.checks.get("single_face")
                    and face.checks.get("face_size")
                    and face.checks.get("brightness")
                )
                if has_valid_face:
                    liveness_snapshot = engine.update_challenge_status(metrics, has_valid_face=True)
                else:
                    engine.pause_current_challenge()
                    liveness_snapshot = engine.snapshot("Face not ready - challenge timer paused")
                frame_quality = score_recognition_frame(
                    detection,
                    float(get_nested(config, "backend.final_pose_limit", 20.0)),
                )
                if frame_quality > best_frame_quality:
                    best_model_frame = camera_frame.copy()
                    best_model_bbox = mirror_bbox(face.bbox, camera_frame.shape[1]) if face is not None else None
                    best_detection = detection
                    best_frame_quality = frame_quality
                signature = challenge_signature(liveness_snapshot)
                if signature != last_challenge_signature:
                    logger.info("Ket qua tung challenge: %s", signature)
                    last_challenge_signature = signature

                now = time.perf_counter()
                if (
                    passive_future is None
                    and model_future is None
                    and now - last_passive_submit_at >= 2.0
                    and passive_model_ready(detection)
                ):
                    last_passive_submit_at = now
                    passive_future = executor.submit(
                        run_model_checks,
                        camera_frame.copy(),
                        detection,
                        anti_spoofing,
                        recognizer,
                        logger,
                        target_name,
                        mirror_bbox(face.bbox, camera_frame.shape[1]) if face is not None else None,
                    )
                    logger.info("Passive model check submitted during liveness")

                if engine.failed:
                    mode = "DONE"
                    final_ok = False
                    final_message = "FAILED: liveness challenge failed"
                    logger.info("Final decision: %s", final_message)

                if engine.passed and mode == "LIVENESS":
                    print("[INFO] Liveness PASS. Dang dung mau tot nhat cua phien de ket luan...")
                    logger.info("Liveness challenge PASS")
                    if best_verified_sample is not None:
                        anti_result = best_verified_sample.anti_result
                        recognition_result = best_verified_sample.recognition_result
                        final_ok = True
                        final_message = "SUCCESS: face authentication passed"
                        mode = "DONE"
                        logger.info(
                            "Final decision from verified live sample: %s similarity=%.3f real=%.3f",
                            final_message,
                            recognition_result.similarity,
                            anti_result.real_score,
                        )
                        print(f"[RESULT] {final_message}")
                    else:
                        selected_frame = best_model_frame.copy() if best_model_frame is not None else camera_frame.copy()
                        selected_detection = best_detection or detection
                        selected_bbox = best_model_bbox
                        if selected_bbox is None and face is not None:
                            selected_bbox = mirror_bbox(face.bbox, camera_frame.shape[1])
                        mode = "PROCESSING"
                        processing_started_at = time.perf_counter()
                        final_message = "Processing best liveness frame... 0.0s"
                        model_future = executor.submit(
                            run_model_checks,
                            selected_frame,
                            selected_detection,
                            anti_spoofing,
                            recognizer,
                            logger,
                            target_name,
                            selected_bbox,
                        )
                        logger.info("Final model check submitted with frame quality %.3f", best_frame_quality)

            if time.perf_counter() - last_log_at >= 1.0:
                log_detection(logger, detection)
                last_log_at = time.perf_counter()

            annotated = draw_overlay(
                frame=frame,
                detection=detection,
                liveness=liveness_snapshot,
                anti_result=anti_result,
                recognition_result=recognition_result,
                final_message=final_message,
                final_ok=final_ok,
                mode=mode,
                target_name=target_name,
                config=config,
            )
            last_frame = annotated
            last_raw_frame = camera_frame.copy()
            cv2.imshow(WINDOW_NAME, annotated)

            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q"), ord("Q")):
                break
            if key in (ord("r"), ord("R")):
                engine = new_liveness_engine(config, logger)
                anti_result = None
                recognition_result = None
                final_message = ""
                final_ok = False
                mode = "LIVENESS"
                model_future = None
                passive_future = None
                last_passive_submit_at = 0.0
                last_passive_completed_at = 0.0
                processing_started_at = None
                best_verified_sample = None
                best_model_frame = None
                best_model_bbox = None
                best_detection = None
                best_frame_quality = -1.0
                last_challenge_signature = ""
                print("[INFO] Da reset. Bat dau lai phien xac thuc moi.")
                logger.info("Reset phien xac thuc")
            if key in (ord("c"), ord("C")) and last_frame is not None and last_raw_frame is not None:
                output_path = resolve_demo_path(config, "output_path", "outputs")
                raw_path = save_frame(last_raw_frame, output_path, prefix="capture_raw")
                screen_path = save_frame(last_frame, output_path, prefix="capture_screen")
                print(f"[INFO] Da luu frame goc: {raw_path}")
                print(f"[INFO] Da luu anh giao dien: {screen_path}")
                logger.info("Da luu frame goc: %s | giao dien: %s", raw_path, screen_path)
    finally:
        cap.release()
        executor.shutdown(wait=False, cancel_futures=True)
        cv2.destroyAllWindows()

    return 0


def open_camera(camera_id: int, width: int, height: int) -> cv2.VideoCapture:
    cap = cv2.VideoCapture(camera_id, getattr(cv2, "CAP_DSHOW", 0))
    if not cap.isOpened():
        cap.release()
        cap = cv2.VideoCapture(camera_id)
    if cap.isOpened():
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    return cap


def mirror_bbox(
    bbox: tuple[int, int, int, int],
    frame_width: int,
) -> tuple[int, int, int, int]:
    x1, y1, x2, y2 = bbox
    return frame_width - x2, y1, frame_width - x1, y2


def new_liveness_engine(config: dict[str, Any], logger: Any) -> LivenessChallengeEngine:
    engine = LivenessChallengeEngine(config)
    print("[INFO] Challenge list:")
    for index, challenge in enumerate(engine.challenges, start=1):
        print(f"  {index}. {challenge.label}")
    logger.info("Liveness challenge list: %s", [item.label for item in engine.challenges])
    return engine


def choose_target_person(database: dict[str, Any], requested: str | None = None) -> str:
    persons = sorted(str(name) for name in database.get("persons", {}).keys())
    if not persons:
        raise ValueError("face_db.pkl chua co nguoi nao. Hay them anh vao database_faces/ roi chay python enroll_faces.py")

    if requested:
        if requested in persons:
            return requested
        choices = ", ".join(persons)
        raise ValueError(f"Khong tim thay target '{requested}' trong face_db.pkl. Danh sach hien co: {choices}")

    print("\n=== CHON NGUOI CAN XAC THUC ===")
    for index, person_name in enumerate(persons, start=1):
        print(f"  {index}. {person_name}")
    print("Nhan Enter de chon nguoi dau tien.")

    while True:
        raw = input("Nhap so thu tu hoac ten nguoi: ").strip()
        if not raw:
            return persons[0]
        if raw.isdigit():
            index = int(raw) - 1
            if 0 <= index < len(persons):
                return persons[index]
        if raw in persons:
            return raw
        print("Lua chon khong hop le, vui long nhap lai.")


def run_model_checks(
    frame: Any,
    detection: FaceDetectionResult,
    anti_spoofing: LightweightOnnxAntiSpoofing,
    recognizer: InsightFaceRecognizer,
    logger: Any,
    target_name: str,
    face_bbox: tuple[int, int, int, int] | None = None,
) -> tuple[AntiSpoofingResult | None, RecognitionResult | None, bool, str]:
    face = detection.primary_face
    if detection.face_count != 1 or face is None:
        return None, None, False, "FAILED: face not valid before anti-spoofing"

    anti_started = time.perf_counter()
    model_bbox = face_bbox or face.bbox
    anti_result = anti_spoofing.predict(frame, model_bbox)
    logger.info(
        "Anti-spoofing scores: real=%.3f printed=%.3f screen=%.3f unknown=%.3f threshold=%.3f pass=%s error=%s",
        anti_result.real_score,
        anti_result.printed_photo_score,
        anti_result.screen_replay_score,
        anti_result.unknown_spoof_score,
        anti_result.threshold,
        anti_result.is_real,
        anti_result.error,
    )
    logger.info("Anti-spoofing time: %.1f ms", (time.perf_counter() - anti_started) * 1000)
    if not anti_result.is_real:
        return anti_result, None, False, "FAILED: spoof suspected"

    recognition_started = time.perf_counter()
    full_frame_result = recognizer.recognize(frame, target_name=target_name)
    crop_result = recognizer.recognize(crop_face(frame, model_bbox), target_name=target_name)
    recognition_result = pick_better_recognition(full_frame_result, crop_result)
    logger.info(
        "Recognition similarity: target=%s name=%s similarity=%.3f distance=%.3f threshold=%.3f strategy=%s pass=%s error=%s",
        target_name,
        recognition_result.best_match_name,
        recognition_result.similarity,
        recognition_result.distance,
        recognition_result.recognition_threshold,
        recognition_result.match_strategy,
        recognition_result.is_recognized,
        recognition_result.error,
    )
    logger.info(
        "Recognition compare modes: full_frame=%.3f err=%s | crop=%.3f err=%s",
        full_frame_result.similarity,
        full_frame_result.error,
        crop_result.similarity,
        crop_result.error,
    )
    logger.info("Recognition time: %.1f ms", (time.perf_counter() - recognition_started) * 1000)
    if recognition_result.is_recognized:
        return anti_result, recognition_result, True, "SUCCESS: face authentication passed"
    return anti_result, recognition_result, False, "FAILED: identity not matched"


def passive_model_ready(detection: FaceDetectionResult) -> bool:
    face = detection.primary_face
    if detection.face_count != 1 or face is None:
        return False
    if not face.checks.get("face_size", False):
        return False
    if not face.checks.get("centered", False):
        return False
    if not face.checks.get("brightness", False):
        return False
    if abs(face.yaw) > 16 or abs(face.pitch) > 16 or abs(face.roll) > 16:
        return False
    if face.mouth_open_score > 0.45:
        return False
    return True


def pick_better_recognition(
    full_frame_result: RecognitionResult,
    crop_result: RecognitionResult,
) -> RecognitionResult:
    if full_frame_result.error and not crop_result.error:
        return crop_result
    if crop_result.error and not full_frame_result.error:
        return full_frame_result
    if full_frame_result.similarity >= crop_result.similarity:
        return full_frame_result
    return crop_result


def draw_overlay(
    frame: Any,
    detection: FaceDetectionResult,
    liveness: LivenessSnapshot,
    anti_result: AntiSpoofingResult | None,
    recognition_result: RecognitionResult | None,
    final_message: str,
    final_ok: bool,
    mode: str,
    target_name: str,
    config: dict[str, Any],
) -> Any:
    annotated = frame.copy()
    face = detection.primary_face
    if face is not None:
        if bool(get_nested(config, "ui.show_bounding_box", True)):
            color = (0, 190, 0) if detection.face_count == 1 else (0, 0, 255)
            x1, y1, x2, y2 = face.bbox
            cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
        if bool(get_nested(config, "ui.show_landmarks", True)):
            for x, y in face.landmarks_px[::3]:
                cv2.circle(annotated, (int(x), int(y)), 1, (0, 0, 255), -1)

    draw_panel(annotated, 12, 12, 560, 282, (20, 20, 20))
    y = 38
    put(annotated, "FACE AUTH LOCAL DEMO", 26, y, (255, 255, 255), 0.72, 2)
    y += 28
    put(annotated, f"Mode: {mode} | R reset | C capture | Q/ESC quit", 26, y, (220, 220, 220), 0.52, 1)
    y += 26
    put(annotated, f"Target: {ascii_safe(target_name)}", 26, y, (220, 220, 220), 0.52, 1)
    y += 24

    checklist = build_checklist(detection, liveness, anti_result, recognition_result, mode)
    for label, passed in checklist:
        color = status_color(passed)
        status = "PASS" if passed is True else "FAIL" if passed is False else "WAIT"
        put(annotated, f"{status:4s}  {label}", 26, y, color, 0.50, 1)
        y += 21

    if face is not None:
        draw_panel(annotated, 12, 310, 560, 174, (20, 20, 20))
        put(annotated, f"Yaw/Pitch/Roll: {face.yaw:.1f} / {face.pitch:.1f} / {face.roll:.1f}", 26, 338, (255, 255, 0), 0.52, 1)
        put(annotated, f"Brightness: {face.brightness:.1f} | Face size ratio: {face.face_size_ratio:.2f}", 26, 364, (255, 255, 0), 0.52, 1)
        put(annotated, f"EAR: {face.eye_aspect_ratio:.3f} | Blink: {face.blink_score:.3f}", 26, 390, (255, 255, 0), 0.52, 1)
        put(annotated, f"Smile: {face.smile_score:.3f} | Mouth open: {face.mouth_open_score:.3f}", 26, 416, (255, 255, 0), 0.52, 1)
        put(annotated, "Message: " + "; ".join(detection.messages[:2]), 26, 442, (210, 210, 210), 0.48, 1)

    draw_panel(annotated, 600, 12, 650, 188, (20, 20, 20))
    put(annotated, "LIVENESS", 616, 40, (255, 255, 255), 0.68, 2)
    put(annotated, f"Current: {ascii_safe(liveness.current_instruction)}", 616, 68, (0, 255, 255), 0.55, 1)
    put(annotated, f"Time left: {liveness.time_left_seconds:.1f}s | Retry left: {liveness.retries_left}", 616, 94, (0, 255, 255), 0.52, 1)
    challenge_y = 120
    for index, item in enumerate(liveness.challenges[:5], start=1):
        color = status_color(item["status"] == "PASS" if item["status"] in {"PASS", "FAIL"} else None)
        if item["status"] == "FAIL":
            color = (0, 0, 255)
        put(annotated, f"{index}. {ascii_safe(item['label'])}: {item['status']} | progress {item['confidence'] * 100:.0f}%", 616, challenge_y, color, 0.45, 1)
        challenge_y += 20

    draw_panel(annotated, 600, 214, 650, 132, (20, 20, 20))
    put(annotated, "ANTI-SPOOFING", 616, 242, (255, 255, 255), 0.62, 2)
    if anti_result is None:
        put(annotated, "Waiting...", 616, 272, (180, 180, 180), 0.55, 1)
    else:
        put(annotated, f"Real: {anti_result.real_score * 100:.1f}%  Threshold: {anti_result.threshold * 100:.1f}%", 616, 272, status_color(anti_result.is_real), 0.55, 1)
        put(annotated, f"Print: {anti_result.printed_photo_score * 100:.1f}% | Screen: {anti_result.screen_replay_score * 100:.1f}% | Unknown: {anti_result.unknown_spoof_score * 100:.1f}%", 616, 298, (220, 220, 220), 0.48, 1)
        if anti_result.error:
            put(annotated, f"Error: {anti_result.error[:70]}", 616, 324, (0, 0, 255), 0.45, 1)

    draw_panel(annotated, 600, 360, 650, 132, (20, 20, 20))
    put(annotated, "RECOGNITION", 616, 388, (255, 255, 255), 0.62, 2)
    if recognition_result is None:
        put(annotated, "Waiting...", 616, 418, (180, 180, 180), 0.55, 1)
    else:
        result_kind = "Final" if mode == "DONE" else "Best live"
        put(annotated, f"{result_kind}: {ascii_safe(recognition_result.best_match_name)}", 616, 418, status_color(recognition_result.is_recognized), 0.55, 1)
        put(annotated, f"Similarity: {recognition_result.similarity_percent:.1f}% | Distance: {recognition_result.distance:.4f}", 616, 444, (220, 220, 220), 0.50, 1)
        put(
            annotated,
            f"Threshold: {recognition_result.recognition_threshold * 100:.1f}% | Match: {recognition_result.match_strategy}",
            616,
            470,
            (220, 220, 220),
            0.50,
            1,
        )

    if final_message:
        h, w = annotated.shape[:2]
        if mode == "DONE":
            banner_color = (0, 150, 0) if final_ok else (0, 0, 180)
        else:
            banner_color = (0, 120, 160)
        cv2.rectangle(annotated, (0, h - 78), (w, h), banner_color, -1)
        put(annotated, final_message, 24, h - 30, (255, 255, 255), 0.90, 2)

    return annotated


def build_checklist(
    detection: FaceDetectionResult,
    liveness: LivenessSnapshot,
    anti_result: AntiSpoofingResult | None,
    recognition_result: RecognitionResult | None,
    mode: str,
) -> list[tuple[str, bool | None]]:
    face = detection.primary_face
    checks = face.checks if face else {}
    anti_status: bool | None = anti_result.is_real if anti_result else None
    recognition_status: bool | None = recognition_result.is_recognized if recognition_result else None
    if mode != "DONE":
        anti_status = True if anti_status is True else None
        recognition_status = True if recognition_status is True else None
    return [
        ("Face detected", detection.face_count > 0),
        ("Only one face", detection.face_count == 1),
        ("Face large enough", checks.get("face_size") if face else False),
        ("Face centered", checks.get("centered") if face else False),
        ("Brightness OK", checks.get("brightness") if face else False),
        ("Pose initial OK", checks.get("pose") if face else False),
        ("Liveness", liveness.passed if not liveness.failed else False),
        ("Anti-spoofing", anti_status),
        ("Recognition", recognition_status),
    ]


def draw_panel(frame: Any, x: int, y: int, width: int, height: int, color: tuple[int, int, int]) -> None:
    overlay = frame.copy()
    cv2.rectangle(overlay, (x, y), (x + width, y + height), color, -1)
    cv2.addWeighted(overlay, 0.72, frame, 0.28, 0, frame)
    cv2.rectangle(frame, (x, y), (x + width, y + height), (80, 80, 80), 1)


def put(
    frame: Any,
    text: str,
    x: int,
    y: int,
    color: tuple[int, int, int],
    scale: float = 0.55,
    thickness: int = 1,
) -> None:
    cv2.putText(frame, ascii_safe(text), (x, y), cv2.FONT_HERSHEY_SIMPLEX, scale, color, thickness, cv2.LINE_AA)


def ascii_safe(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", str(text))
    return normalized.encode("ascii", "ignore").decode("ascii").replace("  ", " ")


def status_color(status: bool | None) -> tuple[int, int, int]:
    if status is True:
        return (0, 220, 0)
    if status is False:
        return (0, 0, 255)
    return (170, 170, 170)


def challenge_signature(snapshot: LivenessSnapshot) -> str:
    return " | ".join(
        f"{item['label']}={item['status']}:{item['attempts_used']}:{item['confidence']:.2f}"
        for item in snapshot.challenges
    )


def log_detection(logger: Any, detection: FaceDetectionResult) -> None:
    logger.info("Co phat hien mat khong: %s", detection.face_count > 0)
    logger.info("So luong khuon mat: %d", detection.face_count)
    if detection.primary_face:
        face = detection.primary_face
        logger.info("Face bbox: %s", face.bbox)
        logger.info("Brightness score: %.2f", face.brightness)
        logger.info("Yaw/Pitch/Roll: %.2f / %.2f / %.2f", face.yaw, face.pitch, face.roll)


if __name__ == "__main__":
    raise SystemExit(main())
