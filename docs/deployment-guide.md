# Deployment Guide

> Cài đặt cơ bản & `.env` chuẩn: [`README.md`](../README.md). Tài liệu này bổ sung **triển khai production + bật observability nâng cao (alerting/blackbox/logs)**.

## Quy trình chung

Mọi thay đổi: sửa `.env` hoặc `services/*.md` → `./setup.sh` → `docker compose up -d`.

```bash
chmod +x setup.sh
./setup.sh --up        # sinh compose + chạy
```

## Triển khai production (Ubuntu / CentOS)

1. `DOMAIN=<domain thật>`, `SSL=true`, `ACME_EMAIL=<email>` trong `.env`.
2. Trỏ DNS (A record) các host `setup.sh` in ra về IP server; mở cổng 80/443.
3. Đổi `TRAEFIK_DASHBOARD_PASSWORD`, `GRAFANA_PASSWORD`.
4. `./setup.sh --up`.

**Khác biệt host metrics:** node-exporter/cAdvisor đầy đủ trên Linux thật. Trên Docker Desktop (dev) một số metric đĩa/IO/OOM/time-drift thiếu — bình thường.

## Bật cảnh báo (Alertmanager)

> 📒 **Hướng dẫn chi tiết lấy token/webhook từng kênh:** [notification-channels-setup.md](notification-channels-setup.md).

```dotenv
ALERTMANAGER=true
ALERT_TELEGRAM=true        # chọn kênh: telegram/slack/email/discord
TELEGRAM_BOT_TOKEN=<từ @BotFather>
TELEGRAM_CHAT_ID=<từ @userinfobot>
# ALERT_DISCORD=true / DISCORD_WEBHOOK_URL=...   (Server Settings → Integrations → Webhooks)
```

- Bật **nhiều kênh** = mỗi alert gửi qua **tất cả** kênh (broadcast, nhận trùng) — không phải failover.
- `./setup.sh` sinh `alertmanager.generated.yml` theo cờ. Test: `docker stop whoami` → chờ ~30s nhận báo; `docker start whoami` → "resolved".
- Verify config: `docker run --rm -v $PWD/alertmanager:/a --entrypoint amtool prom/alertmanager:v0.33.0 check-config /a/alertmanager.generated.yml`.

## Bật giám sát uptime/SSL (Blackbox)

```dotenv
BLACKBOX_EXPORTER=true
```

`setup.sh` tự sinh `prometheus/targets/blackbox.generated.yml` từ `Host()` trong services đang bật. Scheme/module theo `SSL`: `SSL=true` → `https` + đo cert; `SSL=false` → `http`. Cảnh báo cert <14 ngày tự kích hoạt.

## Bật log tập trung (Loki + Alloy)

```dotenv
LOKI=true
ALLOY=true
```

Xem log trong Grafana → Explore → datasource **Loki** → `{job="docker"}` hoặc `{container="traefik"}`. Retention 31 ngày (`loki/loki-config.yml`).

### ⚠️ CentOS/RHEL — SELinux

SELinux enforcing có thể **chặn Alloy đọc `/var/run/docker.sock`** → không thu được log. Khắc phục:
- Thêm `:z` vào bind-mount docker.sock trong `services/alloy.md`, hoặc
- `--security-opt label=disable` cho service alloy (cân nhắc bảo mật), hoặc
- Chỉnh SELinux policy cho phép container_t đọc docker.sock.

**Phải test riêng trên CentOS** — không suy ra từ Ubuntu/macOS.

### Quyền bind-mount Loki (Linux)

Loki chạy user `10001`. Nếu lỗi permission: `chown -R 10001:10001 loki/data`.

## Vận hành

```bash
docker compose ps                       # trạng thái
docker compose logs -f alertmanager     # log 1 service
docker compose config                   # kiểm cú pháp compose sinh
./setup.sh && docker compose up -d --remove-orphans   # áp đổi service, gỡ container cũ
```

## Rollback

Tắt service mới: cờ `<TÊN>=false` trong `.env` → `./setup.sh && docker compose up -d --remove-orphans`. Dashboard/alert là file text — revert bằng `git checkout`.

## Checklist bảo mật

- [ ] Đổi mật khẩu dashboard + Grafana.
- [ ] Không commit `.env`, `acme/`, `*.generated.yml`, `*/data/` (đã gitignore).
- [ ] Chỉ mở 80/443; exporter/Alertmanager/Loki/Alloy giữ trong `monitoring`.
- [ ] Test SSL bằng Let's Encrypt staging trước khi production.
