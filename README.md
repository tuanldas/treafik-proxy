# Traefik Stack

Reverse proxy **Traefik** kèm giám sát **Prometheus + Grafana**, chạy bằng Docker
Compose. `docker-compose.yml` được **sinh tự động** từ các file mô tả service và cờ
bật/tắt trong `.env` — không viết tay.

## Mục lục

- [Yêu cầu](#yêu-cầu)
- [Cài đặt nhanh](#cài-đặt-nhanh)
- [Cấu hình (.env)](#cấu-hình-env)
- [Tính năng](#tính-năng)
- [Cách hoạt động](#cách-hoạt-động)
- [Cấu trúc thư mục](#cấu-trúc-thư-mục)
- [Quản lý service](#quản-lý-service)
- [SSL / Cloudflare](#ssl--cloudflare)
- [Giám sát](#giám-sát)
- [Đổi tên network / volume](#đổi-tên-network--volume)
- [Vận hành](#vận-hành)
- [Bảo mật](#bảo-mật)
- [Xử lý sự cố](#xử-lý-sự-cố)

## Yêu cầu

- Docker + Docker Compose v2 (`docker compose`).
- `bash` và một trong `openssl` / `htpasswd` / `docker` (để hash mật khẩu dashboard).
- Domain trỏ về server (production) hoặc dùng `*.localhost` khi chạy local.

## Cài đặt nhanh

```bash
# 1. Chỉnh .env: DOMAIN, ACME_EMAIL, mật khẩu, các cờ service
# 2. Sinh compose và chạy
chmod +x setup.sh
./setup.sh --up            # = ./setup.sh && docker compose up -d
```

`setup.sh` tự tạo `acme/acme.json`, hash mật khẩu dashboard, và in danh sách host
cần trỏ DNS. Truy cập (mặc định `DOMAIN=localhost`):

- Traefik dashboard — `http(s)://traefik.localhost`
- Grafana — `http(s)://grafana.localhost`
- Prometheus — `http(s)://prometheus.localhost`

Chạy local: để `DOMAIN=localhost` (trình duyệt tự phân giải `*.localhost`). Nếu
không vào được, dùng `DOMAIN=127.0.0.1.nip.io`.

Mọi thay đổi đều theo quy trình: sửa `.env` hoặc `services/*.md` → `./setup.sh` →
`docker compose up -d`.

## Cấu hình (.env)

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `DOMAIN` | `localhost` | Domain gốc; service là `<ten>.${DOMAIN}` |
| `TZ` | `Asia/Ho_Chi_Minh` | Múi giờ |
| `PROXY_NETWORK` / `MONITORING_NETWORK` | `proxy` / `monitoring` | Tên network thật |
| `PROMETHEUS_VOLUME` / `GRAFANA_VOLUME` | `prometheus-data` / `grafana-data` | Tên volume thật |
| `TRAEFIK_VERSION` | `v3.7.5` | Phiên bản Traefik |
| `SSL` | `false` | `true`: Let's Encrypt; `false`: SSL ngoài (Cloudflare) |
| `ACME_EMAIL` | — | Email Let's Encrypt (khi `SSL=true`) |
| `TRAEFIK_DASHBOARD_USER` / `TRAEFIK_DASHBOARD_PASSWORD` | `admin` / `changeme` | Đăng nhập dashboard (mật khẩu thường, tự hash) |
| `GRAFANA` / `GRAFANA_*` | `true` | Bật Grafana + version/tài khoản |
| `PROMETHEUS` / `NODE_EXPORTER` / `CADVISOR` | `true` | Bật các service giám sát |
| `WHOAMI` | `true` | Service test |

Sau khi sửa `.env`, luôn chạy lại `./setup.sh`.

## Tính năng

- Reverse proxy tự phát hiện service qua Docker label, không cần sửa config thủ công.
- SSL Let's Encrypt tự động (HTTP challenge), bật/tắt bằng 1 cờ khi dùng Cloudflare.
- Mô hình "1 service = 1 file `.md`"; `setup.sh` ghép thành compose hoàn chỉnh.
- Bật/tắt từng service bằng cờ `true/false` trong `.env`.
- Mật khẩu dashboard nhập dạng thường, `setup.sh` tự hash.
- 3 dashboard Grafana nạp sẵn: Traefik, máy chủ (node-exporter), container (cAdvisor).

## Cách hoạt động

```
services/*.md  ──(block ```yaml)──┐
.env (cờ <TÊN>=true)              ├──►  ./setup.sh  ──►  docker-compose.yml
traefik/ prometheus/ grafana/     ┘                       (KHÔNG sửa tay)
```

`traefik` luôn được đưa vào. Service khác bật bằng cờ `<TÊN>=true`, trong đó tên cờ
là tên file viết HOA (vd `node-exporter.md` → `NODE_EXPORTER`). `setup.sh` trích
block ` ```yaml ` trong mỗi file service được bật và ghép lại.

Một file service mẫu (`services/whoami.md`):

````markdown
# Service: whoami
Mô tả tuỳ ý...

```yaml
  whoami:
    image: traefik/whoami
    networks: [proxy]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`whoami.${DOMAIN}`)"
      - "traefik.http.routers.whoami.entrypoints=websecure"
      - "traefik.http.routers.whoami.tls.certresolver=le"
      - "traefik.http.services.whoami.loadbalancer.server.port=80"
```
````

## Cấu trúc thư mục

```
proxy/
├── setup.sh                  # sinh docker-compose.yml
├── .env                      # cấu hình + cờ bật/tắt (gitignored)
├── docker-compose.yml        # SINH TỰ ĐỘNG — không sửa tay
├── CLAUDE.md                 # hướng dẫn cho AI agent
├── services/                 # mỗi service 1 file .md
│   ├── traefik.md            # bắt buộc
│   ├── grafana.md
│   ├── prometheus.md
│   ├── node-exporter.md
│   ├── cadvisor.md
│   ├── whoami.md             # service test
│   └── _template.md          # copy để tạo service mới
├── traefik/
│   ├── traefik.yml           # static config (entrypoints, ACME, metrics, provider)
│   └── dynamic/
│       ├── middlewares.yml   # security headers, rate limit, default-chain
│       └── auth.generated.yml # basic-auth dashboard (sinh, gitignored)
├── prometheus/prometheus.yml # scrape targets
├── grafana/
│   ├── provisioning/         # datasource + dashboard tự nạp
│   └── dashboards/           # traefik.json, node-exporter.json, cadvisor.json
└── acme/acme.json            # lưu chứng chỉ (sinh, gitignored)
```

## Quản lý service

Bật/tắt bằng cờ trong `.env` (`traefik` luôn bật):

| Mục đích | Cờ |
|---|---|
| Chỉ proxy + dashboard | `PROMETHEUS=false`, `GRAFANA=false`, `NODE_EXPORTER=false`, `CADVISOR=false` |
| Proxy + giám sát đầy đủ | đặt các cờ trên `=true` |

Thêm service mới:

1. `cp services/_template.md services/api.md` — sửa tên, `Host(...)`, `server.port`.
2. Thêm `API=true` vào `.env`.
3. `./setup.sh && docker compose up -d`

```bash
./setup.sh
docker compose up -d --remove-orphans   # gỡ container của service vừa tắt
```

## SSL / Cloudflare

| `SSL` | Hành vi |
|---|---|
| `true` | Traefik tự xin Let's Encrypt; router chạy `websecure`; redirect HTTP→HTTPS |
| `false` | Origin chạy HTTP; bỏ `certresolver`; tắt redirect (hợp với Cloudflare) |

Khi `SSL=false`, `setup.sh` tự chuyển router sang entrypoint `web`, xoá
`tls.certresolver`, và comment khối redirect trong `traefik.yml` — không sửa tay.
Trên Cloudflare dùng SSL mode **Flexible** (hoặc **Full** nếu muốn mã hoá tới origin).

## Giám sát

3 dashboard Grafana nạp sẵn (mở `grafana.${DOMAIN}` là có ngay). Dưới đây là mô tả
từng biểu đồ để dễ đọc số.

### Dashboard "Traefik" — lưu lượng qua proxy

| Biểu đồ | Cho biết | Đọc thế nào |
|---|---|---|
| Tổng request/s | Tổng số request mỗi giây qua tất cả entrypoint | Tăng = nhiều traffic; tụt về 0 = không có request tới |
| Tỉ lệ lỗi 5xx (%) | Phần trăm request bị lỗi server (mã 5xx) | Nên ~0%. Vàng >1%, đỏ >5% là backend đang lỗi |
| Kết nối đang mở | Số kết nối TCP Traefik đang giữ | Cao bất thường = nghẽn hoặc tấn công |
| Latency p95 (s) | 95% request nhanh hơn mức này | Càng thấp càng tốt; tăng đột biến = chậm |
| Request/s theo service | Traffic tách theo từng service | So sánh service nào đang nhận nhiều request |
| Request/s theo mã trạng thái | Traffic tách theo mã HTTP (2xx/3xx/4xx/5xx) | Nhiều 4xx = lỗi client; nhiều 5xx = lỗi server |
| Latency theo service (p50/p95/p99) | Độ trễ p50/p95/p99 của mỗi service | p99 cao = một số request rất chậm |

### Dashboard "Node / Host" — tài nguyên máy chủ (cần `NODE_EXPORTER=true`)

| Biểu đồ | Cho biết | Đọc thế nào |
|---|---|---|
| CPU sử dụng (%) | Tổng CPU đang dùng của máy | Vàng >70%, đỏ >90% là quá tải |
| RAM sử dụng (%) | Phần trăm bộ nhớ đã dùng | Vàng >75%, đỏ >90% là sắp hết RAM |
| Disk / dùng (%) | Phần trăm ổ đĩa gốc đã dùng | Đỏ >90% là sắp đầy đĩa |
| Load (1m) | Tải trung bình 1 phút | So với số core; lớn hơn số core = quá tải |
| CPU theo mode (%) | CPU chia theo user/system/iowait... | `iowait` cao = nghẽn đĩa |
| Bộ nhớ (bytes) | Tổng RAM và RAM đã dùng | Khoảng cách 2 đường = RAM còn trống |
| Network (bytes/s) | Lưu lượng vào/ra theo card mạng | Đo băng thông đang dùng |
| Disk I/O (bytes/s) | Tốc độ đọc/ghi đĩa | Cao kéo dài = đĩa là điểm nghẽn |

### Dashboard "Containers / cAdvisor" — theo container (cần `CADVISOR=true`)

| Biểu đồ | Cho biết | Đọc thế nào |
|---|---|---|
| Số container đang chạy | Tổng container đang hoạt động | Tụt giảm = có container chết |
| Tổng CPU container (cores) | Tổng CPU mọi container đang dùng | Quy ra số core |
| Tổng RAM container | Tổng RAM mọi container đang dùng | Theo dõi xu hướng tăng dần (rò rỉ) |
| CPU theo container (cores) | CPU của từng container | Tìm container "ăn" CPU |
| RAM theo container | RAM của từng container | Tìm container "ăn" RAM / rò rỉ |
| Network nhận theo container | Băng thông tải xuống mỗi container | Container nào nhận nhiều dữ liệu |
| Network gửi theo container | Băng thông tải lên mỗi container | Container nào gửi nhiều dữ liệu |

Thêm dashboard khác: bỏ file `.json` vào `grafana/dashboards/` rồi restart Grafana.
Prometheus và các exporter chỉ nằm trong network nội bộ; Prometheus có domain riêng
được bảo vệ bằng basic-auth.

## Đổi tên network / volume

Sửa `PROXY_NETWORK` / `MONITORING_NETWORK` / `PROMETHEUS_VOLUME` / `GRAFANA_VOLUME`
trong `.env`. Alias nội bộ trong compose giữ nguyên, chỉ tên Docker thật đổi;
`setup.sh` tự đồng bộ tên network proxy vào `traefik.yml`. Đổi `*_VOLUME` sẽ trỏ
sang volume mới (dữ liệu cũ vẫn còn nhưng không dùng).

## Vận hành

```bash
./setup.sh                       # sinh lại compose sau khi đổi .env / services
docker compose up -d             # khởi động
docker compose down              # dừng
docker compose ps                # trạng thái
docker compose logs -f traefik   # log
docker compose config            # kiểm tra cú pháp compose đã sinh
```

## Bảo mật

- [ ] Đổi `TRAEFIK_DASHBOARD_PASSWORD` và `GRAFANA_PASSWORD` trong `.env`.
- [ ] Không commit `.env`, `acme/`, `docker-compose.yml`, `auth.generated.yml`
      (đã có trong `.gitignore`).
- [ ] Chỉ mở cổng 80/443 ra ngoài; giữ Prometheus/exporter trong network nội bộ.
- [ ] Khi test SSL, cân nhắc dùng Let's Encrypt staging để tránh bị giới hạn.

## Xử lý sự cố

- **Dashboard "No data"**: đợi 30–60s để Prometheus scrape lần đầu.
- **`*.localhost` không vào được**: đổi `DOMAIN=127.0.0.1.nip.io`, chạy lại `setup.sh`.
- **node-exporter lỗi "not a shared or slave mount"**: dùng `- /:/host:ro` (đã cấu
  hình sẵn), không dùng `ro,rslave` trên Docker Desktop.
- **cadvisor "image not found"**: trên `gcr.io` tag cao nhất là `v0.55.1`; bản mới
  hơn ở `ghcr.io/google/cadvisor`.
- **Trên macOS/Windows (Docker Desktop)**: một số metric đĩa/container có thể thiếu
  do chạy trong VM — bình thường, không phải lỗi cấu hình.

---

Chi tiết kiến trúc & quy ước cho AI agent: xem [CLAUDE.md](CLAUDE.md).
