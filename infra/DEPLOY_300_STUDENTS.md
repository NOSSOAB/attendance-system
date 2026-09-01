# Stack thử tải 300 sinh viên

`compose.production.300.yaml` tách Face Auth thành 40 shard cố định. Mỗi shard
giữ tối đa 30 session, có 3 detector và 3 worker nhận dạng. NestJS chạy bốn
container và trả `faceShard` trong ticket; Flutter gửi frame, status và delete
qua `/face-api/face-01` đến `/face-api/face-40`, nên session trong RAM không bị
đưa nhầm container.

Bốn backend dùng `FACE_SHARD_OFFSET` lần lượt 0, 10, 20 và 30. Với 300 yêu cầu
được Nginx cân bằng, mỗi Face shard nhận 7 hoặc 8 sinh viên thay vì bốn backend
cùng dồn lượt đầu tiên vào `face-01`.

## Yêu cầu máy chủ

Stack Compose này chạy trên **một máy lớn để thử tải**, không dành cho EC2
`t3.micro`. Tổng giới hạn container xấp xỉ 158 vCPU và 113 GiB RAM, vì vậy máy
thử cần tối thiểu:

- 192 logical CPU;
- 128 GiB RAM;
- SSD còn trống ít nhất 40 GiB;
- uplink thực tế tối thiểu 1 Gbps;
- Docker Engine và Docker Compose mới.

Production có tính sẵn sàng cao nên phân 40 Face task trên nhiều node/ECS thay
vì giữ tất cả trong một máy. Dù chạy kiểu nào, phải khởi động đủ task trước giờ
điểm danh vì model mất hàng chục giây để nạp.

## Chuẩn bị

Face Auth source đã nằm trong monorepo:

```text
/home/ubuntu/smart-attendance/attendance-system
```

Tạo `infra/.env` từ `.env.example`, dùng secret thật và restore PostgreSQL có
bảng `FaceIdentity` chứa đầy đủ danh tính sinh viên đã enroll. Dockerfile tự
tải ArcFace model trong lúc build image, nên không cần model hay face database
host volume riêng.

Không chạy stack thật nếu chưa có HTTPS. Ảnh khuôn mặt và session token không
được truyền qua HTTP ngoài môi trường thử kín.

## Kiểm tra và khởi động

```bash
cd /home/ubuntu/smart-attendance/attendance-system
bash infra/preflight-300.sh

docker compose \
  --env-file infra/.env \
  -f infra/compose.production.300.yaml \
  build

docker compose \
  --env-file infra/.env \
  -f infra/compose.production.300.yaml \
  up -d
```

Chờ toàn bộ model nạp xong rồi kiểm tra:

```bash
docker compose \
  --env-file infra/.env \
  -f infra/compose.production.300.yaml \
  ps

for shard in $(seq -w 1 40); do
  curl -fsS "http://127.0.0.1/face-api/face-${shard}/api/v1/health"
done

curl -fsS http://127.0.0.1/health
```

## Điều kiện cho phép dùng thật

Phải thử trên staging bằng đúng loại máy chủ và đúng mẫu ảnh 640x480 của ứng
dụng. Bài thử gồm 300 sinh viên tạo phiên trong cùng một đợt, gửi đủ frame
liveness và ghi bản ghi điểm danh.

Chỉ cho phép sử dụng khi:

- 300/300 phiên được chấp nhận;
- 300/300 yêu cầu cuối `/students/attendance/scan` ghi được kết quả, không có 5xx;
- p95 của bước kiểm tra BLE/GPS và ghi PostgreSQL không quá 2 giây;
- p95 hoàn tất không quá 15 giây;
- tỷ lệ HTTP 429 dưới 0,1%;
- không có kết quả `SERVER_BUSY`;
- CPU dưới 75%, RAM dưới 80%;
- `verification_queue_waiting` không tăng kéo dài;
- PostgreSQL không hết connection và không có lỗi unique/deadlock ngoài dự kiến.

Kết quả benchmark cục bộ dùng để chọn số shard được lưu tại
`infra/LOAD_TEST_RESULTS_LOCAL.md`.

Nếu không đạt, tăng số shard hoặc giảm số session tối đa mỗi shard; không tăng
`verification_queue_capacity` lớn vì thao tác đó chỉ biến quá tải thành hàng
đợi dài.
