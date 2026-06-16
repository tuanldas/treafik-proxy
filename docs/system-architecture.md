# System Architecture

## Tổng quan 2 tầng

```
                    Internet (80/443)
                          │
                  ┌───────▼────────┐   network: proxy
                  │    Traefik     │   (reverse proxy, auto-discovery qua label,
                  │  entrypoints   │    Let's Encrypt / Cloudflare, metrics :8082)
                  └───┬────────┬───┘
            route ────┘        └──── route
        ┌─────────────┐   ┌──────────────┐
        │  Grafana    │   │  app/whoami  │   ← service có label traefik.enable
        └─────────────┘   └──────────────┘
                          │
══════════════════════════════════════════  network: monitoring (KHÔNG expose)
   Prometheus ◄── scrape ── node-exporter, cadvisor, traefik:8082,
       │                     blackbox-exporter, (postgres/redis/mysqld optional)
       │ eval rule_files
       ▼ fire
   Alertmanager ──► Telegram / Slack / Email / Discord   (chọn qua .env)
       ▲
   Grafana ◄── datasource ── Prometheus + Loki
                                  ▲
                              Loki ◄── push ── Alloy ◄── docker.sock (log container)
```

- **Tầng proxy** (`proxy` network): Traefik + các service có route ra ngoài.
- **Tầng monitoring** (`monitoring` network): toàn bộ exporter + Prometheus + Alertmanager + Loki + Alloy — **không** gắn label Traefik, **không** expose internet. Grafana & Prometheus nằm cả 2 network (Grafana route ra ngoài; Prometheus có domain riêng bảo vệ basic-auth).

## Luồng sinh compose (`setup.sh`)

```
.env (cờ <TÊN>=true) ─┐
services/*.md ────────┼─► setup.sh ─► docker-compose.yml (header networks/volumes + services bật)
                      │            ├─► traefik/dynamic/auth.generated.yml      (hash mật khẩu dashboard)
                      │            ├─► alertmanager/alertmanager.generated.yml (receiver theo cờ ALERT_*)
                      │            └─► prometheus/targets/blackbox.generated.yml (target từ Host())
```

Các bước chính trong `setup.sh`:
1. Tạo `acme/acme.json` (600) nếu chưa có.
2. `hash_cred` → sinh `auth.generated.yml` (basic-auth dashboard).
3. `generate_alertmanager()` → sinh receiver Telegram/Slack/Email/Discord theo cờ `ALERT_*` (ghi thẳng secret, gitignore).
4. Áp cờ `SSL`: chuyển router web↔websecure, bỏ/giữ `certresolver`, comment/mở khối redirect trong `traefik.yml`.
5. Đồng bộ tên network proxy vào `traefik.yml`.
6. Ghép header + service bật → `docker-compose.yml`.
7. `generate_blackbox_targets()` → sinh `file_sd` từ `Host()` (scheme/module theo `SSL`).
8. In danh sách host cần trỏ DNS.

## Observability — 4 trụ cột

| Trụ cột | Thành phần | Dữ liệu |
|---------|-----------|---------|
| **Metrics** | Prometheus ← node-exporter (host), cAdvisor (container), Traefik (proxy) | TSDB, retention 30d |
| **Alerting** | Alertmanager ← 15 rule (`prometheus/rules/alerts.yml`) | route + group + inhibit → 4 kênh |
| **Uptime/SSL** | Blackbox exporter ← probe domain (file_sd tự sinh) | `probe_success`, cert expiry |
| **Logs** | Loki ← Alloy (đọc `docker.sock`) | bind-mount `./loki/data`, retention 31d |
| **Visualize** | Grafana ← datasource Prometheus + Loki | 5 dashboard provisioned |

### Luồng metric → alert

```
exporter ──(15s scrape)──► Prometheus ──(eval rule_files)──► alert pending→firing (sau `for:`)
   ──► Alertmanager (group_by alertname+instance, inhibit InstanceDown nuốt warning) ──► kênh báo
```

Alert rules chia 4 nhóm: `host` (InstanceDown, Disk, Memory, Load…), `container` (Killed, RestartLoop, HighMemory), `traefik` (5xx, latency, ServiceDown), `blackbox` (ProbeFailed, SSLCertExpiring/Expired).

### Luồng log

```
container stdout/stderr ──► Docker ──► Alloy (discovery.docker + relabel name→container)
   ──(loki.write)──► Loki ──► Grafana (LogQL, datasource Loki)
```

Nhãn `container` của Alloy khớp nhãn `name` của cAdvisor → xem log & metric cùng container.

## Nguyên tắc thiết kế dashboard/alert

- **USE** (Utilization/Saturation/Errors) cho host & container (node-exporter, cAdvisor).
- **RED** (Rate/Errors/Duration) cho dịch vụ HTTP (Traefik).
- **4 Golden Signals** cho dashboard tổng (`00 — Overview / NOC`).
- Dashboard tự viết dùng biến `${datasource}` (tên `Prometheus`) — không hardcode uid.

## Bảo mật

- Exporter & Alertmanager & Loki & Alloy chỉ ở `monitoring` → `/metrics` không ra internet.
- Traefik metrics ở entrypoint nội bộ `:8082` (không trong `web`/`websecure`).
- Secret chỉ trong `.env`; file generated chứa secret (`auth.generated.yml`, `alertmanager.generated.yml`) đều gitignored.
- Prometheus có route ngoài nhưng chặn bằng `dashboard-auth@file` (basic-auth).

## Lưu ý môi trường

- node-exporter/cAdvisor viết cho host Linux; trên Docker Desktop (macOS/Win) một số metric đĩa/IO/OOM/time-drift thiếu (chạy trong VM) — không phải lỗi.
- **CentOS/RHEL + SELinux:** có thể chặn Alloy đọc `docker.sock` → cần `:z`/`label=disable` (xem [deployment-guide.md](deployment-guide.md)).
