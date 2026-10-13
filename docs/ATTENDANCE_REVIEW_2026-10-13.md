# Rà soát phần mềm điểm danh — 13/10/2026

## Tình trạng để báo cáo

Hệ thống gồm Flutter Android, API NestJS, PostgreSQL/Prisma, xác minh khuôn mặt trên điện thoại, GPS, BLE ESP32-C6 và cấu hình HTTPS trên EC2. Mã hiện tại đã nối luồng BLE ESP32-C6: app đọc manufacturer data, backend xác thực AES-GCM và kiểm tra beacon/phòng đã đăng ký. ESP32-C6 đã nạp firmware có khóa riêng; máy tính thu được quảng bá BLE thật và backend trên EC2 xác thực token phát từ board. **Production đã bắt buộc BLE cho mọi phiên điểm danh demo, dùng chung một beacon `ROOM_PHONG_LAB_02` theo yêu cầu. Chưa xác nhận toàn bộ luồng điểm danh trên điện thoại Android.**

## Bằng chứng đã kiểm tra

| Hạng mục | Kết quả |
| --- | --- |
| GitHub `main` trước đợt cập nhật | Commit `7236c0f`, 01/09/2026 13:29 ICT |
| Các cập nhật GitHub ngày 13/10 | `3bc899b` thêm bản thiết kế HTML/ảnh giảng viên; phần BLE/mobile face ở các commit `d48ac6f` và `1d5b783` |
| Mã backend triển khai từ GitHub `main` | Commit `cb1c5f4` ngày 13/10/2026; thay thế bản trước `ae4e434` trên EC2 |
| Nhánh firmware ESP32-C6 | Bản cũ `408626f` ngày 10/09/2026; đầu nhánh đã cập nhật lên `7298903` ngày 13/10, bỏ khóa AES khỏi sketch và thêm script tạo khóa riêng. Khóa cũ vẫn nằm trong lịch sử Git, tuyệt đối không dùng lại |
| Backend | Build thành công; 18/18 suite, 75/75 test qua sau cấu hình một beacon demo dùng chung |
| Flutter | `flutter analyze` không có lỗi; 33/33 test qua |
| Python Face Auth và ETL | 25/25 và 20/20 test qua ở lần rà soát trước |
| Android | APK profile v1.0.13+14 build thành công cho arm64 với BLE và mobile face bật; `apksigner` xác minh chữ ký v2 Android Debug, `aapt` xác nhận package `com.smartattendance.mobile.v2` |
| Firmware ESP32-C6 | Arduino CLI/core ESP32 3.3.11 biên dịch và nạp thành công qua CH343/COM7 vào ESP32-C6 revision v0.2; các vùng flash đều xác minh hash. Bản dùng khóa riêng chiếm 55% flash, 5% RAM tĩnh. File nạp nằm ngoài Git tại `dist/c6-provisioned/out/SecureAttendance_C6.ino.bin` (728.512 byte, SHA-256 `47cde53794dad347391eaf2f06ecb9a3a41561962ef47e9586277b7fc4e276b9`) |
| Model di động | Face Landmarker và OpenCV SFace được kiểm tra SHA-256; script tải/cài lại được cho bản clone |
| API AWS công khai | `https://18-143-149-146.nip.io/health` trả HTTP 200 `{"status":"ok"}` |
| SSH/triển khai EC2 | Đã thêm SSH 22 chỉ cho IP máy hiện tại `1.53.101.245/32` vào `smartattendance-sg`, SSH thành công. Đã sao lưu PostgreSQL và mã cũ; backend từ mã GitHub `cb1c5f4` đã build/chạy trên EC2. Backend, Caddy, PostgreSQL đều `healthy` |
| Migration EC2 | 13 migration trên mỗi database, cả 5 database đều không còn migration chờ áp dụng |
| Kiểm tra API sau triển khai | HTTPS `/health` trả HTTP 200 `{"status":"ok"}`; `/students/profile` không có token trả HTTP 401 như mong đợi |
| Bộ xác thực BLE trên image AWS | Container production nhận token AES-GCM thu trực tiếp từ ESP32-C6, trả đúng `ROOM_PHONG_LAB_02` và từ chối token bị sửa. Máy tính thu 3 token khác nhau trong 39 giây; cả 3 xác thực bằng khóa riêng, không có token sai |
| Trạng thái dữ liệu và cờ tính năng | `MOBILE_FACE_AUTH_ENABLED=true`. Có 2 mẫu SFace đang hoạt động trong `attendance_db`, khớp khóa khuôn mặt của hai tài khoản sinh viên demo HUCE/HUST. `attendance_db` có 0 phiên và 0 bản ghi điểm danh; các database sinh viên riêng có dữ liệu lịch/điểm danh. Container production đang chạy `ATTENDANCE_REQUIRE_BLE=true`, `BLE_DEMO_ROOM_ID=ROOM_PHONG_LAB_02` |
| Dữ liệu demo ngày thứ Tư | `huce_student_db`: 1 tài khoản sinh viên, 7 lịch hoạt động, 24 phiên/21 bản ghi điểm danh; `hust_student_db`: 1 tài khoản, 6 lịch, 6 phiên/3 bản ghi. Cả hai có lịch tuần 13:00–15:00 ở “Phong Lab 02” |
| Registry BLE và phòng demo | Header khóa riêng giữ ngoài Git; 1 ESP32-C6 đăng ký cho `ROOM_PHONG_LAB_02` trong `infra/.env` riêng trên EC2. Quyền đọc header/registry/bản build được hạn chế; registry EC2 có quyền `600`. Backend ánh xạ mọi phòng lịch demo về beacon này, vẫn giữ tên phòng gốc trên lịch |
| Thiết bị thật | ESP32-C6 đã nạp và quảng bá BLE, tín hiệu thu trên PC khoảng −65 dBm. Chưa cài/thử APK trên điện thoại; chưa đo camera, GPS và điểm danh đầu cuối trên máy thật |

