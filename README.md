# Attendance System

Monorepo nay duoc sap xep theo thu tu DB -> BE -> FE de nhin vao la biet du lieu nam o dau, backend xu ly o dau, va frontend dang dung ket qua nao.

## 1. DB

- `apps/backend/prisma/schema.prisma`: schema nguon cho attendance system.
- `apps/backend/prisma/migrations/`: lich su thay doi DB de deploy hoac reproduce local.
- `infra/compose.yaml`: PostgreSQL local cho dev/test.
- `infra/.env.example`: mau bien moi truong cho DB local, khong commit file that.

## 2. BE

- `apps/backend/src/database/prisma/`: ket noi DB chung va tenant DB.
- `apps/backend/src/modules/auth/`: dang nhap va dat lai mat khau.
- `apps/backend/src/modules/schools/`: danh muc truong.
- `apps/backend/src/modules/students/`: home, lich hoc, diem danh, thong bao cho sinh vien.
- `apps/backend/.env.example`: mau cau hinh backend.
- `apps/backend/scripts/seed-demo-auth.js`: seed demo bang env, khong hard-code secret that.

## 3. FE

- `apps/frontend_student/lib/core/`: config API va lop goi backend.
- `apps/frontend_student/lib/features/`: man hinh theo nghiep vu.
- `apps/frontend_student/lib/shared/`: model, widget, navigation dung chung.

## Local setup

1. Tao `infra/.env` tu `infra/.env.example`.
2. Tao `apps/backend/.env` tu `apps/backend/.env.example`.
3. Chay `docker compose -f infra/compose.yaml up -d`.
4. Chay `cd apps/backend && npm install && npm run build`.
5. Chay `cd apps/frontend_student && flutter pub get && flutter analyze`.

## Git hygiene

- Thu muc `apps/backend/.git-local-backup/` va `apps/backend/local-only/` chi de giu du lieu local, da bi chan khong cho len GitHub.
- Thu muc `.deploy/` chua ban sao cau hinh deploy local, `.docx_work/` chua file trung gian, va `outputs/` chua APK/bao cao da sinh; ca ba khong duoc dua len GitHub. Cau hinh ha tang co the chia se nam trong `infra/`.
- Tat ca file `.env`, key, keystore, Firebase config, build output, `node_modules`, `.dart_tool` deu da bi chan o root `.gitignore`.

## Dua source len GitHub

1. Kiem tra noi dung se commit:

   ```powershell
   git status
   git diff --cached --check
   ```

2. Tao repository rong tren GitHub, sau do ket noi va day nhanh `main`:

   ```powershell
   git branch -M main
   git remote add origin https://github.com/<tai-khoan>/<ten-repository>.git
   git push -u origin main
   ```

   Thay `<tai-khoan>` va `<ten-repository>` bang thong tin repository vua tao.

## Face Auth

- Ma nguon FastAPI cua dich vu nhan dien khuon mat nam trong `services/face_auth/`; khong can clone them project Python ben ngoai.
- Docker Compose build dich vu nay truc tiep tu monorepo va Dockerfile tu tai recognition model vao image. Script `services/face_auth/scripts/fetch_models.py` chi dung khi chay API Python truc tiep tren may.
- Anh enroll, embedding khuon mat trong PostgreSQL, model ONNX tai ve va khoa API la du lieu nhay cam, khong duoc commit.

## EC2 + Face Auth

- Production Compose: `infra/compose.production.yaml`.
- EC2 deployment guide: `infra/DEPLOY_EC2.md`.
- The Flutter app asks NestJS for a short-lived Face Auth session, sends camera
  frames with the session token, and submits the terminal session to NestJS.
- NestJS verifies the Face Auth result and identity before writing an
  `AttendanceRecord`; the client can no longer mark itself successful by
  sending `outcome: success`.

## BLE attendance MVP

Flutter co hai implementation cua `BleScanner`: mock de test giao dien va
`RealBleScanner` dung `FlutterBluePlus.startScan()` de quet ESP32 that.

### Chay demo

1. Chay migration va seed backend:

   ```powershell
   cd apps/backend
   npx prisma migrate deploy
   npm run seed:demo-auth
   npm run start:dev
   ```

2. Chay Flutter voi BLE mock:

   ```powershell
   cd apps/frontend_student
   flutter pub get
   flutter run --dart-define=USE_MOCK_BLE=true
   ```

3. Dang nhap tai khoan demo, mo mot attendance session tu giao dien giang vien,
   sau do bam diem danh tren ung dung sinh vien.

Trang sinh vien quet BLE ngan de hien thi phong gan nhat. Luot quet nay chi de
goi y. Khi bam diem danh, ung dung luon tao mot luot quet moi 6,5 giay, sau do
xac thuc khuon mat va gui BLE/face/GPS evidence len backend.

Backend kiem tra session, duplicate, beacon/phong, nguong RSSI, thoi gian quet va
ket qua face auth. Ket qua API co mot trong cac status:
`present`, `late`, `flagged`, `rejected_session_closed`,
`rejected_duplicate`.

## Thử tải 300 sinh viên

- Stack 40 Face Auth shard: `infra/compose.production.300.yaml`.
- Nginx định tuyến session theo shard: `infra/nginx/sharded.conf`.
- Hướng dẫn phần cứng, khởi động và tiêu chí đạt: `infra/DEPLOY_300_STUDENTS.md`.
- Cấu hình demo cũ vẫn được giữ riêng; không chạy stack 300 trên `t3.micro`.

### Cau hinh mock

- Flutter: `--dart-define=USE_MOCK_BLE=true`.
- Backend: xem cac bien `BLE_TEST_*` trong `apps/backend/.env.example`.
- RSSI test mac dinh: `-80 dBm`.
- Thoi gian scan hop le: tu 5 den 8 giay.

### Chay voi ESP32 that

ESP32 phai advertise ten `ATTENDANCE_BLE_TEST` va Service UUID
`12345678-1234-1234-1234-123456789abc`. Ung dung anh xa thiet bi nay thanh
beacon `ESP32_TEST_01`, phong `ROOM_A101`, dong thoi doc RSSI truc tiep tu goi
quang ba. Dien thoai chi quet BLE, khong can pair/ket noi GATT.

```powershell
cd apps/frontend_student
flutter build apk --debug `
  --dart-define=USE_MOCK_BLE=false `
  --dart-define=API_BASE_URL=http://18.143.149.146 `
  --dart-define=FACE_API_BASE_URL=http://18.143.149.146/face-api
```

Trang chu quet 2 giay; moi luot diem danh quet moi 6,5 giay. Rotating token,
anti-replay va chong gia mao BLE van nam ngoai pham vi MVP.
