# Rà soát phần mềm điểm danh — 13/10/2026

## Tình trạng để báo cáo

Hệ thống gồm Flutter Android, API NestJS, PostgreSQL/Prisma, xác minh khuôn mặt trên điện thoại, GPS, BLE ESP32-C6 và cấu hình HTTPS trên EC2. Mã hiện tại đã nối luồng BLE ESP32-C6: app đọc manufacturer data, backend xác thực AES-GCM và kiểm tra beacon/phòng đã đăng ký. Backend mới đã triển khai lên EC2, các kiểm thử tự động qua. **BLE trên production vẫn tắt vì ESP32-C6 chưa nạp firmware và chưa có khóa thiết bị; chưa xác nhận điểm danh đầu cuối trên thiết bị thật.**

## Bằng chứng đã kiểm tra

| Hạng mục | Kết quả |
| --- | --- |
| GitHub `main` trước đợt cập nhật | Commit `7236c0f`, 01/09/2026 13:29 ICT |
| Các cập nhật GitHub ngày 13/10 | `3bc899b` thêm bản thiết kế HTML/ảnh giảng viên; phần BLE/mobile face ở các commit `d48ac6f` và `1d5b783` |
| Mã backend triển khai từ GitHub `main` | Commit `ae4e434` ngày 13/10/2026; mã này đã được dùng để build backend trên EC2 |
| Nhánh firmware ESP32-C6 | Bản cũ `408626f` ngày 10/09/2026; đầu nhánh đã cập nhật lên `7298903` ngày 13/10, bỏ khóa AES khỏi sketch và thêm script tạo khóa riêng. Khóa cũ vẫn nằm trong lịch sử Git, tuyệt đối không dùng lại |
| Backend | Build thành công; 18/18 suite, 74/74 test qua |
| Flutter | `flutter analyze` không có lỗi; 33/33 test qua |
| Python Face Auth và ETL | 25/25 và 20/20 test qua ở lần rà soát trước |
| Android | APK profile v1.0.13+14 build thành công cho arm64 với BLE và mobile face bật; `apksigner` xác minh chữ ký v2 Android Debug, `aapt` xác nhận package `com.smartattendance.mobile.v2` |
| Firmware ESP32-C6 | Arduino CLI/core ESP32 3.3.11 biên dịch thành công cho `esp32:esp32:esp32c6`; 55% flash, 5% RAM tĩnh; chưa nạp board |
| Model di động | Face Landmarker và OpenCV SFace được kiểm tra SHA-256; script tải/cài lại được cho bản clone |
| API AWS công khai | `https://18-143-149-146.nip.io/health` trả HTTP 200 `{"status":"ok"}` |
| SSH/triển khai EC2 | Đã thêm SSH 22 chỉ cho IP máy hiện tại `1.53.101.245/32` vào `smartattendance-sg`, SSH thành công. Đã sao lưu PostgreSQL và mã cũ; build và chạy backend từ `ae4e434`. Backend, Caddy, PostgreSQL đều `healthy` |
| Migration EC2 | 13 migration trên mỗi database, cả 5 database đều không còn migration chờ áp dụng |
| Kiểm tra API sau triển khai | HTTPS `/health` trả HTTP 200 `{"status":"ok"}`; `/students/profile` không có token trả HTTP 401 như mong đợi |
| Bộ xác thực BLE trên image AWS | Trong container tách biệt với khóa thử dùng một lần: nhận token AES-GCM hợp lệ; từ chối token bị sửa, sai khóa và sai định dạng. Chưa kiểm thử bằng board thật |
| Trạng thái dữ liệu và cờ tính năng | `MOBILE_FACE_AUTH_ENABLED=true`, có 2 bản ghi `MobileFaceIdentity` đang hoạt động trong `attendance_db`; database này hiện có 0 phiên và 0 bản ghi điểm danh. `ATTENDANCE_REQUIRE_BLE=false`; chưa có `BLE_C6_DEVICES_JSON` |
| Thiết bị thật | Chưa nạp firmware mới và chưa đo BLE/camera/GPS/điểm danh trên máy thật |

