# Face Auth service

Day la dich vu FastAPI nhan dien khuon mat duoc Flutter app va NestJS backend
su dung. Toan bo source API, pipeline MediaPipe/InsightFace, Dockerfile, test
va thin client Android cu deu nam trong thu muc nay; deployment tich hop dung
config o `../../infra/`.

## Thanh phan

- `backend/`: REST API, session, rate limit va orchestration inference.
- `modules/`: MediaPipe face landmark/liveness va ArcFace verification.
- `models/face_landmarker.task`: model MediaPipe duoc version control de Docker
  build co the chay ngay.
- Dockerfile tu tai recognition model `w600k_r50.onnx` tu release cua
  InsightFace trong luc build image.
- `scripts/fetch_models.py`: dung khi chay Face Auth truc tiep bang Python,
  khong qua Docker.
- `tests/`: test hoi quy FastAPI/pipeline.
- `mobile_android/`: thin client Android cu, giu lai de tham khao; ung dung
  chinh hien tai la `../../apps/frontend_student/`.

## Du lieu khong dua len GitHub

Khong commit `.env`, API key, anh enroll, `database_faces/`, log, output hay
file `.onnx` tai ve. Embedding khuon mat nam trong bang `FaceIdentity` cua
PostgreSQL, khong ton tai `face_db.json` trong deployment. Docker image tu tai
model khi build; khi clone, chi can ket noi den database da co du lieu enroll.

## Cai dat model sau khi clone

Tu root cua monorepo, chay:

```powershell
python services/face_auth/scripts/fetch_models.py
```

Script tai `w600k_r50.onnx` vao `services/face_auth/models/` khi chay API
truc tiep tren may. Docker Compose khong can buoc nay vi Dockerfile tu tai
model vao image. Kiem tra va tuan thu license cua model InsightFace truoc khi
su dung. Desktop legacy co the can Passive PAD; chi khi can, tai them no bang:

```powershell
python services/face_auth/scripts/fetch_models.py --include-legacy-pad
```

## Enroll khuon mat

1. Tao `database_faces/<face_identity_key>/` va them anh co su dong y cua nguoi
   dung. Thu muc nay da bi Git bo qua.
2. Cai dependency Python trong `services/face_auth/`:

   ```powershell
   python -m venv .venv
   .\.venv\Scripts\python -m pip install -r requirements.txt
   ```

3. Tao embedding database:

   ```powershell
   $env:FACE_DATABASE_URL = "postgresql://<user>:<password>@<host>:5432/<database>"
   .\.venv\Scripts\python enroll_faces.py
   ```

   Dat `FACE_DATABASE_URL` truoc khi chay lenh. Enrollment se upsert embedding
   vao bang `FaceIdentity` trong PostgreSQL; anh goc van nam local va khong duoc
   dua vao GitHub.

`face_identity_key` phai trung voi gia tri ma backend Attendance gan cho sinh
vien. Doi voi production, ma hoa du lieu at rest, han che quyen truy cap volume
va chi enroll khi co su dong y phu hop.

## Chay bang Docker Compose

1. Copy `infra/.env.example` thanh `infra/.env` va tao key that.
2. Restore PostgreSQL database da co bang `FaceIdentity` (hoac enroll truoc khi
   khoi dong Face Auth), sau do chay stack:

   ```powershell
   docker compose --env-file infra/.env -f infra/compose.production.yaml up --build
   ```

Face Auth chi san sang sau khi Docker build xong, key va face database hop le.
Nginx public API duoi `/face-api/`; NestJS goi service qua internal network
`face-auth:8000`.

## API chinh

| Method | Endpoint | Xac thuc |
| --- | --- | --- |
| GET | `/api/v1/health` | Khong |
| GET | `/api/v1/identities` | `X-API-Key` |
| POST | `/api/v1/sessions` | `X-API-Key` |
| GET | `/api/v1/sessions/{id}` | `X-Session-Token` |
| POST | `/api/v1/sessions/{id}/frames` | `X-Session-Token` |
| DELETE | `/api/v1/sessions/{id}` | `X-Session-Token` |
| POST | `/api/v1/admin/reload-identities` | `X-Admin-Key` |

Khi khong chay production, OpenAPI tai `/docs`. Trong production, docs bi tat
va Nginx cung cap endpoint qua `/face-api/`.

Tai lieu thiet ke chi tiet nam o `ARCHITECTURE.md`; tai lieu demo cu duoc giu
o `LEGACY_DEMO_GUIDE.md`.
