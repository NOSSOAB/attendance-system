# Hệ thống điểm danh

Hệ thống gồm backend NestJS, ứng dụng Flutter, PostgreSQL, xác thực khuôn mặt
và điểm danh BLE.

## Thành phần

| Thư mục | Nội dung |
| --- | --- |
| `apps/backend/` | API NestJS, Prisma và nghiệp vụ điểm danh. |
| `apps/frontend_student/` | Ứng dụng Flutter cho sinh viên. |
| `services/face_auth/` | API xác thực khuôn mặt và kiểm tra sống. |
| `infra/` | Docker Compose, Nginx và hướng dẫn triển khai. |

## Yêu cầu

- Docker Engine và Docker Compose để chạy toàn bộ hệ thống.
- Node.js để chạy backend trực tiếp.
- Flutter SDK để chạy ứng dụng sinh viên.
- PostgreSQL đã có dữ liệu hoặc quyền để migration tạo database mới.

## Cấu hình môi trường

Mẫu biến môi trường nằm trong `infra/.env.example` và
`apps/backend/.env.example`.

### Chạy bằng Docker

```powershell
Copy-Item infra\.env.example infra\.env
```

Mở `infra/.env` và thay các giá trị sau bằng giá trị riêng của môi trường:

- `POSTGRES_PASSWORD`
- `JWT_SECRET`
- `FACE_CLIENT_API_KEY`
- `FACE_ADMIN_API_KEY`

### Chạy backend trực tiếp

```powershell
Copy-Item apps\backend\.env.example apps\backend\.env
```

Mở `apps/backend/.env` và cấu hình các chuỗi kết nối database.

## Chạy toàn bộ hệ thống bằng Docker

```powershell
docker compose --env-file infra/.env -f infra/compose.production.yaml up --build -d
```

Kiểm tra các container:

```powershell
docker compose --env-file infra/.env -f infra/compose.production.yaml ps
```

Kiểm tra API:

```powershell
curl http://localhost/health
curl http://localhost/face-api/api/v1/health
```

Container `migration` tự tạo các database cần thiết và chạy toàn bộ Prisma
migration trước khi backend khởi động.

## Chạy khi phát triển

### Khởi động PostgreSQL cục bộ

```powershell
docker compose -f infra/compose.yaml up -d
```

### Khởi động backend

```powershell
cd apps/backend
npm install
npx prisma migrate deploy
npm run start:dev
```

### Khởi động ứng dụng Flutter

Mở một cửa sổ dòng lệnh khác:

```powershell
cd apps/frontend_student
flutter pub get
flutter run
```

Khi chạy thiết bị thật, đặt địa chỉ API của máy chủ:

```powershell
flutter run --dart-define=API_BASE_URL=https://<máy-chủ>
```

## Xác thực khuôn mặt

Face Auth đọc embedding từ bảng `FaceIdentity` trong PostgreSQL. Database phải
có dữ liệu khuôn mặt đã enroll trước khi chức năng xác thực được sử dụng.

Để enroll bằng Python:

```powershell
cd services/face_auth
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
$env:FACE_DATABASE_URL = "postgresql://<người-dùng>:<mật-khẩu>@<máy-chủ>:5432/<database>"
.\.venv\Scripts\python enroll_faces.py
```

Ảnh enroll chỉ lưu tại máy thực hiện enroll. Chúng không được đưa lên GitHub.

Khi chạy Docker Compose, Dockerfile tự tải model cần thiết trong quá trình
build. Không cần sao chép thêm source hoặc model từ project khác.

## ESP32-C6 BLE

Nhánh này giữ mã firmware ESP32-C6. Ứng dụng Flutter và API đồng bộ với token
AES-GCM qua manufacturer data nằm trên nhánh `main`; dùng `main` khi chạy toàn bộ
hệ thống. Không nạp sketch ở các commit cũ của nhánh này vì khóa AES từng được
ghi trực tiếp trong mã Git. Khóa cũ không được dùng lại.

Tạo khóa riêng cho từng board trước khi nạp `SecureAttendance_C6.ino`:

```bash
python create_device_secrets.py \
  --device-id A1B2C3D4 \
  --beacon-id ESP32_TEST_01 \
  --room-id ROOM_A101
```

Thay các mã ví dụ bằng ID và phòng thực tế. Script tạo
`ble_device_secrets.h` cho firmware và `ble_device_registry.local.json` để
đăng ký thiết bị trong `BLE_C6_DEVICES_JSON` trên EC2. Hai file này được Git
bỏ qua; không đưa khóa vào APK hay repository. Mỗi board cần ID và khóa riêng.
Chỉ bật `ATTENDANCE_REQUIRE_BLE=true` trên backend sau khi đã nạp board và
đăng ký đúng khóa/phòng.

## Tài khoản demo

Chỉ dùng trên database thử nghiệm:

```powershell
cd apps/backend
npm run seed:demo-auth
```

Không chạy lệnh này trên database đang sử dụng thật.

## Triển khai

- Triển khai EC2: `infra/DEPLOY_EC2.md`.
- Thử tải 300 sinh viên: `infra/DEPLOY_300_STUDENTS.md`.

Sử dụng HTTPS trước khi cho người dùng truy cập từ Internet.

## Kiểm thử

```powershell
cd apps/backend
npm run test
```

```powershell
cd services/face_auth
python -m unittest discover -s tests -v
```

## Quy tắc dữ liệu và Git

Không đưa các dữ liệu sau lên GitHub:

- `.env`, mật khẩu, API key và khóa chứng thực.
- Database dump và chuỗi kết nối database thật.
- Ảnh khuôn mặt, embedding và file `face_db`.
- Model tải về, file build, log, `node_modules` và thư mục cache.

Sau khi thay đổi source:

```powershell
git add .
git commit -m "Mô tả thay đổi"
git push
```
