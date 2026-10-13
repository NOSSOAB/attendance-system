# 01. Kiến trúc tổng thể

[← Mục lục](README.md)

```mermaid
flowchart LR
  subgraph phone[Điện thoại Android]
    sv[Sinh viên] --> flutter[Ứng dụng Flutter]
    gv[Giảng viên] --> lecturer[Giao diện giảng viên Flutter]
    flutter --> camera[Camera + MediaPipe<br/>+ SFace qua ONNX Runtime]
    flutter --> gps[Geolocator: GPS]
    flutter --> scanner[FlutterBluePlus: BLE]
    camera --> keystore[Android Keystore: ký chứng cứ]
  end
  subgraph classroom[Trong phòng học]
    esp[ESP32-C6<br/>token AES-GCM]
  end
  subgraph cloud[AWS EC2 - cấu hình production]
    caddy[Caddy: HTTPS] --> nest[NestJS: xác thực<br/>và nghiệp vụ điểm danh]
    nest --> prisma[Prisma]
    prisma --> postgres[(PostgreSQL<br/>dữ liệu chung và theo trường/vai trò)]
  end
  esp -->|Quảng bá BLE| scanner
  flutter -->|HTTPS: ticket, vector + chữ ký,<br/>GPS + token BLE| caddy
  lecturer -->|HTTPS: lịch, phiên, kết quả| caddy
  classDef mobile fill:#dbeafe,stroke:#2563eb,color:#172554
  classDef device fill:#fef3c7,stroke:#d97706,color:#78350f
  classDef server fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef data fill:#f3e8ff,stroke:#9333ea,color:#581c87
  class sv,gv,flutter,lecturer,camera,gps,scanner,keystore mobile
  class esp device
  class caddy,nest,prisma server
  class postgres data
```

**Ý chính:** ảnh camera được xử lý trên Android ở luồng mobile-first. API nhận vector khuôn mặt và chữ ký để đối chiếu mẫu đã lưu, rồi xét GPS, BLE và phiên điểm danh. Cùng ứng dụng Flutter có màn hình sinh viên và giảng viên; `apps/frontend_teacher/` chỉ chứa các bản thiết kế HTML/ảnh, không phải ứng dụng chạy riêng.

**Tình trạng:** đây là kiến trúc được cấu hình cho demo hiện tại. Đường điểm danh đầy đủ trên điện thoại thật còn chờ kiểm thử. Dịch vụ Python Face Auth là nhánh cũ tùy chọn, xem [mô hình 02](02-kien-truc-cu-va-moi.md).

Đối chiếu: [`student_home_screen.dart`](../../apps/frontend_student/lib/features/student_home/student_home_screen.dart), [`MainActivity.kt`](../../apps/frontend_student/android/app/src/main/kotlin/com/example/frontend_student/MainActivity.kt), [`compose.production.yaml`](../../infra/compose.production.yaml), [`prisma-tenant.service.ts`](../../apps/backend/src/database/prisma/prisma-tenant.service.ts).
