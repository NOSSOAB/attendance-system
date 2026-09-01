# Deploy Smart Attendance on EC2

## Required layout

Face Auth source is part of this monorepo, so clone only this repository:

```text
/home/ubuntu/smart-attendance/
└── attendance-system/
    └── services/face_auth/

```

PostgreSQL data is persisted in the Docker volume
`smart-attendance_postgres_data`. Face embeddings are stored in the
`FaceIdentity` PostgreSQL table; the Dockerfile downloads the ArcFace model
during its image build. Restore a database that contains enrolled identities
before starting Face Auth.

## Configure

```bash
cd /home/ubuntu/smart-attendance/attendance-system
cp infra/.env.example infra/.env
nano infra/.env
chmod 600 infra/.env
```

Set unique random values for `POSTGRES_PASSWORD`, `JWT_SECRET`,
`FACE_CLIENT_API_KEY`, and `FACE_ADMIN_API_KEY`. `JWT_SECRET` must contain at
least 32 random characters. Keep both API keys and `JWT_SECRET` on EC2; they are
intentionally not embedded in the APK.

## Build and start

```bash
cd /home/ubuntu/smart-attendance/attendance-system
docker compose --env-file infra/.env -f infra/compose.production.yaml config --quiet
docker compose --env-file infra/.env -f infra/compose.production.yaml build
docker compose --env-file infra/.env -f infra/compose.production.yaml up -d
docker compose --env-file infra/.env -f infra/compose.production.yaml ps
```

The one-shot `migration` service creates the configured tenant databases and
applies every Prisma migration before NestJS starts.

For the demo account, link MSSV `1389570` to the identity named by
`DEMO_STUDENT_FACE_IDENTITY`:

```bash
docker compose --env-file infra/.env -f infra/compose.production.yaml run --rm migration node scripts/seed-demo-auth.js
```

The configured identity must already exist in PostgreSQL table `FaceIdentity`.

## Verify

```bash
curl -fsS http://127.0.0.1/health
curl -fsS http://127.0.0.1/face-api/api/v1/health
docker compose --env-file infra/.env -f infra/compose.production.yaml logs --tail=200 backend face-auth nginx
```

Do not run `docker compose down -v`; `-v` deletes the PostgreSQL volume. Use
HTTPS before distributing the app outside a controlled test because camera
frames and session tokens must not travel over plain HTTP.
