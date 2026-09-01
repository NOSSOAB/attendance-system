from __future__ import annotations

import os
from pathlib import Path

from modules.face_recognizer import InsightFaceRecognizer
from modules.utils import load_config, resolve_demo_path, setup_logging


def main() -> int:
    config = load_config()
    logger = setup_logging(config, "face_auth_enroll")
    database_path = resolve_demo_path(config, "database_path", "database_faces")
    face_db_value = Path(config.get("paths", {}).get("face_db_path", "face_db.json"))
    face_db_path = face_db_value if face_db_value.is_absolute() else Path(__file__).resolve().parent / face_db_value

    logger.info("Bắt đầu enroll khuôn mặt")
    logger.info("Database ảnh: %s", database_path)
    if os.environ.get("FACE_DATABASE_URL", "").strip():
        logger.info("Embedding sẽ lưu vào PostgreSQL FaceIdentity")
    else:
        logger.info("File embedding legacy sẽ lưu: %s", face_db_path)

    recognizer = InsightFaceRecognizer(config)
    payload = recognizer.enroll_database(database_path=database_path, face_db_path=face_db_path, logger=logger)
    person_count = len(payload.get("persons", {}))
    image_count = sum(person.get("valid_image_count", 0) for person in payload.get("persons", {}).values())
    skipped = payload.get("skipped", [])

    if os.environ.get("FACE_DATABASE_URL", "").strip():
        logger.info("Đã lưu embedding vào PostgreSQL FaceIdentity")
    else:
        logger.info("Đã lưu database ở: %s", face_db_path)
    logger.info("Tổng số người hợp lệ: %d", person_count)
    logger.info("Tổng số ảnh hợp lệ: %d", image_count)
    logger.info("Tổng số ảnh lỗi/bỏ qua: %d", len(skipped))

    if person_count == 0:
        logger.warning(
            "Chưa enroll được người nào. Hãy đặt ảnh vào database_faces/<ten_nguoi>/ rồi chạy lại python enroll_faces.py"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
