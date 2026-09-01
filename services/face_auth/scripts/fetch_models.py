#!/usr/bin/env python3
"""Download externally distributed model assets without committing them to Git."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import sys
import tempfile
from urllib.request import Request, urlopen
import zipfile


BUFFALO_L_ARCHIVE_URL = (
    "https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip"
)
ARC_FACE_FILENAME = "w600k_r50.onnx"
ANTI_SPOOF_URL = (
    "https://storage.openvinotoolkit.org/repositories/open_model_zoo/public/"
    "2022.1/anti-spoof-mn3/anti-spoof-mn3.onnx"
)
ANTI_SPOOF_SHA384 = (
    "6de4534964b723397b3e8c995cadcf43bc007cc2f9930b95ae25f76adccece"
    "5d1d4d058d0b15117b9e4a9f758424f92a"
)
USER_AGENT = "smart-attendance-face-model-bootstrap/1.0"


def download(url: str, destination: Path) -> None:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=120) as response, destination.open("wb") as file:
        shutil.copyfileobj(response, file, length=1024 * 1024)


def atomic_copy(source, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary_name = ""
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=destination.parent, prefix=f".{destination.name}.", delete=False
        ) as file:
            temporary_name = file.name
            shutil.copyfileobj(source, file, length=1024 * 1024)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary_name, destination)
        temporary_name = ""
    finally:
        if temporary_name:
            Path(temporary_name).unlink(missing_ok=True)


def sha384(path: Path) -> str:
    digest = hashlib.sha384()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_arcface(models_dir: Path, force: bool) -> None:
    destination = models_dir / ARC_FACE_FILENAME
    if destination.exists() and not force:
        print(f"Already present: {destination}")
        return

    with tempfile.TemporaryDirectory(prefix="smart-attendance-face-model-") as directory:
        archive = Path(directory) / "buffalo_l.zip"
        print("Downloading InsightFace buffalo_l model package...")
        download(BUFFALO_L_ARCHIVE_URL, archive)
        with zipfile.ZipFile(archive) as package:
            member = next(
                (
                    item
                    for item in package.infolist()
                    if item.filename.replace("\\", "/").endswith(f"/{ARC_FACE_FILENAME}")
                    or item.filename == ARC_FACE_FILENAME
                ),
                None,
            )
            if member is None or member.is_dir():
                raise RuntimeError(f"The downloaded package does not contain {ARC_FACE_FILENAME}.")
            with package.open(member) as source:
                atomic_copy(source, destination)
    print(f"Installed ArcFace model: {destination}")


def ensure_anti_spoof(models_dir: Path, force: bool) -> None:
    destination = models_dir / "anti-spoof-mn3.onnx"
    if destination.exists() and not force:
        actual = sha384(destination)
        if actual != ANTI_SPOOF_SHA384:
            raise RuntimeError(f"Checksum mismatch for existing {destination}; rerun with --force.")
        print(f"Already present and verified: {destination}")
        return

    with tempfile.TemporaryDirectory(prefix="smart-attendance-pad-model-") as directory:
        downloaded = Path(directory) / destination.name
        print("Downloading optional Open Model Zoo anti-spoof model...")
        download(ANTI_SPOOF_URL, downloaded)
        actual = sha384(downloaded)
        if actual != ANTI_SPOOF_SHA384:
            raise RuntimeError("Checksum mismatch for the downloaded anti-spoof model.")
        with downloaded.open("rb") as source:
            atomic_copy(source, destination)
    print(f"Installed optional anti-spoof model: {destination}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch model assets required by the Face Auth service."
    )
    parser.add_argument(
        "--models-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "models",
        help="Destination directory for model files (default: service models directory).",
    )
    parser.add_argument(
        "--include-legacy-pad",
        action="store_true",
        help="Also fetch the optional anti-spoof model used only by the legacy desktop UI.",
    )
    parser.add_argument("--force", action="store_true", help="Replace existing model files.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    models_dir = args.models_dir.resolve()
    models_dir.mkdir(parents=True, exist_ok=True)
    ensure_arcface(models_dir, args.force)
    if args.include_legacy_pad:
        ensure_anti_spoof(models_dir, args.force)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Model setup failed: {error}", file=sys.stderr)
        raise SystemExit(1)
