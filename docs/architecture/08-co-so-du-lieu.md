# 08. Cơ sở dữ liệu

[← Mục lục](README.md)

```mermaid
flowchart LR
  subgraph school[Dữ liệu lớp học và tài khoản]
    student[(Student)] --> account[(StudentAccount)]
    lecturer[(Lecturer)] --> lecturerAccount[(LecturerAccount)]
    studentClass[(StudentClass)] --> student
    course[(Course)] --> offering[(CourseOffering)]
    studentClass --> offering
    offering --> enroll[(CourseOfferingEnrollment)]
    student --> enroll
  end
  subgraph attendance[Lịch và điểm danh]
    course --> schedule[(Schedule)]
    studentClass --> schedule
    lecturer --> schedule
    offering --> schedule
    schedule --> session[(AttendanceSession)]
    session --> record[(AttendanceRecord)]
    student --> record
  end
  subgraph face[Mẫu và chứng cứ mặt]
    mobile[(MobileFaceIdentity)]
    key[(MobileFaceDeviceKey)]
    ticket[(MobileFaceSession)]
    old[(FaceIdentity - ArcFace cũ)]
  end
  student -.->|identityKey; không có khóa ngoại| mobile
  student -.->|identityKey; không có khóa ngoại| key
  session -.->|attendanceSessionId; không có khóa ngoại| ticket
  classDef data fill:#f3e8ff,stroke:#9333ea,color:#581c87
  class student,account,lecturer,lecturerAccount,studentClass,course,offering,enroll,schedule,session,record,mobile,key,ticket,old data
```

**Quan hệ có khóa ngoại trong Prisma:** lớp → sinh viên; môn/lớp → học phần; học phần + sinh viên → đăng ký; lịch → phiên; phiên + sinh viên → bản ghi. `AttendanceRecord` có ràng buộc duy nhất `(sessionId, studentId)` để không tạo hai bản ghi cho cùng một sinh viên trong một phiên.

**Liên hệ bằng giá trị, không phải khóa ngoại:** ba bảng mobile dùng `identityKey` hoặc `attendanceSessionId` để gắn với sinh viên/phiên. `MobileFaceIdentity` lưu vector mẫu trung bình; `MobileFaceDeviceKey` lưu **khóa công khai**; `MobileFaceSession` lưu thử thách, trạng thái dùng một lần và kết quả kiểm. `FaceIdentity` là mẫu ArcFace của nhánh cũ. Đường chấm trong sơ đồ biểu thị liên hệ logic, không phải ràng buộc Prisma.

**Vị trí dữ liệu:** cấu hình production có một PostgreSQL container nhưng nhiều database: `attendance_db` cho mẫu mặt/trung tâm và các database sinh viên, giảng viên theo trường HUCE/HUST. Cùng một `schema.prisma` được migration vào các database; sơ đồ trên là mô hình bảng, không có nghĩa mọi bảng đều chứa dữ liệu ở mọi database.

Đối chiếu: [`schema.prisma`](../../apps/backend/prisma/schema.prisma), [`prisma-tenant.service.ts`](../../apps/backend/src/database/prisma/prisma-tenant.service.ts), [`compose.production.yaml`](../../infra/compose.production.yaml).
