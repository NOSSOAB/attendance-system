# 03. Luồng điểm danh của sinh viên

[← Mục lục](README.md)

```mermaid
flowchart TD
  login[Đăng nhập và xem lịch học] --> open{Phiên điểm danh đang mở?}
  open -- Không --> stop[Thông báo chưa thể điểm danh]
  open -- Có --> ble[Quét BLE ESP32-C6 trước]
  ble --> bleOk{Có tín hiệu phù hợp?}
  bleOk -- Không --> retry[Thông báo lỗi; có thể thử lại]
  bleOk -- Có --> ticket[API cấp ticket khuôn mặt 90 giây]
  ticket --> face[Camera: một mặt, làm thử thách sống,<br/>tạo vector và ký trên Android]
  face --> faceOk{API xác minh mặt đạt?}
  faceOk -- Không --> retry
  faceOk -- Có --> gps[Lấy GPS sau xác minh mặt]
  gps --> gpsOk{Có vị trí hợp lệ?}
  gpsOk -- Không --> retry
  gpsOk -- Có --> submit[Gửi mã phiên mặt + BLE + GPS<br/>tới POST /students/attendance/scan]
  submit --> decide{API xét phiên, trùng,<br/>BLE, GPS và mặt}
  decide -- Đạt --> saved[(Ghi AttendanceRecord:<br/>có mặt hoặc đi muộn)]
  decide -- Chứng cứ lỗi --> flagged[(Ghi cần xem lại;<br/>cho phép thử lại)]
  decide -- Đã điểm danh / hết phiên --> rejected[Từ chối, không ghi lượt thành công mới]
  saved --> result[Trả kết quả và tải lại lịch]
  flagged --> result
  rejected --> result
  classDef mobile fill:#dbeafe,stroke:#2563eb,color:#172554
  classDef server fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef data fill:#f3e8ff,stroke:#9333ea,color:#581c87
  class login,ble,face,gps,retry,stop,result mobile
  class open,bleOk,ticket,faceOk,gpsOk,submit,decide,rejected server
  class saved,flagged data
```

**Thứ tự theo mã Flutter:** quét BLE → màn hình xác minh mặt → lấy GPS → gửi lượt điểm danh. Ticket mặt được xin khi màn hình camera mở. API `/scan` kiểm điều kiện rồi ghi `AttendanceRecord`. Bản ghi đạt là `present` hoặc `late`; chứng cứ lỗi có thể thành `flagged`/`needs_review`; phiên đóng và điểm danh trùng bị từ chối.

**Lưu ý:** đăng nhập, xem lịch và mở phiên dùng các API khác nhau. Hình trên mô tả build bật cả `MOBILE_FACE_AUTH` và `BLE_ATTENDANCE_ENABLED`; chưa có lượt xác nhận đầu cuối trên điện thoại thật.

Đối chiếu: [`student_home_screen.dart`](../../apps/frontend_student/lib/features/student_home/student_home_screen.dart), [`students.controller.ts`](../../apps/backend/src/modules/students/students.controller.ts), [`students.service.ts`](../../apps/backend/src/modules/students/students.service.ts).
