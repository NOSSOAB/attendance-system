# Ứng dụng sinh viên

## Cài đặt

```powershell
flutter pub get
```

## Chạy ứng dụng

```powershell
flutter run
```

Có thể đặt địa chỉ API khi chạy:

```powershell
flutter run --dart-define=API_BASE_URL=https://<máy-chủ>
```

Trước khi build Android từ bản clone mới, chạy
`python scripts/prepare_mobile_models.py`. Script sao chép Face Landmarker đã có
trong repo và tải SFace từ OpenCV Zoo, rồi kiểm tra SHA-256 của cả hai. Các file
model nằm trong Android assets và không được đưa vào Git.

## Tạo APK để cài trên điện thoại

Bản profile/release không dùng địa chỉ emulator. Script kiểm tra `/health`
trước khi build và luôn bật đúng luồng nhận diện trên máy:

```powershell
$env:FLUTTER_ROOT = 'C:\duong-dan\flutter'
.\scripts\build_mobile_apk.ps1 -ApiBaseUrl 'https://ten-may-chu-cua-ban'
```

APK bản 1.0.13 (build 14) xuất ra
`dist/smartattendance-mobile-first-v1.0.13-arm64-release.apk` tại thư mục gốc
dự án. Application ID `com.smartattendance.mobile.v2` và tên hiển thị
`Smart Attendance 2` cho phép cài song song với bản
`com.smartattendance.mobile`; mỗi bản có phiên đăng nhập và khóa Android
Keystore riêng. Nếu thiếu `API_BASE_URL`, ứng dụng production sẽ báo lỗi cấu
hình thay vì âm thầm gọi `10.0.2.2`.
