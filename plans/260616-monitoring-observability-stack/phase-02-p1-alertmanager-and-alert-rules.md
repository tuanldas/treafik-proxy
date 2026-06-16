---
phase: 2
title: "P1 Alertmanager and Alert Rules"
status: pending
priority: P1
effort: "1d"
dependencies: []
---

# Phase 2: P1 — Alertmanager + alert rules + 3 kênh chọn qua env

## Overview
Thêm Prometheus Alertmanager + bộ alert rules tối thiểu cho sysadmin. Notification hỗ trợ **cả 3 kênh (Telegram/Slack/Email), bật/tắt từng kênh qua `.env`** bằng cách `setup.sh` sinh `alertmanager.generated.yml` theo cờ — tái dùng đúng pattern đã có khi sinh `auth.generated.yml` (ghi **giá trị secret thật** vào file gitignore).

> **Đã verify bằng `docker pull` (2026-06-16):** Alertmanager bản thật = **`v0.33.0`** (build 2026-06-12). Flag `--config.expand-environment-variables` **KHÔNG tồn tại** → thiết kế dùng env-expansion (đề xuất ban đầu của research) bị loại; thay bằng sinh file chứa giá trị thật + gitignore.

## Requirements
- Functional: Prometheus eval rules → đẩy Alertmanager → định tuyến tới (các) kênh đang bật. Stop 1 container phải nhận được thông báo.
- Functional: chọn kênh qua cờ `ALERT_TELEGRAM/ALERT_SLACK/ALERT_EMAIL` trong `.env`, không sửa file YAML tay.
- Non-functional: secret nguồn ở `.env`; `alertmanager.generated.yml` (chứa secret thật, gitignore) là file sinh — không commit, không sửa tay. Chống alert fatigue bằng group + inhibition.

## Architecture
```
Prometheus (eval rule_files mỗi 15s) ──fire──► Alertmanager :9093 ──route/group/inhibit──► [Telegram|Slack|Email]
```
- `setup.sh` thêm hàm `generate_alertmanager()`: nếu `ALERTMANAGER=true`, đọc 3 cờ `ALERT_*`, ghép `receivers:` chỉ gồm block của kênh bật, ghi `alertmanager/alertmanager.generated.yml` (route + receiver 'notify' + inhibit_rules tĩnh). Secret ghi **thẳng giá trị** bằng `get_raw` (như `auth.generated.yml`).
- Service `alertmanager` chỉ mount file generated — **không** cần flag expand, **không** cần `environment:` secret (an toàn hơn: `docker inspect` không lộ). Bind-mount `./alertmanager/data` (né header volume).
- Prometheus: thêm `alerting:` + `rule_files:` vào `prometheus.yml`, mount `./prometheus/rules` qua `services/prometheus.md`.

## Related Code Files
- Create: `services/alertmanager.md` (service, network `monitoring`, không expose)
- Create: `prometheus/rules/alerts.yml` (bộ rule host/container/traefik)
- Modify: `setup.sh` (thêm `generate_alertmanager()`, gọi sau khối sinh `auth.generated.yml` ~dòng 168)
- Modify: `prometheus/prometheus.yml` (thêm `alerting:` + `rule_files:`)
- Modify: `services/prometheus.md` (thêm mount `./prometheus/rules:/etc/prometheus/rules:ro`)
- Modify: `.env` (thêm cờ + tên biến secret — KHÔNG giá trị)
- Modify: `.gitignore` (thêm `alertmanager/alertmanager.generated.yml`, `alertmanager/data/`)

## Test-First (TDD)
1. **Rule hợp lệ:** `docker run --rm -v $PWD/prometheus/rules:/r --entrypoint promtool prom/prometheus:v3.12.0 check rules /r/alerts.yml` → SUCCESS.
2. **Config Alertmanager hợp lệ:** sau `./setup.sh` (đã điền secret test vào `.env`), `docker run --rm -v $PWD/alertmanager:/a --entrypoint amtool prom/alertmanager:v0.33.0 check-config /a/alertmanager.generated.yml` → OK. (Lưu ý `--entrypoint amtool` — entrypoint mặc định image là `alertmanager`.)
3. **Sinh đúng theo cờ:** bật chỉ `ALERT_TELEGRAM=true` → file generated CHỈ có `telegram_configs`; bật cả 3 → có cả 3 block. Kiểm bằng `grep`.
4. **Compose hợp lệ:** `docker compose config >/dev/null`.
5. **End-to-end:** `docker stop whoami` (hoặc 1 container test) → trong ≤ (for + group_wait) nhận thông báo ở kênh bật; `docker start` → nhận "resolved".
6. **Không lộ secret ngoài file gitignore:** `git check-ignore alertmanager/alertmanager.generated.yml` trả về path (đã ignore); `docker inspect alertmanager` không chứa secret (vì không dùng `environment:`).

## Implementation Steps
1. **`prometheus/rules/alerts.yml`** — bộ rule đã verify (awesome-prometheus-alerts + Traefik v3 docs). Nhóm `host` (InstanceDown, TargetMissing, HighMemory, DiskAlmostFull, DiskWillFillSoon predict_linear 6h→24h, HostHighLoad), `container` (ContainerKilled, ContainerRestartLoop, ContainerHighMemory — nhãn `name` cho Docker thuần), `traefik` (Traefik5xxHigh entrypoint, TraefikHighLatency p95, TraefikServiceDown). PromQL đầy đủ trong report researcher-1 §D. **Comment mô tả hành vi, không tham chiếu số phase.**
2. **`services/prometheus.md`** — thêm 1 dòng volume mount `./prometheus/rules:/etc/prometheus/rules:ro` vào block yaml.
3. **`prometheus/prometheus.yml`** — thêm ngay sau `global:`:
   ```yaml
   alerting:
     alertmanagers:
       - static_configs:
           - targets: ["alertmanager:9093"]
   rule_files:
     - /etc/prometheus/rules/*.yml
   ```
