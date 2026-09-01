# Hệ thống điểm danh

## Cấu trúc

- `apps/backend/`: API NestJS và Prisma.
- `apps/frontend_student/`: ứng dụng Flutter.
- `services/face_auth/`: dịch vụ xác thực khuôn mặt.
- `infra/`: Docker Compose và cấu hình triển khai.

## Chạy bằng Docker

1. Tạo file môi trường:

   ```powershell
   Copy-Item infra\.env.example infra\.env
   ```

2. Mở `infra/.env` và thay các giá trị bí mật mẫu.

3. Khởi động hệ thống:

   ```powershell
   docker compose --env-file infra/.env -f infra/compose.production.yaml up --build -d
   ```

4. Kiểm tra trạng thái:

   ```powershell
   docker compose --env-file infra/.env -f infra/compose.production.yaml ps
   ```

Migration database chạy tự động trước khi backend khởi động.

## Chạy khi phát triển

```powershell
docker compose -f infra/compose.yaml up -d

cd apps/backend
npm install
npm run start:dev
```

```powershell
cd apps/frontend_student
flutter pub get
flutter run
```

## Xác thực khuôn mặt

Dữ liệu khuôn mặt được lưu trong bảng `FaceIdentity` của PostgreSQL. Database
phải có dữ liệu đã enroll trước khi sử dụng xác thực khuôn mặt.

Hướng dẫn triển khai xem tại `infra/DEPLOY_EC2.md`. Hướng dẫn chạy tải lớn xem
tại `infra/DEPLOY_300_STUDENTS.md`.

## Dữ liệu không đưa lên GitHub

Không đưa `.env`, mật khẩu, API key, database dump, ảnh khuôn mặt, embedding,
file model tải về hoặc thư mục build lên GitHub.
