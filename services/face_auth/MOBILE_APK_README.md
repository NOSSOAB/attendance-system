# Face Auth Android Thin Client

APK chỉ làm frontend:

```text
CameraX 640x480 -> nén JPEG -> REST API PC -> hiển thị trạng thái/điểm số
```

Không có MediaPipe, PyTorch, ONNX Runtime, InsightFace hoặc model AI trong APK.
CameraX dùng `KEEP_ONLY_LATEST`, vì vậy frame cũ tự bị bỏ khi mạng hoặc server bận.
APK chỉ giữ một frame upload đang bay. Khi API trả `429`, khoảng gửi tự tăng từ 250 ms
lên tối đa 2 giây rồi giảm dần sau các response thành công. `CookieManager` giữ cookie affinity
để một phiên không nhảy giữa các EC2 nằm sau Application Load Balancer.

## Chạy

1. Đảm bảo EC2 và container Face Auth đang chạy.
2. Cài `outputs/face-auth-ec2-test-v2.0.1.apk` và cấp quyền camera.
3. Giữ URL mặc định `http://18.143.149.146/face-api`.
4. Nhập mã truy cập API do quản trị server cấp. Bản 2.0.1 không lưu mã này trên điện thoại.
5. Bấm **Tải người**, chọn danh tính, bấm **Xác thực**.

Mỗi phiên có ba hành động ngẫu nhiên. Recognition bắt đầu sớm sau ba frame tốt và chạy
song song với liveness. Mọi request sau khi tạo phiên phải mang token ngẫu nhiên riêng của phiên.

## Thêm người

Tạo thư mục mới trong `database_faces/<ten_nguoi>/`, thêm 5-10 ảnh rồi chạy:

```powershell
python enroll_faces.py
```

Sau đó bấm lại **Tải người** trên điện thoại.

## Build lại APK

```text
build_mobile_apk.bat
```

APK test mới nhất nằm tại `outputs/face-auth-ec2-test-v2.0.1.apk`.

## Lỗi kết nối

- Mở `http://18.143.149.146/health` bằng trình duyệt điện thoại.
- Kiểm tra EC2 đang ở trạng thái `Running` và health trả HTTP 200.
- Wi-Fi của điện thoại không cần giống máy tính vì API dùng Public IP EC2.
- Nếu EC2 đã Stop/Start và không có Elastic IP, kiểm tra lại Public IPv4 rồi sửa URL trong APK.
