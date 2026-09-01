# Triển khai trên EC2

## Chuẩn bị

1. Cài Docker Engine và Docker Compose trên máy chủ.
2. Clone repository vào thư mục triển khai.
3. Tạo file môi trường:

   ```bash
   cp infra/.env.example infra/.env
   chmod 600 infra/.env
   ```

4. Trong `infra/.env`, thay `POSTGRES_PASSWORD`, `JWT_SECRET`,
   `FACE_CLIENT_API_KEY` và `FACE_ADMIN_API_KEY` bằng giá trị ngẫu nhiên.
5. Khôi phục PostgreSQL có dữ liệu bảng `FaceIdentity` trước khi khởi động.

## Khởi động

```bash
docker compose --env-file infra/.env -f infra/compose.production.yaml config --quiet
docker compose --env-file infra/.env -f infra/compose.production.yaml up --build -d
docker compose --env-file infra/.env -f infra/compose.production.yaml ps
```

## Kiểm tra

```bash
curl -fsS http://127.0.0.1/health
curl -fsS http://127.0.0.1/face-api/api/v1/health
```

Sử dụng HTTPS trước khi cho người dùng bên ngoài truy cập hệ thống.
