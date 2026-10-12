# Ký APK/AAB release

Không dùng debug keystore để phát hành. Tạo một keystore riêng ở máy build,
giữ bản sao an toàn và tuyệt đối không đưa file keystore hoặc
`android/key.properties` vào Git.

```powershell
keytool -genkeypair -v -keystore ..\keys\smartattendance-release.jks `
  -alias smartattendance -keyalg RSA -keysize 4096 -validity 9125
Copy-Item key.properties.example key.properties
```

Điền bốn giá trị thật vào `key.properties`, rồi build với API HTTPS:

```powershell
flutter build appbundle --release `
  --target-platform android-arm64 `
  --dart-define=MOBILE_FACE_AUTH=true `
  --dart-define=BLE_ATTENDANCE_ENABLED=true `
  --dart-define=API_BASE_URL=https://attendance.example.edu.vn
```

Build release sẽ dừng ngay nếu thiếu thông tin ký. Luồng mobile-first dùng
Android Keystore và không cần cấu hình Google Cloud hay Play Integrity.
