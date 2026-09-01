# Dịch vụ xác thực khuôn mặt

## Thành phần

- `backend/`: API FastAPI.
- `modules/`: nhận diện khuôn mặt và kiểm tra sống.
- `models/`: tài nguyên model cần thiết.
- `tests/`: kiểm thử dịch vụ.

## Enroll khuôn mặt

1. Tạo thư mục `database_faces/<mã-danh-tính>/` và đặt ảnh đã có sự đồng ý.
2. Cài thư viện Python:

   ```powershell
   python -m venv .venv
   .\.venv\Scripts\python -m pip install -r requirements.txt
   ```

3. Khai báo kết nối PostgreSQL và chạy enroll:

   ```powershell
   $env:FACE_DATABASE_URL = "postgresql://<người-dùng>:<mật-khẩu>@<máy-chủ>:5432/<database>"
   .\.venv\Scripts\python enroll_faces.py
   ```

Embedding được lưu vào bảng `FaceIdentity` của PostgreSQL. Ảnh enroll chỉ dùng
trên máy cục bộ và không đưa lên GitHub.

## Chạy bằng Docker Compose

```powershell
Copy-Item infra\.env.example infra\.env
docker compose --env-file infra/.env -f infra/compose.production.yaml up --build -d
```

Database phải có dữ liệu đã enroll trước khi dùng xác thực khuôn mặt.

## Tải model khi chạy trực tiếp bằng Python

```powershell
python services/face_auth/scripts/fetch_models.py
```

Dockerfile tự tải model khi build image nên không cần chạy lệnh này nếu dùng Docker Compose.