Người dùng chỉ cần APK thử nghiệm; bản profile được ký bằng Android Debug để cài thử, không phải gói phát hành. Các bài test dùng mock và mã hóa token tổng hợp, nên không thay thế thử nghiệm phần cứng. Hiện ADB không thấy điện thoại kết nối.

Bản APK profile để thử demo trên máy Android arm64: `dist/smartattendance-v1.0.13-arm64-profile-ble-c6.apk` (117.900.131 byte, SHA-256 `036a4a8d345e4d7ac687570ffe8ee7e939dd1dff68592011e451b3dc5503a01e`). File này ở máy build, không đưa vào GitHub.

## Thay đổi quan trọng

1. Bật BLE trong cấu hình build ứng dụng. Backend nhận `c6Token` thay cho thông tin phòng do client tự khai và từ chối token sai, mock, tín hiệu yếu, phòng không khớp, thời gian quét bất hợp lý. Nhiều beacon đã đăng ký trong cùng phòng đều được hỗ trợ; backend production kiểm tra registry lúc khởi động.
2. Tách khóa AES khỏi firmware công khai. Mỗi ESP32-C6 cần một `deviceId` và khóa riêng; chỉ ghi khóa vào firmware và `BLE_C6_DEVICES_JSON` bí mật trên server.
3. Không lưu token BLE thô vào JSON chứng cứ. Thêm script chuẩn bị model có kiểm tra hash và quy trình ký release.

## Điều kiện còn thiếu trước khi công bố sẵn sàng

1. Nạp firmware mới và khóa riêng vào ESP32-C6, đăng ký chính xác `beaconId`/`roomId`/`keyHex` trên EC2. Chưa có việc này thì chưa thể xác thực tín hiệu BLE của thiết bị thật.
2. Khi board đã nạp firmware và registry đã cấu hình, chuyển `ATTENDANCE_REQUIRE_BLE=true` rồi thử token hợp lệ/sai phòng/bị sửa trên AWS. Không bật cờ này trước thời điểm đó vì backend mới sẽ từ chối khởi động nếu registry rỗng.
3. Cài APK profile lên điện thoại Android arm64, thử phiên mở → nhận diện mặt → quét BLE/GPS → ghi điểm danh → xem lịch sử; thử phòng sai, token sửa và điểm danh trùng. Chưa thể thử BLE thật vì ESP32-C6 chưa được nạp firmware.
4. Xác nhận tài khoản demo nằm trong 2 mẫu SFace đã có trên `attendance_db`, hoặc enroll tài khoản cần dùng. Chưa có phiên điểm danh thực tế để đối chiếu dữ liệu đầu cuối.

## Giới hạn bảo mật cần nói đúng

Firmware ESP32-C6 hiện chưa có thời gian tuyệt đối trong token. AES-GCM chứng minh token đến từ khóa beacon, nhưng một quảng bá hợp lệ từng thu được vẫn có thể bị chuyển tiếp. RSSI và thời gian quét do điện thoại báo cũng không chống được app bị sửa. Vì vậy BLE chỉ là một lớp tín hiệu vị trí cùng với xác minh khuôn mặt/GPS, chưa đủ để cam kết chống gian lận tuyệt đối.

## Câu trình bày ngắn

“Phần mềm đã có luồng quản lý lịch, mở phiên và ghi nhận điểm danh, xác minh khuôn mặt trên điện thoại, GPS và token BLE ESP32-C6 được API xác thực bằng AES-GCM. Backend bản 13/10 đã triển khai lên EC2 và hoạt động qua HTTPS; Flutter và APK Android thử nghiệm đã qua kiểm thử kỹ thuật. BLE trên production đang chờ nạp firmware, đăng ký khóa beacon và thử toàn bộ luồng trên thiết bị thật.”
