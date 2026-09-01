from __future__ import annotations

import os
from unittest import TestCase, mock

from modules import face_recognizer
from modules.face_recognizer import InsightFaceRecognizer


class _FakeCursor:
    def __init__(self) -> None:
        self.statements: list[tuple[str, object]] = []
        self.rows = [
            (
                "student_001",
                [[0.6, 0.8]],
                [0.6, 0.8],
                1,
                "buffalo_l",
                0.6,
            )
        ]

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def execute(self, statement: str, params=None) -> None:
        self.statements.append((statement, params))

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return (123456789,)


class _FakeConnection:
    def __init__(self, cursor: _FakeCursor) -> None:
        self.cursor_instance = cursor

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def cursor(self):
        return self.cursor_instance


class _FakePsycopg:
    def __init__(self, cursor: _FakeCursor) -> None:
        self.cursor = cursor

    def connect(self, _url: str, **_kwargs):
        return _FakeConnection(self.cursor)


class PostgresFaceDatabaseTests(TestCase):
    def setUp(self) -> None:
        self.cursor = _FakeCursor()
        self.driver = _FakePsycopg(self.cursor)
        self.driver_patch = mock.patch.object(
            face_recognizer,
            "_postgres_driver",
            return_value=(self.driver, lambda value: value),
        )
        self.driver_patch.start()
        self.addCleanup(self.driver_patch.stop)

    def test_loads_active_embeddings_from_postgres(self) -> None:
        database = face_recognizer.load_face_database_from_postgres("postgresql://example")

        self.assertEqual(["student_001"], sorted(database["persons"]))
        self.assertEqual([[0.6, 0.8]], database["persons"]["student_001"]["embeddings"])
        self.assertEqual(123456789, face_recognizer.face_database_revision_from_postgres("postgresql://example"))
        self.assertIn('FROM "FaceIdentity"', self.cursor.statements[0][0])

    def test_enrollment_upserts_postgres_identity(self) -> None:
        payload = {
            "version": 3,
            "model_name": "buffalo_l",
            "threshold": 0.6,
            "persons": {
                "student_001": {
                    "embeddings": [[0.6, 0.8]],
                    "mean_embedding": [0.6, 0.8],
                    "valid_image_count": 1,
                }
            },
        }

        face_recognizer.save_face_database_to_postgres("postgresql://example", payload)

        insert_statement, params = self.cursor.statements[0]
        self.assertIn('INSERT INTO "FaceIdentity"', insert_statement)
        self.assertEqual("student_001", params[0])

    def test_recognizer_prefers_postgres_when_configured(self) -> None:
        with mock.patch.dict(os.environ, {"FACE_DATABASE_URL": "postgresql://example"}):
            recognizer = InsightFaceRecognizer({})

        self.assertTrue(recognizer.uses_postgres)
