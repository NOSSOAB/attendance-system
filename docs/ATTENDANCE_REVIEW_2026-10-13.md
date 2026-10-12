# Rà soát phần mềm điểm danh — 13/10/2026

## Tình trạng để báo cáo

Hệ thống gồm Flutter Android, API NestJS, PostgreSQL/Prisma, xác minh khuôn mặt trên điện thoại, GPS, BLE ESP32-C6 và cấu hình HTTPS trên EC2. Mã hiện tại đã nối luồng BLE ESP32-C6: app đọc manufacturer data, backend xác thực AES-GCM và kiểm tra beacon/phòng đã đăng ký. Các kiểm thử tự động qua. **Chưa xác nhận điểm danh đầu cuối trên điện thoại, ESP32-C6 và EC2 thật.**

## Bằng chứng đã kiểm tra

| Hạng mục | Kết quả |
| --- | --- |
| GitHub `main` trước đợt cập nhật | Commit `7236c0f`, 01/09/2026 13:29 ICT |
| Mã mới trên GitHub `main` | Commit tích hợp `d48ac6f` đã push; gồm BLE ESP32-C6, mobile face, migration và hướng dẫn triển khai |
| Nhánh firmware ESP32-C6 | Commit `408626f`, 10/09/2026 02:16 ICT; đã tích hợp giao thức vào app/API và chuyển khóa thiết bị ra file riêng |
| Backend | Build thành công; 18/18 suite, 72/72 test qua |
| Flutter | `flutter analyze` không có lỗi; 33/33 test qua |
| Python Face Auth và ETL | 25/25 và 20/20 test qua ở lần rà soát trước |
| Android | APK profile v1.0.13+14 build thành công cho arm64 với BLE và mobile face bật |
| Firmware ESP32-C6 | Arduino CLI/core ESP32 3.3.11 biên dịch thành công cho `esp32:esp32:esp32c6`; 55% flash, 5% RAM tĩnh; chưa nạp board |
| Model di động | Face Landmarker và OpenCV SFace được kiểm tra SHA-256; script tải/cài lại được cho bản clone |
| API AWS công khai | `https://18-143-149-146.nip.io/health` trả HTTP 200 `{"status":"ok"}` |
| SSH/triển khai EC2 | Cổng 22 còn timeout tại thời điểm rà soát; chưa đọc được cấu hình, container, migration và dữ liệu đang chạy |
| Thiết bị thật | Chưa nạp firmware mới và chưa đo BLE/camera/GPS/điểm danh trên máy thật |

APK profile chỉ dùng kiểm thử. APK release còn thiếu keystore phát hành. Các bài test dùng mock và mã hóa token tổng hợp, nên không thay thế thử nghiệm phần cứng.

Bản APK profile để thử demo trên máy Android arm64: `dist/smartattendance-v1.0.13-arm64-profile-ble-c6.apk` (117.900.131 byte, SHA-256 `036a4a8d345e4d7ac687570ffe8ee7e939dd1dff68592011e451b3dc5503a01e`). File này ở máy build, không đưa vào GitHub.

## Thay đổi quan trọng

1. Bật BLE trong cấu hình build ứng dụng. Backend nhận `c6Token` thay cho thông tin phòng do client tự khai và từ chối token sai, mock, tín hiệu yếu, phòng không khớp, thời gian quét bất hợp lý.
2. Tách khóa AES khỏi firmware công khai. Mỗi ESP32-C6 cần một `deviceId` và khóa riêng; chỉ ghi khóa vào firmware và `BLE_C6_DEVICES_JSON` bí mật trên server.
3. Không lưu token BLE thô vào JSON chứng cứ. Thêm script chuẩn bị model có kiểm tra hash và quy trình ký release.

## Điều kiện còn thiếu trước khi công bố sẵn sàng

1. Nạp firmware mới và khóa riêng vào ESP32-C6, đăng ký chính xác `beaconId`/`roomId`/`keyHex` trên EC2. Chưa có việc này thì backend sẽ từ chối điểm danh BLE.
2. Mở SSH tới EC2, sao lưu database, kiểm tra cấu hình hiện hành, migration và phiên bản đang chạy trước khi cập nhật. Đã xác nhận riêng `/health` nhưng chưa xác nhận chức năng điểm danh.
3. Ký APK release bằng keystore chính thức, cài lên điện thoại, thử phiên mở → nhận diện mặt → quét BLE/GPS → ghi điểm danh → xem lịch sử; thử phòng sai, token sửa và điểm danh trùng.
4. Xác nhận mẫu SFace đã nạp cho tài khoản demo và `MOBILE_FACE_AUTH_ENABLED=true` trên backend.

## Giới hạn bảo mật cần nói đúng

Firmware ESP32-C6 hiện chưa có thời gian tuyệt đối trong token. AES-GCM chứng minh token đến từ khóa beacon, nhưng một quảng bá hợp lệ từng thu được vẫn có thể bị chuyển tiếp. RSSI và thời gian quét do điện thoại báo cũng không chống được app bị sửa. Vì vậy BLE chỉ là một lớp tín hiệu vị trí cùng với xác minh khuôn mặt/GPS, chưa đủ để cam kết chống gian lận tuyệt đối.

## Câu trình bày ngắn

“Phần mềm đã có luồng quản lý lịch, mở phiên và ghi nhận điểm danh, xác minh khuôn mặt trên điện thoại, GPS và token BLE ESP32-C6 được API xác thực bằng AES-GCM. Backend, Flutter và APK Android đã qua kiểm thử kỹ thuật. Bước cuối trước khi vận hành là nạp khóa cho beacon, triển khai cấu hình lên EC2, ký bản release và thử toàn bộ luồng trên thiết bị thật.”
