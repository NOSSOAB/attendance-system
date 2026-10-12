from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile
from typing import Any

import cv2
import numpy as np

from .utils import get_nested, resolve_demo_path


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


class FaceDatabaseMissingError(RuntimeError):
    pass


class FaceEmbeddingError(RuntimeError):
    pass


@dataclass
class RecognitionResult:
    best_match_name: str
    similarity_percent: float
    similarity: float
    distance: float
    recognition_threshold: float
    is_recognized: bool
    candidate_image: str = ""
    match_strategy: str = "individual"
    face_count: int = 0
    error: str = ""
    sample_count: int = 1
    passed_count: int = 0
    median_similarity: float = 0.0
    similarities: list[float] | None = None


class InsightFaceRecognizer:
    """InsightFace adapter for enrollment and identity matching."""

    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        self.threshold = float(get_nested(config, "thresholds.recognition_threshold", 0.60))
        self.model_name = str(get_nested(config, "recognition.model_name", "buffalo_l"))
        self.face_db_path = self._resolve_face_db_path()
        self.database_url = os.environ.get("FACE_DATABASE_URL", "").strip()
        self.database_path = resolve_demo_path(config, "database_path", "database_faces")
        self._app = None
        self._recognition_model = None
        self._providers: list[str] = []
        self._database: dict[str, Any] | None = None

    def _resolve_face_db_path(self) -> Path:
        value = get_nested(self.config, "paths.face_db_path", "face_db.json")
        path = Path(value)
        if not path.is_absolute():
            path = Path(__file__).resolve().parents[1] / path
        return path

    @property
    def uses_postgres(self) -> bool:
        return bool(self.database_url)

    def get_embedding(self, image_bgr: np.ndarray) -> tuple[np.ndarray, int]:
        app = self._ensure_app()
        faces = app.get(image_bgr)
        if not faces:
            raise FaceEmbeddingError("Không tìm thấy khuôn mặt để trích xuất embedding.")
        best_face = max(faces, key=lambda face: _face_area(getattr(face, "bbox", None)))
        embedding = np.asarray(best_face.embedding, dtype=np.float32)
        norm = np.linalg.norm(embedding)
        if norm <= 0:
            raise FaceEmbeddingError("Embedding InsightFace không hợp lệ.")
        return embedding / norm, len(faces)

    def enroll_database(
        self,
        database_path: Path | None = None,
        face_db_path: Path | None = None,
        logger: Any | None = None,
    ) -> dict[str, Any]:
        database_path = database_path or self.database_path
        face_db_path = face_db_path or self.face_db_path
        database_path.mkdir(parents=True, exist_ok=True)
        people_dirs = [path for path in sorted(database_path.iterdir()) if path.is_dir()]
        persons: dict[str, Any] = {}
        skipped: list[str] = []

        for person_dir in people_dirs:
            image_paths = [
                path
                for path in sorted(person_dir.iterdir())
                if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
            ]
            if logger:
                logger.info("Đang xử lý %s: %d ảnh", person_dir.name, len(image_paths))
            embeddings = []
            valid_images = []
            for image_path in image_paths:
                image = cv2.imread(str(image_path))
                if image is None:
                    message = f"{person_dir.name}/{image_path.name}: không đọc được ảnh"
                    skipped.append(message)
                    if logger:
                        logger.warning(message)
                    continue
                try:
                    embedding, face_count = self.get_embedding(image)
                except Exception as exc:
                    message = f"{person_dir.name}/{image_path.name}: {exc}"
                    skipped.append(message)
                    if logger:
                        logger.warning(message)
                    continue
                embeddings.append(embedding)
                valid_images.append({"file": str(image_path), "face_count": face_count})
                if logger:
                    logger.info("  OK %s | faces=%d", image_path.name, face_count)

            if embeddings:
                stacked = np.vstack(embeddings).astype(np.float32)
                mean_embedding = stacked.mean(axis=0)
                mean_embedding = mean_embedding / max(np.linalg.norm(mean_embedding), 1e-6)
                persons[person_dir.name] = {
                    "embeddings": stacked,
                    "mean_embedding": mean_embedding.astype(np.float32),
                    "images": valid_images,
                    "valid_image_count": len(valid_images),
                }
            elif logger:
                logger.warning("Không có ảnh hợp lệ cho %s", person_dir.name)

        payload = {
            "version": 2,
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "model_name": self.model_name,
            "threshold": self.threshold,
            "persons": persons,
            "skipped": skipped,
        }
        if self.uses_postgres:
            save_face_database_to_postgres(self.database_url, payload)
        else:
            save_face_database(face_db_path, payload)
        self._database = payload
        return payload

    def load_database(self, face_db_path: Path | None = None) -> dict[str, Any]:
        if self.uses_postgres:
            database = load_face_database_from_postgres(self.database_url)
            self._database = database
            return database

        face_db_path = face_db_path or self.face_db_path
        if not face_db_path.exists():
            raise FaceDatabaseMissingError(
                f"Không tìm thấy face database: {face_db_path}. Hãy chạy: python enroll_faces.py"
            )
        database = load_face_database(face_db_path)
        if not database.get("persons"):
            raise FaceDatabaseMissingError(
                f"Face database rỗng: {face_db_path}. Hãy thêm ảnh vào database_faces/ và chạy enroll_faces.py"
            )
        self._database = database
        return database

    def list_people(self, force_reload: bool = False) -> list[str]:
        database = self.load_database() if force_reload else self._database or self.load_database()
        return sorted(str(name) for name in database.get("persons", {}).keys())

    def database_revision(self) -> int:
        if self.uses_postgres:
            return face_database_revision_from_postgres(self.database_url)
        try:
            return self.face_db_path.stat().st_mtime_ns
        except OSError:
            return -1

    def recognize(
        self,
        image_bgr: np.ndarray,
        threshold: float | None = None,
        target_name: str | None = None,
    ) -> RecognitionResult:
        threshold = self.threshold if threshold is None else threshold
        try:
            embedding, face_count = self.get_embedding(image_bgr)
            return self._match_embedding(embedding, face_count, threshold, target_name)
        except Exception as exc:
            return self._error_result(threshold, exc)

    def recognize_with_keypoints(
        self,
        image_bgr: np.ndarray,
        keypoints: tuple[tuple[float, float], ...],
        threshold: float | None = None,
        target_name: str | None = None,
    ) -> RecognitionResult:
        """Recognize a MediaPipe-aligned face without a second face detection pass."""
        threshold = self.threshold if threshold is None else threshold
        try:
            recognition_model = self._ensure_recognition_model()
            from insightface.utils import face_align

            landmarks = np.asarray(keypoints, dtype=np.float32)
            if landmarks.shape != (5, 2):
                raise FaceEmbeddingError(f"Expected five alignment points, found {landmarks.shape}")
            aligned = face_align.norm_crop(
                image_bgr,
                landmark=landmarks,
                image_size=recognition_model.input_size[0],
            )
            embedding = np.asarray(recognition_model.get_feat(aligned), dtype=np.float32).reshape(-1)
            norm = np.linalg.norm(embedding)
            if norm <= 0:
                raise FaceEmbeddingError("Aligned InsightFace embedding is invalid")
            return self._match_embedding(embedding / norm, 1, threshold, target_name)
        except Exception as exc:
            return self._error_result(threshold, exc)

    def recognize_many_with_keypoints(
        self,
        images_bgr: list[np.ndarray],
        keypoints_list: list[tuple[tuple[float, float], ...]],
        threshold: float | None = None,
        target_name: str | None = None,
    ) -> list[RecognitionResult]:
        """Align several frames and extract all embeddings in one ONNX batch."""
        threshold = self.threshold if threshold is None else threshold
        if len(images_bgr) != len(keypoints_list):
            error = FaceEmbeddingError("Image and keypoint batch sizes do not match")
            return [self._error_result(threshold, error) for _ in images_bgr]
        if not images_bgr:
            return []
        try:
            recognition_model = self._ensure_recognition_model()
            from insightface.utils import face_align

            aligned_faces: list[np.ndarray] = []
            for image_bgr, keypoints in zip(images_bgr, keypoints_list):
                landmarks = np.asarray(keypoints, dtype=np.float32)
                if landmarks.shape != (5, 2):
                    raise FaceEmbeddingError(
                        f"Expected five alignment points, found {landmarks.shape}"
                    )
                aligned_faces.append(
                    face_align.norm_crop(
                        image_bgr,
                        landmark=landmarks,
                        image_size=recognition_model.input_size[0],
                    )
                )

            embeddings = np.asarray(
                recognition_model.get_feat(aligned_faces),
                dtype=np.float32,
            )
            if embeddings.ndim == 1:
                embeddings = embeddings.reshape(1, -1)
            if embeddings.shape[0] != len(aligned_faces):
                raise FaceEmbeddingError(
                    f"Expected {len(aligned_faces)} embeddings, found {embeddings.shape[0]}"
                )

            results: list[RecognitionResult] = []
            for embedding in embeddings:
                norm = np.linalg.norm(embedding)
                if norm <= 0:
                    raise FaceEmbeddingError("Aligned InsightFace embedding is invalid")
                results.append(
                    self._match_embedding(embedding / norm, 1, threshold, target_name)
                )
            return results
        except Exception as exc:
            return [self._error_result(threshold, exc) for _ in images_bgr]

    def _match_embedding(
        self,
        embedding: np.ndarray,
        face_count: int,
        threshold: float,
        target_name: str | None,
    ) -> RecognitionResult:
        database = self._database or self.load_database()
        persons = database.get("persons", {})
        if target_name:
            if target_name not in persons:
                raise FaceDatabaseMissingError(
                    f"Khong tim thay nguoi '{target_name}' trong face database. Hay chay lai enroll_faces.py"
                )
            persons = {target_name: persons[target_name]}

        best_name = "UNKNOWN"
        best_similarity = -1.0
        best_image = ""
        best_strategy = "individual"
        for person_name, person in persons.items():
            embeddings = np.asarray(person.get("embeddings", []), dtype=np.float32)
            images = person.get("images", [])
            for index, reference in enumerate(embeddings):
                similarity = cosine_similarity(embedding, reference)
                if similarity > best_similarity:
                    best_similarity = similarity
                    best_name = person_name
                    best_image = images[index]["file"] if index < len(images) else ""
                    best_strategy = "individual"

            mean_embedding = np.asarray(person.get("mean_embedding", []), dtype=np.float32)
            if mean_embedding.size:
                mean_similarity = cosine_similarity(embedding, mean_embedding)
                if mean_similarity > best_similarity:
                    best_similarity = mean_similarity
                    best_name = person_name
                    best_image = ""
                    best_strategy = "centroid"

        if best_similarity < -0.5:
            if target_name:
                raise FaceDatabaseMissingError(f"Nguoi '{target_name}' khong co embedding hop le.")
            raise FaceDatabaseMissingError("Face database không có embedding hợp lệ.")

        is_recognized = best_similarity >= threshold
        return RecognitionResult(
            best_match_name=best_name if is_recognized else f"{best_name} (dưới ngưỡng)",
            similarity_percent=max(0.0, min(100.0, best_similarity * 100.0)),
            similarity=best_similarity,
            distance=1.0 - best_similarity,
            recognition_threshold=threshold,
            is_recognized=is_recognized,
            candidate_image=best_image,
            match_strategy=best_strategy,
            face_count=face_count,
            sample_count=1,
            passed_count=1 if is_recognized else 0,
            median_similarity=best_similarity,
            similarities=[best_similarity],
        )

    @staticmethod
    def _error_result(threshold: float, exc: Exception) -> RecognitionResult:
        return RecognitionResult(
            best_match_name="UNKNOWN",
            similarity_percent=0.0,
            similarity=0.0,
            distance=1.0,
            recognition_threshold=threshold,
            is_recognized=False,
            error=str(exc),
            sample_count=0,
            passed_count=0,
            similarities=[],
        )

    def _ensure_app(self):
        if self._app is not None:
            return self._app

        try:
            import onnxruntime
            from insightface.app import FaceAnalysis
        except Exception as exc:  # pragma: no cover - depends on local env
            raise RuntimeError(
                "Không import được InsightFace/onnxruntime. "
                "Hãy chạy: python -m pip install -r requirements.txt. "
                f"Chi tiết lỗi: {exc}"
            ) from exc

        providers, ctx_id = _provider_config(onnxruntime)

        app = FaceAnalysis(
            name=self.model_name,
            allowed_modules=["detection", "recognition"],
            providers=providers,
        )
        app.prepare(ctx_id=ctx_id, det_size=(640, 640))
        self._app = app
        self._recognition_model = app.models.get("recognition")
        self._providers = providers
        return app

    def _ensure_recognition_model(self):
        if self._recognition_model is not None:
            return self._recognition_model

        try:
            import onnxruntime
            from insightface.model_zoo.arcface_onnx import ArcFaceONNX
        except Exception as exc:  # pragma: no cover - depends on local env
            raise RuntimeError("Không import được InsightFace recognition runtime") from exc

        providers, ctx_id = _provider_config(onnxruntime)
        model_path = self._resolve_recognition_model_path()
        options = onnxruntime.SessionOptions()
        options.intra_op_num_threads = max(
            1, int(get_nested(self.config, "recognition.intra_op_threads", 2))
        )
        options.inter_op_num_threads = 1
        options.graph_optimization_level = onnxruntime.GraphOptimizationLevel.ORT_ENABLE_ALL
        session = onnxruntime.InferenceSession(
            str(model_path),
            sess_options=options,
            providers=providers,
        )
        model = ArcFaceONNX(model_file=str(model_path), session=session)
        model.prepare(ctx_id=ctx_id)
        self._recognition_model = model
        self._providers = providers
        return model

    def _resolve_recognition_model_path(self) -> Path:
        configured = str(get_nested(self.config, "recognition.model_path", "")).strip()
        if configured:
            path = Path(configured)
            if not path.is_absolute():
                path = Path(__file__).resolve().parents[1] / path
            if path.is_file():
                return path
            raise FileNotFoundError(f"Không tìm thấy recognition model: {path}")

        bundled = resolve_demo_path(self.config, "models_path", "models") / "w600k_r50.onnx"
        if bundled.is_file():
            return bundled
        model_dir = Path.home() / ".insightface" / "models" / self.model_name
        preferred = model_dir / "w600k_r50.onnx"
        if preferred.is_file():
            return preferred
        candidates = sorted(model_dir.glob("*.onnx"))
        likely = [
            path
            for path in candidates
            if any(token in path.stem.lower() for token in ("w600k", "arcface", "r50", "r100"))
        ]
        if likely:
            return likely[0]
        raise FileNotFoundError(
            f"Không tìm thấy recognition ONNX trong {model_dir}. "
            "Hãy đặt recognition.model_path trong config.yaml."
        )


