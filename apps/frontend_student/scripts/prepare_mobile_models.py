#!/usr/bin/env python3
"""Install pinned face models into Android assets before building an APK."""

from __future__ import annotations

import hashlib
from pathlib import Path
import shutil
import tempfile
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[3]
DEST = ROOT / "apps/frontend_student/android/app/src/main/assets/models"
LANDMARKER = ROOT / "services/face_auth/models/face_landmarker.task"
SFACE_URL = (
    "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/"
    "models/face_recognition_sface/face_recognition_sface_2021dec.onnx"
)
MODELS = {
    "face_landmarker.task": "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff",
    "face_recognition_sface_2021dec.onnx": "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_model(name: str) -> None:
    destination = DEST / name
    expected = MODELS[name]
    if destination.is_file() and sha256(destination) == expected:
        print(f"Verified {name}")
        return

    DEST.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=DEST, prefix=f".{name}.", delete=False) as stream:
        temporary = Path(stream.name)
        try:
            if name == "face_landmarker.task":
                with LANDMARKER.open("rb") as source:
                    shutil.copyfileobj(source, stream)
            else:
                request = Request(SFACE_URL, headers={"User-Agent": "smart-attendance-build/1.0"})
                with urlopen(request, timeout=120) as source:
                    shutil.copyfileobj(source, stream)
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    if sha256(temporary) != expected:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"Checksum mismatch for {name}")
    temporary.replace(destination)
    print(f"Installed and verified {name}")


if __name__ == "__main__":
    for model_name in MODELS:
        ensure_model(model_name)
