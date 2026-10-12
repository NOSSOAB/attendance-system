# Chuyển EC2 sang mobile-first

Thực hiện trên EC2 sau khi đã đưa mã nguồn này lên máy. Không chạy lệnh đổi
stack khi chưa sao lưu file môi trường và database.

## 1. Chuẩn bị môi trường

Trong `infra/.env`, giữ nguyên các giá trị PostgreSQL và JWT hiện có, rồi đặt:

```dotenv
MOBILE_FACE_AUTH_ENABLED=true
MOBILE_FACE_MODEL_ID=opencv_sface_2021dec_v1
```

Tạo bản sao trước khi thay đổi:

```bash
cd /duong-dan/attendance-system
cp infra/.env "infra/.env.backup.$(date +%Y%m%d-%H%M%S)"
set -a; . infra/.env; set +a
docker compose --env-file infra/.env -f infra/compose.production.yaml exec -T postgres \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "backup-before-mobile-first.sql"
```

## 2. Chuẩn bị mẫu khuôn mặt

Tạo vector SFace từ 2--5 ảnh hồ sơ đã có trước buổi điểm danh. Không yêu cầu
sinh viên đăng ký lại trong lúc điểm danh.
Các ảnh phải khác nhau và cùng một người; công cụ sẽ từ chối bộ ảnh có độ
giống nhau thấp hơn ngưỡng xác minh.

```bash
python services/face_auth/tools/build_mobile_face_reference.py ...
docker compose --env-file infra/.env -f infra/compose.production.yaml run --rm \
  -v /duong-dan/reference.json:/tmp/reference.json:ro \
  -v "$PWD/apps/backend/scripts/import-mobile-face-reference.js:/app/scripts/import-mobile-face-reference.js:ro" \
  migration \
  node scripts/import-mobile-face-reference.js /tmp/reference.json
```

Build APK arm64 có mobile-first từ máy build đã có release keystore:

```powershell
flutter build appbundle --release --target-platform android-arm64 `
  --dart-define=MOBILE_FACE_AUTH=true `
  --dart-define=BLE_ATTENDANCE_ENABLED=true `
  --dart-define=API_BASE_URL=https://YOUR_SERVER_NAME
```

Lần điểm danh đầu chỉ khác ở chỗ khóa Android Keystore được gắn sau khi khuôn
mặt trực tiếp khớp mẫu hồ sơ. Người dùng vẫn chỉ thực hiện một luồng xác minh.

## 3. Chuyển sang steady-state mobile-first

Sau khi toàn bộ nhóm pilot đã enroll, dừng profile cũ bằng cùng compose file
nhưng không truyền profile:

```bash
docker compose --env-file infra/.env \
  -f infra/compose.production.yaml up -d --remove-orphans
docker compose --env-file infra/.env \
  -f infra/compose.production.yaml ps
curl -fsS https://$SERVER_NAME/health
```

Kết quả `ps` không được còn container `face-auth`. Khi đó EC2 chỉ xử lý chữ ký
P-256, vector 128 chiều, BLE, GPS và PostgreSQL cho mỗi lần điểm danh.

## 4. Kiểm tra pilot

Kiểm tra với ít nhất hai sinh viên đã enrollment: một lần hợp lệ, một lần sai
khuôn mặt, và thử gửi lại cùng ticket. Ticket phải chỉ dùng được một lần; lần
thứ hai phải bị từ chối. Theo dõi `docker stats --no-stream` trong khi 50 máy
điểm danh để xác nhận RAM không bị dồn lên bởi `face-auth`.
