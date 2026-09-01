# Nhập dữ liệu EDU_NUCE

Công cụ này đọc dữ liệu từ SQL Server và ghi vào các database PostgreSQL đã cấu hình.

## Chuẩn bị

1. Khôi phục database nguồn ở chế độ chỉ đọc.
2. Tạo file mapping khoa dạng JSON.
3. Khai báo các biến database trong `.env`.

## Kiểm tra trước khi ghi

```powershell
npm run etl:edu-nuce -- --term-id=<mã-kỳ> --active-registration-statuses=1,2,3 --faculty-map-json=C:\secure\faculty-map.json
```

## Ghi dữ liệu vào database cục bộ

```powershell
npm run etl:edu-nuce -- --apply --term-id=<mã-kỳ> --active-registration-statuses=1,2,3 --faculty-map-json=C:\secure\faculty-map.json --confirm=<mã-xác-nhận>
```

Không ghi mật khẩu, tài khoản ngân hàng, số căn cước, ảnh khuôn mặt hoặc chuỗi
kết nối database vào lệnh hay GitHub.
