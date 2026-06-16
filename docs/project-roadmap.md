# Project Roadmap

## Đã hoàn thành — nền tảng

Proxy Traefik + codegen compose + giám sát cơ bản (Prometheus, Grafana, node-exporter, cAdvisor, 3 dashboard) + SSL Let's Encrypt/Cloudflare. Xem [README.md](../README.md).

## Đã hoàn thành — bộ observability toàn diện

Triển khai theo kế hoạch [`plans/260616-monitoring-observability-stack/`](../plans/260616-monitoring-observability-stack/plan.md). **7/8 phase Done** (verify mức config/generator bằng docker: promtool/amtool/alloy fmt/loki verify/jq).

| Hạng mục | Trạng thái |
|----------|-----------|
| Vá 3 lỗi PromQL dashboard (working_set, bỏ clamp_min, by instance) | ✅ |
| Alertmanager + 15 alert rules (host/container/traefik/blackbox) | ✅ |
| 4 kênh báo chọn qua `.env` (Telegram/Slack/Email/Discord) | ✅ |
| Blackbox exporter — uptime + SSL, tự sinh target từ `Host()` | ✅ |
| Dashboard `00 — Overview / NOC` (4 Golden Signals) | ✅ |
| Panel USE/RED bổ sung (swap/inode/IO/throttle/OOM/router…) | ✅ |
| Loki + Alloy — log tập trung container | ✅ |

## Còn lại

| Việc | Loại | Ghi chú |
|------|------|---------|
| **Test runtime** (alert gửi thật, thu log, render dashboard) | Vận hành | Cần `docker compose up` + secret thật (Telegram/Discord webhook) |
| **Test SELinux trên CentOS** | Vận hành | Alloy đọc `docker.sock` có thể bị chặn — xem [deployment-guide.md](deployment-guide.md) |
| **DB exporter (postgres/redis/mysqld) + Pushgateway** | Optional (YAGNI) | Chỉ cook khi có backend thật. Khuôn sẵn trong [phase 7](../plans/260616-monitoring-observability-stack/phase-07-p3-optional-exporters.md) |

## Hướng mở rộng tương lai (chưa cam kết)

- **Phân kênh báo theo severity** (vd Discord chỉ `critical`) — cần route tree đa-receiver trong `generate_alertmanager()`.
- **Tự sinh `prometheus.yml` scrape config** — hiện tĩnh, thêm target sửa tay.
- **Đa-host** — hiện single-host static scrape; mở rộng cần `$instance`/service discovery.
- **Cập nhật README** — README chưa phản ánh service mới (alerting/blackbox/loki); cân nhắc đồng bộ.

## Nguyên tắc cắt phạm vi

YAGNI: chỉ thêm service có nhu cầu thật (DB exporter chờ DB; Pushgateway chờ batch job). KISS: bind-mount thay named volume cho service mới; broadcast kênh báo thay vì route phức tạp.