def cosine_similarity(left: np.ndarray, right: np.ndarray) -> float:
    left = np.asarray(left, dtype=np.float32)
    right = np.asarray(right, dtype=np.float32)
    return float(np.dot(left, right) / max(np.linalg.norm(left) * np.linalg.norm(right), 1e-6))


def save_face_database(path: Path, payload: dict[str, Any]) -> None:
    """Write a non-executable JSON database atomically with an integrity digest."""
    path = Path(path)
    if path.suffix.lower() != ".json":
        raise FaceDatabaseMissingError("Face database path must use the .json format")
    safe_payload = _to_json_value(payload)
    _validate_face_database(safe_payload)
    canonical = json.dumps(
        safe_payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    envelope = {
        "format": "smartattendance-face-db",
        "sha256": hashlib.sha256(canonical).hexdigest(),
        "payload": safe_payload,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_name = ""
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as file:
            temporary_name = file.name
            json.dump(envelope, file, ensure_ascii=False, indent=2, allow_nan=False)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary_name, path)
    finally:
        if temporary_name:
            try:
                Path(temporary_name).unlink(missing_ok=True)
            except OSError:
                pass


def load_face_database(path: Path) -> dict[str, Any]:
    """Load and validate the safe JSON database; pickle is intentionally unsupported."""
    path = Path(path)
    if path.suffix.lower() != ".json":
        raise FaceDatabaseMissingError(
            "Legacy pickle face databases are disabled; run enroll_faces.py to create face_db.json"
        )
    try:
        with path.open("r", encoding="utf-8") as file:
            envelope = json.load(file)
    except (OSError, json.JSONDecodeError) as exc:
        raise FaceDatabaseMissingError(f"Không đọc được face database an toàn: {exc}") from exc
    if not isinstance(envelope, dict) or envelope.get("format") != "smartattendance-face-db":
        raise FaceDatabaseMissingError("Face database format is invalid")
    payload = envelope.get("payload")
    if not isinstance(payload, dict):
        raise FaceDatabaseMissingError("Face database payload is invalid")
    canonical = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    actual_digest = hashlib.sha256(canonical).hexdigest()
    expected_digest = str(envelope.get("sha256", ""))
    if not expected_digest or not hmac_compare(expected_digest, actual_digest):
        raise FaceDatabaseMissingError("Face database checksum mismatch")
    _validate_face_database(payload)
    return payload


def hmac_compare(left: str, right: str) -> bool:
    import hmac

    return hmac.compare_digest(left, right)


def load_face_database_from_postgres(database_url: str) -> dict[str, Any]:
    """Read active face embeddings from PostgreSQL without writing biometric files."""
    psycopg, _jsonb = _postgres_driver()
    try:
        with psycopg.connect(database_url, connect_timeout=5) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    '''
                    SELECT "identityKey", "embeddings", "meanEmbedding", "imageCount",
                           "modelName", "threshold"
                    FROM "FaceIdentity"
                    WHERE "isActive" = true
                    ORDER BY "identityKey"
                    '''
                )
                rows = cursor.fetchall()
    except Exception as exc:
        raise FaceDatabaseMissingError(
            "Không thể đọc FaceIdentity từ PostgreSQL. "
            "Hãy kiểm tra FACE_DATABASE_URL và migration."
        ) from exc

    persons: dict[str, Any] = {}
    model_name = "buffalo_l"
    threshold = 0.60
    for identity_key, embeddings, mean_embedding, image_count, row_model_name, row_threshold in rows:
        persons[str(identity_key)] = {
            "embeddings": _decode_jsonb(embeddings),
            "mean_embedding": _decode_jsonb(mean_embedding),
            # Enrollment image paths never leave the protected enrollment machine.
            "images": [],
            "valid_image_count": int(image_count or 0),
        }
        model_name = str(row_model_name or model_name)
        threshold = float(row_threshold if row_threshold is not None else threshold)

    payload = {
        "version": 3,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "model_name": model_name,
        "threshold": threshold,
        "persons": persons,
        "skipped": [],
    }
    if not persons:
        raise FaceDatabaseMissingError(
            "PostgreSQL chưa có FaceIdentity hoạt động. Hãy enroll khuôn mặt vào database."
        )
    _validate_face_database(payload)
    return payload