4. **`services/alertmanager.md`** — service `prom/alertmanager:${ALERTMANAGER_VERSION:-v0.33.0}`, network `monitoring`, command `--config.file=/etc/alertmanager/alertmanager.yml --storage.path=/alertmanager`, mount `./alertmanager/alertmanager.generated.yml:/etc/alertmanager/alertmanager.yml:ro` + `./alertmanager/data:/alertmanager`. **Không** `environment:` secret, **không** flag expand.
5. **`setup.sh` — `generate_alertmanager()`** (đặt sau khối auth.generated.yml ~dòng 168, gọi có điều kiện):
   - `is_true "$(get_flag ALERTMANAGER)"` mới sinh; `mkdir -p alertmanager/data`.
   - Ghi `route:` (receiver 'notify', `group_by: ['alertname','instance']`, `group_wait: 30s`, `group_interval: 5m`, `repeat_interval: 4h`, sub-route `severity=critical` repeat 1h).
   - `receivers: - name: 'notify'` rồi **append có điều kiện** bằng `get_raw` (ghi giá trị thật):
     - `ALERT_TELEGRAM` → `telegram_configs` (`bot_token: '<get_raw TELEGRAM_BOT_TOKEN>'`, `chat_id: <get_raw TELEGRAM_CHAT_ID>`, `parse_mode: HTML`, `send_resolved: true`).
     - `ALERT_SLACK` → `slack_configs` (`api_url: '<get_raw SLACK_WEBHOOK_URL>'`, `send_resolved: true`).
     - `ALERT_EMAIL` → `email_configs` (`to/from/smarthost/auth_username/auth_password` = `get_raw SMTP_*`).
   - `inhibit_rules` tĩnh: InstanceDown nuốt warning cùng instance; critical nuốt warning trùng alertname+instance.
   - **Escape:** bọc secret trong single-quote; cảnh báo nếu secret chứa ký tự `'` (SMTP password phức tạp) — hiếm, nhưng ghi chú để tránh vỡ YAML.
   - Cảnh báo nếu `ALERTMANAGER=true` mà cả 3 cờ kênh đều false (sinh receiver rỗng → alert không gửi đâu).
   - Header file: `# SINH TỰ ĐỘNG bởi setup.sh — ĐỪNG SỬA TAY (chứa secret). Đã .gitignore.`
6. **`.env`** — thêm:
   ```dotenv
   ALERTMANAGER=true
   ALERTMANAGER_VERSION=v0.33.0      # đã verify docker pull 2026-06-16
   ALERT_TELEGRAM=true
   ALERT_SLACK=false
   ALERT_EMAIL=false
   TELEGRAM_BOT_TOKEN=
   TELEGRAM_CHAT_ID=
   SLACK_WEBHOOK_URL=
   SMTP_SMARTHOST=
   SMTP_FROM=
   SMTP_TO=
   SMTP_AUTH_USERNAME=
   SMTP_AUTH_PASSWORD=
   ```
7. **`.gitignore`** — thêm `alertmanager/alertmanager.generated.yml` và `alertmanager/data/`.
8. Chạy TDD bước 1→6.

## Success Criteria
- [ ] `promtool check rules` + `amtool check-config` (đúng entrypoint) PASS.
- [ ] Đổi cờ `ALERT_*` → `./setup.sh` sinh đúng tập receiver (verify bằng grep).
- [ ] Stop container test → nhận alert ở kênh bật; start → nhận resolved.
- [ ] `alertmanager.generated.yml` đã gitignore; secret không xuất hiện trong `docker inspect` hay git.
- [ ] Prometheus tab **Alerts** hiện đủ rule, không lỗi parse.

## Risk Assessment
- **Flag expand không tồn tại (ĐÃ XỬ LÝ):** verify v0.33.0 không có `--config.expand-environment-variables` → đã chuyển sang ghi giá trị thật vào file gitignore. Đây là cách Alertmanager khuyến nghị tránh secret-in-flag và khớp pattern repo. (Phương án thay thế nếu muốn tách secret khỏi config: dùng `bot_token_file`/`*_file` + setup.sh ghi file secret riêng — phức tạp hơn, chưa cần.)
- **Secret trong file generated:** nằm `alertmanager.generated.yml` (gitignore, mount `:ro`) — cùng mô hình bảo mật với `auth.generated.yml` (đã chứa hash). Chấp nhận được. Escape single-quote cho SMTP password.
- **Alert host trên Docker Desktop dev** có thể không kích hoạt đúng (thiếu metric đĩa/load) — chỉ test host alert thật trên Ubuntu/CentOS. Test container/traefik alert chạy được ở mọi nơi.
- **CentOS/RHEL:** không ảnh hưởng Alertmanager (chỉ network nội bộ, không mount docker.sock).
- **Receiver rỗng:** nếu bật `ALERTMANAGER` mà tắt cả 3 kênh → `generate_alertmanager()` phải cảnh báo.
- **Tag `v0.33.0`:** xác nhận đúng tag trên Docker Hub khi pull (đã thấy `version 0.33.0` từ image `latest`); nếu Docker Hub dùng tag không-prefix, điều chỉnh `.env`.