Người dùng chỉ cần APK thử nghiệm; bản profile được ký bằng Android Debug để cài thử, không phải gói phát hành. Các bài test dùng mock và mã hóa token tổng hợp, nên không thay thế thử nghiệm phần cứng. Hiện ADB không thấy điện thoại kết nối.

Bản APK profile để thử demo trên máy Android arm64: `dist/smartattendance-v1.0.13-arm64-profile-ble-c6.apk` (117.900.131 byte, SHA-256 `036a4a8d345e4d7ac687570ffe8ee7e939dd1dff68592011e451b3dc5503a01e`). File này ở máy build, không đưa vào GitHub.

## Thay đổi quan trọng

1. Bật BLE trong cấu hình build ứng dụng. Backend nhận `c6Token` thay cho thông tin phòng do client tự khai và từ chối token sai, mock, tín hiệu yếu, phòng không khớp, thời gian quét bất hợp lý. Nhiều beacon đã đăng ký trong cùng phòng đều được hỗ trợ; backend production kiểm tra registry lúc khởi động.
2. Tách khóa AES khỏi firmware công khai. Mỗi ESP32-C6 cần một `deviceId` và khóa riêng; chỉ ghi khóa vào firmware và `BLE_C6_DEVICES_JSON` bí mật trên server.
3. Không lưu token BLE thô vào JSON chứng cứ. Thêm script chuẩn bị model có kiểm tra hash và quy trình ký release.

## Điều kiện còn thiếu trước khi công bố sẵn sàng

1. Cài APK profile lên điện thoại Android arm64, thử phiên mở → nhận diện mặt → quét BLE/GPS → ghi điểm danh → xem lịch sử; thử token sửa và điểm danh trùng. ADB hiện chưa thấy điện thoại kết nối.
2. Mở một phiên mới bằng tài khoản giảng viên demo và xác minh bản ghi điểm danh mới từ điện thoại trong database sinh viên tương ứng. Chưa có lượt thử đầu cuối với bản APK và beacon mới.
3. Chế độ `BLE_DEMO_ROOM_ID` dùng một board cho mọi phòng lịch chỉ phù hợp trình diễn tại một địa điểm. Khi triển khai thật ở nhiều phòng, cần beacon riêng ở từng phòng và bỏ biến cấu hình này.

## Giới hạn bảo mật cần nói đúng

Firmware ESP32-C6 hiện chưa có thời gian tuyệt đối trong token. AES-GCM chứng minh token đến từ khóa beacon, nhưng một quảng bá hợp lệ từng thu được vẫn có thể bị chuyển tiếp. RSSI và thời gian quét do điện thoại báo cũng không chống được app bị sửa. Vì vậy BLE chỉ là một lớp tín hiệu vị trí cùng với xác minh khuôn mặt/GPS, chưa đủ để cam kết chống gian lận tuyệt đối.

## Câu trình bày ngắn

“Phần mềm đã có luồng quản lý lịch, mở phiên và ghi nhận điểm danh, xác minh khuôn mặt trên điện thoại, GPS và token BLE ESP32-C6 được API xác thực bằng AES-GCM. Board đã nạp firmware và phát token thay đổi; máy tính thu được tín hiệu thật, backend EC2 xác thực thành công và đã bật yêu cầu BLE cho demo dùng chung một beacon. Flutter và APK Android thử nghiệm đã qua kiểm thử kỹ thuật. Bước còn lại là thử toàn bộ luồng trên điện thoại thật.”