def save_face_database_to_postgres(database_url: str, payload: dict[str, Any]) -> None:
    """Upsert enrollment embeddings into the application's PostgreSQL database."""
    safe_payload = _to_json_value(payload)
    _validate_face_database(safe_payload)
    psycopg, jsonb = _postgres_driver()
    try:
        with psycopg.connect(database_url, connect_timeout=5) as connection:
            with connection.cursor() as cursor:
                for identity_key, person in safe_payload["persons"].items():
                    embeddings = person["embeddings"]
                    mean_embedding = person["mean_embedding"]
                    image_count = int(person.get("valid_image_count", len(embeddings)))
                    cursor.execute(
                        '''
                        INSERT INTO "FaceIdentity" (
                            "identityKey", "embeddings", "meanEmbedding", "imageCount",
                            "modelName", "threshold", "isActive", "createdAt", "updatedAt"
                        ) VALUES (%s, %s, %s, %s, %s, %s, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                        ON CONFLICT ("identityKey") DO UPDATE SET
                            "embeddings" = EXCLUDED."embeddings",
                            "meanEmbedding" = EXCLUDED."meanEmbedding",
                            "imageCount" = EXCLUDED."imageCount",
                            "modelName" = EXCLUDED."modelName",
                            "threshold" = EXCLUDED."threshold",
                            "isActive" = true,
                            "updatedAt" = CURRENT_TIMESTAMP
                        ''',
                        (
                            identity_key,
                            jsonb(embeddings),
                            jsonb(mean_embedding),
                            image_count,
                            str(safe_payload.get("model_name", "buffalo_l")),
                            float(safe_payload.get("threshold", 0.60)),
                        ),
                    )
    except Exception as exc:
        raise FaceDatabaseMissingError(
            "Không thể lưu FaceIdentity vào PostgreSQL. "
            "Hãy kiểm tra FACE_DATABASE_URL và migration."
        ) from exc


