# 06. Hoạt động của máy chủ EC2

[← Mục lục](README.md)

```mermaid
flowchart TD
  request[HTTPS từ sinh viên / giảng viên] --> caddy[Caddy chuyển tiếp tới NestJS]
  caddy --> auth[JWT + quyền sinh viên / giảng viên]
  auth --> route{Loại yêu cầu}
  route -- Phiên mặt --> face[Kiểm ticket, chữ ký P-256,<br/>thử thách và độ giống SFace]
  route -- Điểm danh --> scan[Kiểm phiên mở, sinh viên thuộc lớp,<br/>điểm danh trùng]
  scan --> evidence[Kiểm mã phiên mặt, BLE AES-GCM,<br/>GPS và ngưỡng đi muộn]
  route -- Giảng viên --> manage[Mở / lưu / đóng phiên,<br/>lịch sử, thống kê, xuất bảng]
  face --> prisma[Prisma]
  evidence --> prisma
  manage --> prisma
  prisma --> db[(PostgreSQL)]
  db --> response[Trả kết quả cho ứng dụng]
  classDef mobile fill:#dbeafe,stroke:#2563eb,color:#172554
  classDef server fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef data fill:#f3e8ff,stroke:#9333ea,color:#581c87
  class request,response mobile
  class caddy,auth,route,face,scan,evidence,manage,prisma server
  class db data
```

**API hiện tại:** `POST /auth/login` cấp phiên đăng nhập; các route sinh viên/giảng viên dùng JWT và quyền. Xác minh mặt mới dùng `POST /students/attendance/mobile-face-session`, `/complete`; lượt điểm danh cuối dùng `POST /students/attendance/scan`. Prisma chọn database chung cho mẫu mặt và database theo trường/vai trò cho dữ liệu học tập/điểm danh. Cùng một PostgreSQL container có nhiều database trong cấu hình production.

**Kết quả:** API ghi `AttendanceRecord` đạt, đi muộn hoặc cần xem lại; chặn phiên đóng và lượt thành công trùng. Face Auth Python/ArcFace chỉ nằm trong profile Compose `legacy-face`, không chạy khi khởi động lệnh mobile-first không kèm profile. Các route `/face-api` trong Caddy còn để phục vụ nhánh cũ khi được bật.

Đối chiếu: [`auth.controller.ts`](../../apps/backend/src/modules/auth/auth.controller.ts), [`students.service.ts`](../../apps/backend/src/modules/students/students.service.ts), [`lecturers.controller.ts`](../../apps/backend/src/modules/lecturers/lecturers.controller.ts), [`prisma-tenant.service.ts`](../../apps/backend/src/database/prisma/prisma-tenant.service.ts), [`compose.production.yaml`](../../infra/compose.production.yaml).
