# 04. Xử lý khuôn mặt trên điện thoại

[← Mục lục](README.md)

## Khi điểm danh

```mermaid
flowchart TD
  start[API cấp ticket: mã phiên, nonce,<br/>model và thứ tự thử thách] --> camera[Flutter Camera lấy khung hình]
  camera --> landmark[Android: MediaPipe Face Landmarker<br/>kiểm một mặt, vị trí, chớp mắt, cười, quay đầu]
  landmark --> alive{Hoàn thành thử thách<br/>theo thứ tự ngẫu nhiên?}
  alive -- Không --> fail[Thử lại hoặc báo lỗi]
  alive -- Có --> align[Căn chỉnh mặt 112 × 112<br/>bằng điểm mốc]
  align --> sface[OpenCV SFace ONNX<br/>tạo vector chuẩn hóa 128 số]
  sface --> sign[Android Keystore ký nonce +<br/>vector + bằng chứng thử thách]
  sign --> send[HTTPS: gửi vector, chữ ký,<br/>khóa công khai, chứng cứ sống]
  send --> api[NestJS: kiểm ticket một lần,<br/>thứ tự thử thách và chữ ký P-256]
  api --> compare[So vector với mẫu SFace<br/>trong MobileFaceIdentity]
  compare --> verdict{Độ giống đạt ngưỡng?}
  verdict -- Có --> verified[Trả mã phiên mặt đã xác minh]
  verdict -- Không --> fail
  classDef mobile fill:#dbeafe,stroke:#2563eb,color:#172554
  classDef server fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef data fill:#f3e8ff,stroke:#9333ea,color:#581c87
  class camera,landmark,alive,align,sface,sign,fail mobile
  class start,send,api,compare,verdict,verified server
```

**Dữ liệu gửi lên:** vector 128 số đã chuẩn hóa, mã phiên, nonce, khóa công khai, chữ ký số và số đo thử thách sống. **Ảnh camera/khung hình không gửi lên EC2 trong luồng mới.** Chữ ký và nonce chỉ bảo vệ gói chứng cứ; backend vẫn so vector với mẫu SFace. Khóa bí mật ở Android Keystore không rời điện thoại. Lần khớp thành công đầu tiên có thể gắn khóa công khai của máy với sinh viên; các lần sau phải dùng khóa đang hoạt động.

## Chuẩn bị mẫu trước buổi điểm danh

```mermaid
flowchart LR
  photos[2–5 ảnh hồ sơ đã được cấp] --> tool[Công cụ SFace ngoại tuyến<br/>tạo các vector]
  tool --> mean[Trung bình và chuẩn hóa]
  mean --> import[Nhập mẫu vào PostgreSQL]
  import --> identity[(MobileFaceIdentity)]
  classDef source fill:#dbeafe,stroke:#2563eb,color:#172554
  classDef server fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef data fill:#f3e8ff,stroke:#9333ea,color:#581c87
  class photos source
  class tool,mean,import server
  class identity data
```

Mẫu SFace được tạo **trước** buổi học từ ảnh hồ sơ bằng công cụ chuẩn bị và nhập vào `MobileFaceIdentity`. Camera khi điểm danh không tự thay mẫu. Mã còn có API đăng ký đáng tin cậy qua xác minh ArcFace cũ; quy trình vận hành mobile-first hiện mô tả cách nhập mẫu ngoại tuyến. Không đưa ảnh hồ sơ vào repository.

**Giới hạn:** kiểm tra sống dựa trên số đo MediaPipe và chứng cứ do ứng dụng gửi; chưa có kiểm thử chống giả mạo đầu cuối trên máy thật. Xem [báo cáo rà soát](../ATTENDANCE_REVIEW_2026-10-13.md).

Đối chiếu: [`MainActivity.kt`](../../apps/frontend_student/android/app/src/main/kotlin/com/example/frontend_student/MainActivity.kt), [`mobile_face_verification_screen.dart`](../../apps/frontend_student/lib/features/face_verification/mobile_face_verification_screen.dart), [`mobile-face-auth.service.ts`](../../apps/backend/src/modules/students/mobile-face-auth.service.ts), [`build_mobile_face_reference.py`](../../services/face_auth/tools/build_mobile_face_reference.py).
