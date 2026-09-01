# Kết quả thử tải cục bộ ngày 2026-08-04

## Môi trường

- CPU Intel Core i5-12450H: 8 core, 12 logical CPU.
- RAM 15,7 GiB; khoảng 4,1 GiB trống trước khi chạy.
- Chạy trực tiếp FastAPI bằng Python 3.11, không dùng Docker.
- Model thật: MediaPipe Face Landmarker và ArcFace `w600k_r50.onnx`.
- Ảnh thật đã enroll của `person_A` được phát lại; active liveness bị tắt riêng
  trong profile benchmark. Vì vậy đây là kiểm tra năng lực xử lý, không phải kiểm
  định chống giả mạo hay chứng nhận production.

## Một tiến trình Face Auth 3 detector + 3 verification worker

| Phiên đồng thời | Thành công | Thất bại | Lượt 429/gửi lại | p95 |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 0 | 0 | 4,68 giây (cold start) |
| 10 | 10 | 0 | 0 | 0,71 giây |
| 25 | 25 | 0 | 10 | 2,55 giây |
| 50 | 50 | 0 | 31 | 5,06 giây |
| 100 | 100 | 0 | 125 | 9,70 giây |
| 300 | 203 | 97 | 727 | 19,99 giây |

Ở lần chạy 300, tool phiên bản đầu chưa ghi lại mã lỗi terminal. Số lượng worker
và queue đã bị lấp đầy, nhưng không dùng bảng này để khẳng định mã lỗi cụ thể của
97 phiên.

## Mô phỏng một shard production

Một shard dùng đúng giới hạn production: 3 detector, 3 verification worker,
verification queue 6 và tối đa 30 session.

| Kịch bản | Kết quả | Lượt 429/gửi lại | p95 |
| --- | --- | ---: | ---: |
| 19 người, 1 ảnh/người | 9 thành công, 10 thất bại | 14 | 1,37 giây |
| 10 người, 1 ảnh/người | 9 thành công, 1 thất bại | 2 | 1,03 giây |
| 9 người, 1 ảnh/người | 9/9 thành công | 0 | 1,04 giây |
| 9 người, 6 ảnh/người | 9/9 thành công | 3 | 6,82 giây |
| 8 người, 6 ảnh/người | 8/8 thành công | 0 | 6,45 giây |
| 19 người, 6 ảnh/người, queue 30 | 19/19 thành công | 11 | 11,77 giây |

Kết quả này là cơ sở nâng stack từ 16 lên 40 shard. Bốn backend dùng offset
0/10/20/30; khi Nginx chia đều 75 yêu cầu cho mỗi backend, 20 shard nhận 7 người
và 20 shard nhận 8 người.

## API, BLE/GPS và ghi điểm danh

Backend có thêm bài test `Promise.all` gửi đồng thời 300 kết quả gồm Face, BLE và
GPS qua toàn bộ logic `scanAttendance`. Kết quả 300/300 thành công; 300 bản ghi và
300 thông báo được tạo trong 14 ms trên mock in-memory. Con số 14 ms chỉ chứng
minh code không có khóa tuần tự hoặc giới hạn 300 người; nó không đại diện cho
độ trễ PostgreSQL hay mạng thật.

Stack phục vụ bài test staging được nâng thành 4 NestJS backend và PostgreSQL
8 CPU/8 GiB, `max_connections=300`, bên cạnh 40 Face shard.

Với ngân sách thử nghiệm hạn chế, kết quả 19 người/shard cho phép dùng profile
16 shard trên máy 64 vCPU/128 GiB và chấp nhận retry ngắn phía ứng dụng. Profile
40 shard vẫn là cấu hình hướng tới không có retry do quá tải.

## Kết luận sử dụng

Stack 40 shard có khả năng xử lý tải mục tiêu theo demo cục bộ, nhưng chưa được
chứng nhận để đưa vào lớp học. Trước khi dùng thật vẫn phải chạy bài 300 thiết bị
với active liveness, mạng thật, PostgreSQL thật và đúng phần cứng staging; áp dụng
đầy đủ tiêu chí trong `DEPLOY_300_STUDENTS.md`.