def face_database_revision_from_postgres(database_url: str) -> int:
    """Return a cheap revision marker so API workers reload only when data changes."""
    psycopg, _jsonb = _postgres_driver()
    try:
        with psycopg.connect(database_url, connect_timeout=5) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    '''
                    SELECT COALESCE(
                        (EXTRACT(EPOCH FROM MAX("updatedAt")) * 1000000000)::BIGINT,
                        0
                    )
                    FROM "FaceIdentity"
                    WHERE "isActive" = true
                    '''
                )
                row = cursor.fetchone()
    except Exception as exc:
        raise FaceDatabaseMissingError(
            "Không thể kiểm tra phiên bản FaceIdentity trong PostgreSQL."
        ) from exc
    return int(row[0] or 0) if row else 0


def _postgres_driver():
    try:
        import psycopg
        from psycopg.types.json import Jsonb
    except Exception as exc:  # pragma: no cover - depends on deployment packages
        raise FaceDatabaseMissingError(
            "Thiếu PostgreSQL driver. Hãy cài requirements của Face Auth."
        ) from exc
    return psycopg, Jsonb


def _decode_jsonb(value: Any) -> Any:
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError as exc:
            raise FaceDatabaseMissingError("FaceIdentity JSON không hợp lệ.") from exc
    return value


