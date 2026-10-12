# Triển khai trên EC2

## Chuẩn bị

1. Gán Elastic IP cho EC2. Tạo DNS A record của `SERVER_NAME` trỏ tới Elastic
   IP đó, rồi mở inbound TCP 80 và 443. Không dùng HTTPS trực tiếp trên IP.
2. Cài Docker Engine và Docker Compose trên máy chủ.
3. Clone repository vào thư mục triển khai.
4. Tạo file môi trường:

   ```bash
   cp infra/.env.example infra/.env
   chmod 600 infra/.env
   ```

5. Trong `infra/.env`, thay `SERVER_NAME`, `CADDY_EMAIL`,
   `POSTGRES_PASSWORD`, `JWT_SECRET`, `FACE_CLIENT_API_KEY` và
   `FACE_ADMIN_API_KEY` bằng giá trị thật. Không thay các secret hiện tại nếu
   đang giữ database cũ, nếu không token và Face Auth đang chạy sẽ mất hiệu lực.
6. Khôi phục PostgreSQL có dữ liệu bảng `FaceIdentity` trước khi khởi động.
7. Với ESP32-C6, tạo khóa riêng cho từng thiết bị theo
   `firmware/esp32-c6/README.md`, nạp firmware vào board, rồi đặt
   `BLE_C6_DEVICES_JSON` trong `infra/.env`. Mỗi mục chứa `deviceId`,
   `beaconId`, `roomId` và `keyHex`; thông tin này chỉ lưu trên EC2.
   Giữ `ATTENDANCE_REQUIRE_BLE=true`.

## Khởi động

Sau khi đã enroll toàn bộ sinh viên mobile, đặt
`MOBILE_FACE_AUTH_ENABLED=true` rồi chạy stack nhẹ:

```bash
docker compose --env-file infra/.env -f infra/compose.production.yaml config --quiet
docker compose --env-file infra/.env -f infra/compose.production.yaml up --build -d --remove-orphans
docker compose --env-file infra/.env -f infra/compose.production.yaml ps
```

Trong giai đoạn enrollment, thêm `--profile legacy-face` vào từng lệnh trên.
Profile này chạy ArcFace cũ để xác minh enrollment một lần. Sau khi enrollment
xong, chạy lại không có profile để dừng container nặng đó.

Ứng dụng Android phải được build với `BLE_ATTENDANCE_ENABLED=true` và
`MOBILE_FACE_AUTH=true`. Khi kiểm thử tại phòng học, xác nhận app thấy token
manufacturer data của ESP32-C6, API xác thực đúng phòng và từ chối token bị
sửa. Bản firmware hiện tại không có thời gian tuyệt đối trong token nên vẫn có
nguy cơ chuyển tiếp token đã quan sát; không dùng riêng BLE làm bằng chứng danh
tính.

## Kiểm tra

```bash
curl -fsS https://$SERVER_NAME/health
curl -fsS https://$SERVER_NAME/face-api/api/v1/health # chỉ khi legacy-face đang bật
```

Caddy chỉ chuyển tiếp HTTPS ở cổng 443; PostgreSQL, NestJS và Face Auth không
được public ra Internet. Khi APK release, truyền đúng `API_BASE_URL` dạng
`https://$SERVER_NAME`.
