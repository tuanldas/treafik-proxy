# CLAUDE.md

Hướng dẫn cho AI agent (Claude Code...) khi làm việc trong repo này.

## Tổng quan

Stack reverse proxy **Traefik** + giám sát **Prometheus/Grafana** chạy bằng Docker
Compose. Điểm đặc biệt: `docker-compose.yml` **không viết tay** mà được **sinh tự
động** từ các file mô tả service, dựa trên cờ bật/tắt trong `.env`.

## Kiến trúc & luồng sinh file

```
services/*.md  ──(block ```yaml)──┐
.env (cờ <TÊN>=true/bool)         ├──►  ./setup.sh  ──►  docker-compose.yml
traefik/, prometheus/, grafana/   ┘                        (KHÔNG sửa tay)
```

- Mỗi service = 1 file `services/<ten>.md`, chứa mô tả + **đúng 1 block** ` ```yaml `
  là fragment compose, thụt lề 2 dấu cách (để nằm dưới `services:`).
- `setup.sh` đọc `.env`, trích block yaml của các service được bật, ghép thành
  `docker-compose.yml` + header (networks/volumes).
- `traefik` luôn được đưa vào (bắt buộc). Service khác bật bằng cờ `<TÊN>=true`,
  tên cờ = tên file viết HOA, ký tự không alphanumeric → `_`
  (vd `node-exporter.md` → `NODE_EXPORTER`).

## Quy tắc QUAN TRỌNG

- **KHÔNG sửa `docker-compose.yml` trực tiếp** — nó là file sinh ra, mọi thay đổi
  sẽ bị ghi đè. Sửa ở `services/*.md` hoặc `.env` rồi chạy `./setup.sh`.
- **KHÔNG hardcode bí mật.** Mật khẩu/cấu hình lấy từ `.env`. Các file sinh tự động
  (`docker-compose.yml`, `traefik/dynamic/auth.generated.yml`, `acme/acme.json`) đã
  nằm trong `.gitignore`.
- Mỗi `services/*.md` chỉ chứa **một** block ```yaml. File bắt đầu bằng `_`
  (vd `_template.md`) bị `setup.sh` bỏ qua.
- Service muốn được Traefik định tuyến phải nằm trong network `proxy` và có label
  `traefik.enable=true` + router rule/entrypoint/service.

## Lệnh thường dùng

```bash
./setup.sh                 # sinh lại docker-compose.yml từ .env + services/
./setup.sh --up            # sinh xong chạy docker compose up -d luôn
docker compose up -d       # khởi động
docker compose down        # dừng & xoá container/network
docker compose logs -f traefik
docker compose ps
```

## `setup.sh` làm gì (tóm tắt)

1. Tạo `acme/acme.json` (quyền 600) nếu chưa có.
2. Hash `TRAEFIK_DASHBOARD_PASSWORD` → sinh `traefik/dynamic/auth.generated.yml`
   (thử `openssl` → `htpasswd` → `docker`).
3. Theo cờ `SSL`: nếu `false` thì chuyển router sang entrypoint `web`, bỏ
   `tls.certresolver`, và comment khối redirect trong `traefik.yml`
   (giữa mốc `# >>> SSL_REDIRECT` / `# <<< SSL_REDIRECT`).
4. Đồng bộ tên network proxy (`PROXY_NETWORK`) vào `traefik.yml` (dòng có
   `# PROXY_NET`), vì static config không đọc được `.env`.
5. Ghép header + service được bật → `docker-compose.yml`, rồi in danh sách host
   cần trỏ DNS.

## Thêm một service mới

1. `cp services/_template.md services/<ten>.md`, sửa tên/`Host(...)`/`server.port`.
2. Thêm cờ `<TÊN>=true` (+ biến version nếu cần) vào `.env`.
3. `./setup.sh && docker compose up -d`.

## Cấu trúc thư mục

```
proxy/
├── setup.sh                 # bộ sinh docker-compose.yml
├── .env                     # cấu hình + cờ bật/tắt (gitignored)
├── docker-compose.yml       # SINH TỰ ĐỘNG
├── CLAUDE.md / README.md
├── services/                # mỗi service 1 file .md (+ _template.md)
├── traefik/
│   ├── traefik.yml          # static config (entrypoints, ACME, metrics, provider)
│   └── dynamic/             # middlewares.yml + auth.generated.yml (sinh)
├── prometheus/prometheus.yml
├── grafana/{provisioning,dashboards}/   # datasource + 3 dashboard nạp sẵn
└── acme/                    # acme.json (gitignored, setup tạo)
```

## Lưu ý môi trường

- `node-exporter`/`cadvisor` viết cho host Linux. Trên Docker Desktop (macOS/Windows)
  một số metric đĩa/container có thể thiếu — không phải lỗi cấu hình.
- node-exporter dùng `- /:/host:ro` (KHÔNG `ro,rslave`) để chạy được trên Docker
  Desktop.
- cAdvisor: trên `gcr.io` tag cao nhất là `v0.55.1`; bản mới hơn ở `ghcr.io`.
