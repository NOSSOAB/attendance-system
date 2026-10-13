# 07. Luồng giảng viên quản lý điểm danh

[← Mục lục](README.md)

```mermaid
flowchart TD
  login[Giảng viên đăng nhập Flutter] --> classes[Xem lịch dạy và lớp phụ trách]
  classes --> detail[Xem chi tiết lớp và danh sách sinh viên]
  detail --> create[Tạo phiên điểm danh cho lịch học]
  create --> open[API mở phiên, đặt giờ kết thúc,<br/>ngưỡng đi muộn và BLE phòng]
  open --> notify[Thông báo tới sinh viên]
  notify --> observe[Theo dõi danh sách và kết quả quét]
  observe --> edit{Cần chỉnh bản ghi?}
  edit -- Có --> draft[Giảng viên sửa trạng thái / ghi chú]
  draft --> save[API lưu và đóng phiên]
  edit -- Không --> save
  save --> reports[Xem lịch sử, thống kê<br/>và xuất tệp XLSX]
  classDef mobile fill:#dbeafe,stroke:#2563eb,color:#172554
  classDef server fill:#dcfce7,stroke:#16a34a,color:#14532d
  class login,classes,detail,observe,edit,draft,reports mobile
  class create,open,notify,save server
```

**Trong mã:** giao diện giảng viên nằm trong cùng ứng dụng Flutter. API có xem lớp, tạo phiên, lưu bản ghi, lịch sử, thống kê và xuất XLSX. Khi tạo phiên, backend kiểm lịch/lớp, đặt điều kiện BLE và tạo thông báo. Thao tác `save` vừa lưu các sửa đổi vừa đóng phiên; không có API “đóng riêng” trong controller. Phiên quá giờ cũng có thể được đồng bộ sang trạng thái đóng ở backend.

**Lưu ý:** thư mục `apps/frontend_teacher/` chứa mockup HTML và ảnh giao diện, không phải ứng dụng giảng viên chạy độc lập. Luồng thực tế là `lecturer_home_screen.dart` gọi `LecturersController`.

Đối chiếu: [`lecturer_home_screen.dart`](../../apps/frontend_student/lib/features/lecturer_home/lecturer_home_screen.dart), [`lecturers.controller.ts`](../../apps/backend/src/modules/lecturers/lecturers.controller.ts), [`lecturers.service.ts`](../../apps/backend/src/modules/lecturers/lecturers.service.ts).
