# 09. Triển khai hệ thống

[← Mục lục](README.md)

```mermaid
flowchart LR
  subgraph users[Thiết bị người dùng]
    android[APK Flutter Android<br/>sinh viên và giảng viên]
  end
  subgraph physical[Thiết bị trong lớp]
    board[ESP32-C6<br/>firmware BLE và khóa riêng]
  end
  subgraph aws[AWS EC2 - Docker Compose production]
    caddy[Caddy: cổng 80 / 443<br/>HTTPS công khai]
    backend[NestJS backend<br/>API nội bộ :3000]
    migration[Migration Prisma<br/>chạy trước backend]
    postgres[(PostgreSQL 16<br/>volume lưu dữ liệu)]
    legacy[Face Auth Python<br/>profile legacy-face tùy chọn]
    caddy --> backend
    backend --> postgres
    migration --> postgres
    legacy -.-> postgres
  end
  board -->|BLE, không qua Internet| android
  android -->|HTTPS| caddy
  caddy -.->|Chỉ khi bật nhánh cũ| legacy
  classDef mobile fill:#dbeafe,stroke:#2563eb,color:#172554
  classDef device fill:#fef3c7,stroke:#d97706,color:#78350f
  classDef server fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef data fill:#f3e8ff,stroke:#9333ea,color:#581c87
  class android mobile
  class board device
  class caddy,backend,migration,legacy server
  class postgres data
```

**Triển khai hiện tại:** APK profile arm64 thử nghiệm có cờ mobile-face và BLE đã build; board thật đã nạp firmware; trên EC2, Caddy, NestJS và PostgreSQL đã chạy khỏe theo báo cáo ngày 13/10. `migration` là tác vụ chuẩn bị database, không phải API lâu dài. Caddy nhận HTTPS, các container ứng dụng và database nằm trên mạng Docker nội bộ.

**Chưa xác nhận:** APK chưa được cài và thử luồng đầy đủ trên điện thoại Android thật. Bản profile được ký bằng Android Debug để thử, chưa phải bản phát hành. `face-auth` là container tùy chọn của nhánh cũ, không thuộc stack mobile-first mặc định.

Đối chiếu: [`compose.production.yaml`](../../infra/compose.production.yaml), [`Caddyfile`](../../infra/caddy/Caddyfile), [runbook EC2](../MOBILE_FIRST_EC2_RUNBOOK.md), [báo cáo rà soát](../ATTENDANCE_REVIEW_2026-10-13.md).
