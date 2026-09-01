# Chạy tải 300 sinh viên

File `compose.production.300.yaml` dùng 40 dịch vụ Face Auth và 4 backend để thử tải.

## Yêu cầu máy chủ

- Tối thiểu 192 luồng CPU.
- Tối thiểu 128 GB RAM.
- Còn trống ít nhất 40 GB SSD.
- Docker Engine và Docker Compose mới.

## Chuẩn bị

1. Tạo `infra/.env` từ `infra/.env.example`.
2. Khai báo khóa bí mật thật.
3. Khôi phục PostgreSQL đã có dữ liệu `FaceIdentity`.
4. Cấu hình HTTPS trước khi dùng ngoài môi trường thử nghiệm.

## Khởi động

```bash
bash infra/preflight-300.sh
docker compose --env-file infra/.env -f infra/compose.production.300.yaml up --build -d
docker compose --env-file infra/.env -f infra/compose.production.300.yaml ps
```

Chỉ sử dụng cấu hình này trên máy chủ đáp ứng đủ tài nguyên.
