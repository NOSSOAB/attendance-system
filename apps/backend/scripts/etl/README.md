# EDU_NUCE import CLI

CLI nay doc SQL Server `EDU_NUCE_IMPORT_20241108` va upsert du lieu HUCE vao ba PostgreSQL target. Mac dinh luon la dry-run. Script khong doc cac cot mat khau/tai khoan/ngan hang/can cuoc, khong tao hoac cap nhat `StudentAccount`/`LecturerAccount`, va khong xoa/truncate du lieu ung dung. Ngay sinh/email/so dien thoai cung khong duoc SELECT mac dinh; chi doc khi operator them `--include-birth-dates` hoac `--include-contact-fields`.

## Chuan bi

- Restore backup bang SQL Server 2022 tro len.
- Chay migration hien tai tren cac PostgreSQL local target truoc khi preflight.
- Windows Authentication: dat `EDU_NUCE_SQLSERVER_TRUSTED=true`. Package native `msnodesqlv8` la optional dependency va chi duoc lazy-load o che do nay; may Windows can Microsoft ODBC Driver for SQL Server.
- SQL login: dat trusted false va cung cap `EDU_NUCE_SQLSERVER_USER`/`EDU_NUCE_SQLSERVER_PASSWORD` qua environment. Khong dua gia tri vao lenh hay commit.
- CLI kiem tra dung database va effective permission. Neu database van READ_WRITE va Windows principal co quyen ghi, mac dinh se abort. Uu tien dat database/principal read-only; `--allow-writable-source-principal` chi la acknowledgement ro rang cho ban restore local, trong khi query allowlist cua CLI van chi cho phep cac cau `SELECT` co cot liet ke.
- Cung cap JSON mapping khoa vi backup khong co database `HRM_NUCE`. Dinh dang:

```json
{
  "<source IDKhoa>": {
    "code": "<ma khoa target>",
    "name": "<ten khoa chinh thuc>"
  }
}
```

Neu mapping chua co, CLI se abort. `--allow-placeholder-faculties` la override ro rang de tao ma `SRC-FAC-*`, co the doi sang mapping chinh thuc trong lan upsert sau. Khong dung override nay cho production neu chua duoc duyet.

## Dry-run

```powershell
npm run etl:edu-nuce -- --term-id=295 --active-registration-statuses=1,2,3 --faculty-map-json=C:\secure\huce-faculties.json --allow-writable-source-principal
```

Trang thai dang ky bat buoc khai bao ro. CLI xep hang lich su tung cap `(IDSinhVien, IDLopHocPhan)` theo `NgayCapNhat/NgayTao/NgayDangKy`, roi `Id`; chi trang thai cua ban ghi moi nhat moi duoc so voi tap active. Output chi gom count, ma issue va trang thai preflight, khong in record/PII/connection string. Neu chua cau hinh target URL, dry-run van chay source/transform va ghi `skipped_not_configured` cho target preflight.

## Apply local

Dat database SQL Server restore sang `READ_ONLY`, xem count/hash/confirmation cua dry-run, roi dung nguyen confirmation va minimum da review. Vi du (gia tri confirmation chi la placeholder):

```powershell
npm run etl:edu-nuce -- --apply --term-id=295 --active-registration-statuses=1,2,3 --faculty-map-json=C:\secure\huce-faculties.json --minimum-active-registrations=150000 --confirm=HUCE:295:4688:156829:41106:<hash-prefix>
```

Remote apply bi fail-closed cho den khi co atomic publish barrier. Remote dry-run/preflight bat buoc dung dung mot `sslmode=verify-full`; query parameter override/duplicate bi reject va TLS thuc te duoc kiem tra sau connect. `DATABASE_URL`, `HUCE_STUDENT_DATABASE_URL`, va `HUCE_LECTURER_DATABASE_URL` phai la ba database rieng; runtime identity va scope marker duoc kiem tra, bat ky alias voi HUST se abort. Local apply chay transaction serializable/checkpoint tung target; neu target sau loi, rerun cung snapshot idempotently. Checkpoint drop qua 20% mac dinh se abort; co the ha nguong bang `--max-snapshot-drop-ratio`.

Course khong map duoc mac dinh la fatal. `--allow-course-quarantine` bo qua offering/course orphan va bao count; khong nen dung neu chua xem preflight. Offering status `5` (huy lop), ky khong active/visible, lich tam ngung, lich thieu phong, hoac lich khong co giang vien thuc te deu duoc giu provenance nhung `isActive=false`. Giang vien du kien duoc giu voi role `planned`, khong duoc cap quyen so huu lich active.

ETL giu nguyen account test va moi du lieu app-native nhu face identity, attendance, notification, announcement. Sinh vien/giang vien moi khong co account dang nhap; provisioning account phai la workflow rieng co phe duyet.