def _to_json_value(value: Any) -> Any:
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {str(key): _to_json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_to_json_value(item) for item in value]
    return value


def _validate_face_database(payload: dict[str, Any]) -> None:
    persons = payload.get("persons")
    if not isinstance(persons, dict) or not persons:
        raise FaceDatabaseMissingError("Face database không có người hợp lệ")
    for person_name, person in persons.items():
        if not isinstance(person_name, str) or not person_name or not isinstance(person, dict):
            raise FaceDatabaseMissingError("Face database contains an invalid person record")
        embeddings = np.asarray(person.get("embeddings", []), dtype=np.float32)
        mean_embedding = np.asarray(person.get("mean_embedding", []), dtype=np.float32)
        if embeddings.ndim != 2 or embeddings.shape[0] < 1 or embeddings.shape[1] < 2:
            raise FaceDatabaseMissingError(f"Person '{person_name}' has invalid embeddings")
        if mean_embedding.ndim != 1 or mean_embedding.shape[0] != embeddings.shape[1]:
            raise FaceDatabaseMissingError(f"Person '{person_name}' has an invalid centroid")
        if not np.isfinite(embeddings).all() or not np.isfinite(mean_embedding).all():
            raise FaceDatabaseMissingError(f"Person '{person_name}' has non-finite embeddings")


def _face_area(bbox: Any) -> float:
    if bbox is None or len(bbox) < 4:
        return 0.0
    return float(max(0.0, bbox[2] - bbox[0]) * max(0.0, bbox[3] - bbox[1]))


def _provider_config(onnxruntime: Any) -> tuple[list[str], int]:
    available = onnxruntime.get_available_providers()
    if "CUDAExecutionProvider" in available:
        return ["CUDAExecutionProvider", "CPUExecutionProvider"], 0
    return ["CPUExecutionProvider"], -1
