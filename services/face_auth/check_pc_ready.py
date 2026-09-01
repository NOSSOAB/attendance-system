from __future__ import annotations

import os
from pathlib import Path

from modules.face_recognizer import load_face_database, load_face_database_from_postgres


def main() -> int:
    imports = [
        "cv2",
        "mediapipe",
        "onnxruntime",
        "fastapi",
        "uvicorn",
        "numpy",
    ]
    for module_name in imports:
        module = __import__(module_name)
        version = getattr(module, "__version__", "ok")
        print(f"{module_name}: {version}")

    database_url = os.environ.get("FACE_DATABASE_URL", "").strip()
    if database_url:
        database = load_face_database_from_postgres(database_url)
    else:
        face_db = Path("face_db.json")
        if not face_db.exists():
            raise FileNotFoundError(
                "Missing FACE_DATABASE_URL. Legacy mode instead requires face_db.json."
            )
        database = load_face_database(face_db)
    people = sorted(database.get("persons", {}).keys())
    if not people:
        raise RuntimeError("Face database has no people. Add images and run python enroll_faces.py")
    print("people:", ", ".join(people))

    print("PC setup OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
