# 10. Công nghệ đang sử dụng

[← Mục lục](README.md)

```mermaid
flowchart LR
  system[SmartAttendance] --> ui[Giao diện<br/>Flutter: màn hình sinh viên và giảng viên]
  system --> vision[Nhận diện trên Android<br/>MediaPipe: điểm mốc, thử thách sống<br/>SFace ONNX: vector khuôn mặt]
  system --> security[Bảo mật<br/>Android Keystore + ECDSA P-256: ký<br/>JWT: xác thực API]
  system --> location[Kết nối và vị trí<br/>ESP32-C6 + BLE: tín hiệu phòng<br/>Geolocator: GPS]
  system --> server[Máy chủ<br/>NestJS: nghiệp vụ và kiểm chứng<br/>Caddy: HTTPS]
  system --> data[Dữ liệu<br/>Prisma: truy vấn<br/>PostgreSQL: lưu trữ]
  system --> deploy[Triển khai<br/>Docker Compose: chạy container<br/>AWS EC2: máy chủ]
  classDef mobile fill:#dbeafe,stroke:#2563eb,color:#172554
  classDef device fill:#fef3c7,stroke:#d97706,color:#78350f
  classDef server fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef db fill:#f3e8ff,stroke:#9333ea,color:#581c87
  class ui,vision,security mobile
  class location device
  class system,server,deploy server
  class data db
```

| Nhóm | Dùng để làm gì? | Vị trí |
| --- | --- | --- |
| Flutter + Camera | Hiện giao diện, thu hình khi xác minh mặt | Điện thoại Android |
| MediaPipe Face Landmarker | Tìm điểm mốc mặt; hỗ trợ kiểm chớp mắt, cười, quay đầu | Điện thoại Android |
| OpenCV SFace + ONNX Runtime | Tạo vector khuôn mặt 128 số để so sánh | Điện thoại; công cụ chuẩn bị mẫu ngoại tuyến |
| Android Keystore + ECDSA P-256 | Giữ khóa bí mật trong thiết bị, ký chứng cứ mặt | Điện thoại; NestJS kiểm chữ ký |
| FlutterBluePlus + ESP32-C6 | Thu token BLE do board trong phòng phát | Điện thoại và board |
| AES-128-GCM | Xác thực token BLE bằng khóa riêng của từng board | Firmware và NestJS |
| Geolocator | Lấy tọa độ, độ chính xác và thời điểm GPS | Điện thoại |
| NestJS + JWT | Xử lý API, đăng nhập, quyền và quyết định điểm danh | EC2 |
| Prisma + PostgreSQL | Đọc/ghi lịch, phiên, bản ghi và mẫu mặt | EC2 |
| Caddy + Docker Compose + AWS EC2 | HTTPS và vận hành các container | EC2 |

**Nhánh cũ:** Python Face Auth dùng ArcFace để xử lý ảnh trên máy chủ nếu chủ động bật profile `legacy-face`. Không trộn nó vào đường xử lý mặt mobile-first.

Đối chiếu: [`pubspec.yaml`](../../apps/frontend_student/pubspec.yaml), [`build.gradle.kts`](../../apps/frontend_student/android/app/build.gradle.kts), [`package.json`](../../apps/backend/package.json), [`compose.production.yaml`](../../infra/compose.production.yaml), [`SecureAttendance_C6.ino`](../../firmware/esp32-c6/SecureAttendance_C6.ino).
