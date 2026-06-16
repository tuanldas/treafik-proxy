# Codebase Summary

## Cấu trúc thư mục (sau khi triển khai observability)

```
proxy/
├── setup.sh                  # BỘ SINH compose + config generated (bash)
├── .env                      # cấu hình + cờ bật/tắt (gitignored)
├── docker-compose.yml        # SINH TỰ ĐỘNG — không sửa tay
├── README.md / CLAUDE.md     # hướng dẫn người dùng / AI agent
├── docs/                     # tài liệu dự án (file này)
├── plans/                    # kế hoạch & report (observability stack)
│
├── services/                 # mỗi service = 1 file .md (đúng 1 block ```yaml)
│   ├── traefik.md            # bắt buộc (luôn vào compose)
│   ├── grafana.md  prometheus.md  node-exporter.md  cadvisor.md  whoami.md
│   ├── alertmanager.md       # cảnh báo (4 kênh)
│   ├── blackbox-exporter.md  # uptime + SSL
│   ├── loki.md  alloy.md     # log tập trung
│   └── _template.md          # copy để tạo service mới (file _* bị bỏ qua)
│
├── traefik/
│   ├── traefik.yml           # static config (entrypoints, ACME, metrics :8082, provider)
│   └── dynamic/              # middlewares.yml + auth.generated.yml (sinh, gitignored)
├── prometheus/
│   ├── prometheus.yml        # scrape targets (tĩnh) + alerting + rule_files
│   ├── rules/alerts.yml      # 15 alert rule (host/container/traefik/blackbox)
│   └── targets/blackbox.generated.yml  # file_sd sinh từ Host() (gitignored)
├── alertmanager/
│   ├── alertmanager.generated.yml      # receiver sinh theo cờ (secret, gitignored)
│   └── data/                 # state (gitignored)
├── blackbox/blackbox.yml     # module probe (http/strict-tls/tcp/icmp)
├── loki/
│   ├── loki-config.yml        # single-binary + retention 31d
│   └── data/                 # log store bind-mount (gitignored)
├── alloy/config.alloy        # River — thu log docker.sock → Loki
├── grafana/
│   ├── provisioning/datasources/  # datasource.yml (Prometheus) + loki.yml
│   ├── provisioning/dashboards/   # auto-load config
│   └── dashboards/           # 00-overview-noc + traefik + node-exporter + cadvisor (.json)
└── acme/acme.json            # chứng chỉ (sinh, gitignored)
```

## File then chốt

| File | Vai trò |
|------|---------|
| `setup.sh` | Bộ sinh. Hàm: `extract_yaml`, `apply_ssl`, `hash_cred`, `generate_alertmanager`, `generate_blackbox_targets`, `toggle_redirect`, `set_traefik_network` |
| `services/*.md` | Nguồn fragment compose (1 block ```yaml thụt 2 space) |
| `.env` | Cờ bật/tắt + secret. Tên cờ = tên file HOA, ký tự lạ → `_` |
| `prometheus/rules/alerts.yml` | Bộ alert (promtool-validated) |

## Thành phần sinh tự động (KHÔNG sửa tay)

| File | Sinh bởi | Track? |
|------|----------|--------|
| `docker-compose.yml` | setup.sh ghép services | ✅ tracked |
| `traefik/dynamic/auth.generated.yml` | `hash_cred` | ❌ gitignored (hash) |
| `alertmanager/alertmanager.generated.yml` | `generate_alertmanager` | ❌ gitignored (secret) |
| `prometheus/targets/blackbox.generated.yml` | `generate_blackbox_targets` | ❌ gitignored |

## Ngôn ngữ / công nghệ

- **Bash** (`setup.sh`) — bộ sinh, không phụ thuộc ngoài (chỉ cần `openssl`/`htpasswd`/`docker` để hash).
- **YAML** — compose fragment, config Prometheus/Alertmanager/Loki/Grafana.
- **River** (`config.alloy`) — config Grafana Alloy.
- **JSON** — dashboard Grafana (schemaVersion 39).
- **Markdown** — service descriptors + docs.

## Số liệu hiện tại

10 service · 15 alert rules · 5 dashboard · 4 kênh báo · 2 network · retention metric 30d / log 31d.
