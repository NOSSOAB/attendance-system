"""Build an Android-compatible SFace reference vector from 2-5 photos.

This is an offline enrollment tool. It never uploads the photos and emits only
the normalized 128-number mean vector consumed by the NestJS import script.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
import onnxruntime as ort


LANDMARK_INDEXES = (33, 263, 1, 61, 291)
TARGET = np.array(
    [[38.2946, 51.6963], [73.5318, 51.5014], [56.0252, 71.7366],
     [41.5493, 92.3655], [70.7299, 92.2041]],
    dtype=np.float32,
)


def similarity_transform(source: np.ndarray) -> np.ndarray:
    source_mean = source.mean(axis=0)
    target_mean = TARGET.mean(axis=0)
    centered_source = source - source_mean
    centered_target = TARGET - target_mean
    real = float(np.sum(centered_source * centered_target))
    imaginary = float(
        np.sum(
            centered_source[:, 0] * centered_target[:, 1]
            - centered_source[:, 1] * centered_target[:, 0]
        )
    )
    energy = float(np.sum(centered_source * centered_source))
    if energy < 1e-6:
        raise ValueError("Face landmarks are degenerate")
    a = real / energy
    b = imaginary / energy
    sx, sy = source_mean
    tx, ty = target_mean
    return np.array(
        [[a, -b, tx - a * sx + b * sy], [b, a, ty - b * sx - a * sy]],
        dtype=np.float32,
    )


def build_embedding(
    image_path: Path,
    landmarker: mp.tasks.vision.FaceLandmarker,
    recognizer: ort.InferenceSession,
) -> np.ndarray:
    bgr = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
    if bgr is None:
        raise ValueError(f"Cannot read image: {image_path}")
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    result = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
    if len(result.face_landmarks) != 1:
        raise ValueError(f"Expected exactly one face in {image_path.name}")
    height, width = rgb.shape[:2]
    landmarks = result.face_landmarks[0]
    source = np.array(
        [[landmarks[index].x * width, landmarks[index].y * height]
         for index in LANDMARK_INDEXES],
        dtype=np.float32,
    )
    aligned = cv2.warpAffine(
        rgb,
        similarity_transform(source),
        (112, 112),
        flags=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
    )
    tensor = np.transpose(aligned.astype(np.float32), (2, 0, 1))[None, ...]
    output = recognizer.run(None, {recognizer.get_inputs()[0].name: tensor})[0]
    vector = np.asarray(output, dtype=np.float32).reshape(-1)
    norm = float(np.linalg.norm(vector))
    if vector.size != 128 or norm < 1e-6:
        raise ValueError(f"Invalid SFace output for {image_path.name}")
    return vector / norm


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--identity", action="append", required=True,
                        help="Scoped key such as HUCE:person_A; repeat if needed")
    parser.add_argument("--images", required=True, type=Path)
    parser.add_argument("--landmarker", required=True, type=Path)
    parser.add_argument("--recognizer", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--threshold", type=float, default=0.45)
    parser.add_argument("--probe", action="append", type=Path,
                        help="Optional photo used only to report similarity")
    args = parser.parse_args()

    photos = sorted(
        path for path in args.images.iterdir()
        if path.suffix.lower() in {".jpg", ".jpeg", ".png"}
    )
    if not 2 <= len(photos) <= 5:
        raise SystemExit("Each identity needs 2-5 reference photos")
    if len({hashlib.sha256(path.read_bytes()).digest() for path in photos}) != len(photos):
        raise SystemExit("Reference photos must be distinct images")
    if not 0.45 <= args.threshold <= 0.9:
        raise SystemExit("Face threshold must be between 0.45 and 0.9")

    options = mp.tasks.vision.FaceLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(args.landmarker)),
        running_mode=mp.tasks.vision.RunningMode.IMAGE,
        num_faces=2,
    )
    recognizer = ort.InferenceSession(
        str(args.recognizer), providers=["CPUExecutionProvider"]
    )
    probe_scores: list[tuple[str, float]] = []
    with mp.tasks.vision.FaceLandmarker.create_from_options(options) as landmarker:
        samples = [build_embedding(path, landmarker, recognizer) for path in photos]
        mean = np.mean(np.stack(samples), axis=0)
        mean /= np.linalg.norm(mean)
        for probe in args.probe or []:
            probe_scores.append(
                (probe.name, float(np.dot(mean, build_embedding(probe, landmarker, recognizer))))
            )

    similarities = [
        float(np.dot(samples[left], samples[right]))
        for left in range(len(samples))
        for right in range(left + 1, len(samples))
    ]
    if min(similarities) < args.threshold:
        raise SystemExit(
            "Reference photos disagree: minimum pair similarity "
            f"{min(similarities):.4f} is below threshold {args.threshold:.4f}. "
            "Use 2-5 clear photos of the same person."
        )
    payload = {
        "modelId": "opencv_sface_2021dec_v1",
        "sourceImageCount": len(samples),
        "minimumPairSimilarity": min(similarities),
        "identities": [
            {
                "identityKey": identity,
                "threshold": args.threshold,
                "meanEmbedding": [float(value) for value in mean],
            }
            for identity in args.identity
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    print(
        f"Wrote {len(args.identity)} identities from {len(samples)} photos; "
        f"minimum pair similarity={min(similarities):.4f}"
    )
    for name, score in probe_scores:
        print(f"Probe {name}: similarity={score:.4f}")


if __name__ == "__main__":
    main()
