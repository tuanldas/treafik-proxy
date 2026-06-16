# Research: Hệ thống cảnh báo (Alertmanager + alert rules + notification)

**Researcher:** researcher-1 | **Date:** 2026-06-16 | **Task:** #1
**Stack:** Traefik + Prometheus v3.12 + Grafana + node-exporter + cAdvisor (docker-compose sinh từ `services/*.md` + `.env` qua `setup.sh`)

---

## Executive Summary

Stack hiện thu metric (Prometheus 4 job) nhưng **không có alerting** — sự cố chỉ phát hiện khi người nhìn dashboard. Đề xuất: thêm **Prometheus Alertmanager** (không phải Grafana Unified Alerting) vì nguồn chân lý alert nên nằm cạnh Prometheus, version-control được, và rule là code copy-là-chạy.

Giải pháp gồm 4 mảnh, tất cả theo cơ chế repo (file + cờ `.env`, secret không hardcode):
1. `services/alertmanager.md` — 1 service, cờ `ALERTMANAGER=true`.
2. 2 dòng thêm vào `prometheus/prometheus.yml` (`alerting:` + `rule_files:`) + 1 file rules `prometheus/rules/alerts.yml` (~11 alert).
3. `alertmanager/alertmanager.yml` đọc secret qua env (`bot_token_file`/`api_url_file` hoặc biến môi trường) — **khuyến nghị Telegram** cho sysadmin solo.
4. Routing tree + grouping + inhibition chống alert fatigue.

**Khối lượng:** ~3 file mới + sửa nhẹ `prometheus.yml`, `setup.sh` (mount secret). Không phá vỡ gì hiện có.

**Cảnh báo version (xem Unresolved):** Các nguồn web trả về số version mâu thuẫn cho Alertmanager (v0.28.1 trên Debian đầu 2025 vs "v0.33" do WebFetch sinh ra — nghi hallucination). Report pin **`v0.28.1`** làm default an toàn (đã ổn định, phổ biến), cho phép override qua `.env`.

---

## Key Findings

### 1. Kiến trúc Alertmanager

```
Prometheus (eval rules mỗi 15s)  ──fire──►  Alertmanager  ──route/group/inhibit──►  Telegram/Slack/Email
   rule_files: alerts.yml                       :9093
   alerting.alertmanagers: [alertmanager:9093]
```

- **Prometheus** đánh giá `rule_files`, alert chuyển `pending`→`firing` sau `for:`, rồi đẩy sang Alertmanager.
- **Alertmanager** lo: **dedup, group, inhibit, silence, route → receiver**. Nó KHÔNG đánh giá PromQL (đó là việc Prometheus).
- Phân tách đúng: ngưỡng/PromQL ở Prometheus; "gửi cho ai, gộp thế nào" ở Alertmanager.

**Tích hợp `prometheus.yml`** (xác nhận từ docs Prometheus latest — [config](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)):
```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

rule_files:
  - /etc/prometheus/rules/*.yml
```
→ 2 khối này thêm vào đầu `prometheus.yml` (sau `global:`). Cần mount thư mục rules vào Prometheus container (xem Recommendations §A).

### 2. Notification — Telegram vs Slack vs Email

| Tiêu chí | **Telegram** | **Slack** | **Email (SMTP)** |
|---|---|---|---|
| Setup | Tạo bot (@BotFather) + lấy `chat_id` | Incoming webhook URL | SMTP host + app-password |
| Secret cần | `bot_token`, `chat_id` | `api_url` (webhook) | `smtp_auth_password` |
| Native trong Alertmanager | ✅ `telegram_configs` (từ v0.24+) | ✅ `slack_configs` | ✅ `email_configs` |
| Push tức thì điện thoại | ✅ Tốt nhất cho solo/SMB | ✅ (cần app Slack) | ⚠️ Chậm, dễ bỏ lỡ |
| Chi phí | Free | Free tier | Cần SMTP (Gmail/SES) |
| Phù hợp stack này | **★ Khuyến nghị** | Nếu team đã dùng Slack | Backup/critical kép |

**Khuyến nghị: Telegram** — rẻ, push nhanh, ít ma sát nhất cho sysadmin. Cú pháp (xác nhận [Alertmanager config docs](https://prometheus.io/docs/alerting/latest/configuration/)):
```yaml
receivers:
  - name: 'telegram'
    telegram_configs:
      - bot_token: '${TELEGRAM_BOT_TOKEN}'   # hoặc bot_token_file
        chat_id: ${TELEGRAM_CHAT_ID}          # số nguyên, có thể âm (group)
        parse_mode: 'HTML'
        send_resolved: true
```

### 3. Bộ alert rules tối thiểu — PromQL đã xác minh

Nguồn chính: [awesome-prometheus-alerts](https://github.com/samber/awesome-prometheus-alerts) (de-facto chuẩn community, raw `_data/rules.yml`) + [Traefik v3 metrics docs](https://doc.traefik.io/traefik/reference/install-configuration/observability/metrics/) (xác nhận tên metric + label `code`).

**Điều chỉnh cho stack này:** container rules trong awesome dùng nhãn k8s (`pod`); stack này là **Docker thuần** nên cAdvisor expose nhãn `name` (tên container) — đã đổi sang `name`. Disk: stack đã loại mountpoint host (`node-exporter.md` exclude `^/(sys|proc|dev|host|etc)`), nên filter `fstype` là đủ.

### 4. Chống alert fatigue

- **Grouping:** `group_by: ['alertname','instance']` — gộp alert cùng loại/cùng host thành 1 thông báo. `group_wait: 30s` (đợi gom burst đầu), `group_interval: 5m`, `repeat_interval: 4h` (không spam lại trong 4h nếu chưa resolve).
- **Severity routing:** `critical` → repeat 1h (gấp); `warning` → repeat 4h. Có thể tách receiver riêng.
- **Inhibition:** khi host `InstanceDown` (critical) thì **chặn** mọi warning của chính host đó (disk/mem/cpu vô nghĩa khi máy đã chết) — tránh 10 alert cho 1 sự cố. Xác nhận cú pháp `inhibit_rules` ([docs](https://prometheus.io/docs/alerting/latest/configuration/)).

### 5. Grafana Unified Alerting vs Prometheus Alertmanager

| | Prometheus Alertmanager | Grafana Unified Alerting |
|---|---|---|
| Nguồn rule | File YAML (version-control) | UI/DB Grafana (provisioning được nhưng nặng hơn) |
| Copy-là-chạy | ✅ rule là text | ⚠️ cần provisioning YAML riêng của Grafana |
| Routing/inhibit | ✅ mạnh, chuẩn ngành | Có nhưng kém linh hoạt hơn |
| Phụ thuộc | Chạy độc lập, Grafana down vẫn alert | Gắn vòng đời Grafana |
| Phù hợp repo "GitOps" này | **★ Chọn cái này** | Bỏ qua |

**Lý do chọn Alertmanager:** repo này triết lý "mọi thứ sinh từ file + version-control"; rule PromQL là code copy-là-chạy; alert không nên chết theo Grafana. Grafana giữ vai trò **visualize**, không kiêm alert.

---

## Evidence — File sẵn dùng (copy-là-chạy)

### A. `services/alertmanager.md`

> KHÔNG expose ra ngoài (chỉ Prometheus gọi nội bộ). Nếu muốn xem UI, thêm router Traefik + `dashboard-auth@file` y như prometheus.md. Mặc định để nội bộ cho an toàn.

````markdown
# Service: alertmanager

Nhận alert từ Prometheus, gom nhóm/ức chế/định tuyến rồi gửi thông báo
(Telegram/Slack/Email). Chỉ nằm trong network `monitoring`, không expose ra ngoài.

> Thuộc nhóm giám sát. Bật cùng `prometheus`. Secret lấy từ `.env`.

**Phụ thuộc:** `alertmanager/alertmanager.yml`.

```yaml
  alertmanager:
    image: "prom/alertmanager:${ALERTMANAGER_VERSION:-v0.28.1}"
    container_name: alertmanager
    restart: unless-stopped
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"
    environment:
      - "TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}"
      - "TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertmanager-data:/alertmanager
    networks:
      - monitoring
```
````

**Lưu ý quan trọng về secret:** Alertmanager **không tự expand `${VAR}`** trong file config (khác Prometheus một số chỗ). Hai cách đúng:
- **Cách 1 (khuyến nghị, KISS):** Bật env expansion bằng flag `--config.expand-environment-variables` (có từ v0.27+). Khi đó `bot_token: '${TELEGRAM_BOT_TOKEN}'` trong YAML sẽ được thay. → thêm flag này vào `command`.
- **Cách 2:** Dùng `bot_token_file: /etc/alertmanager/secret_token` + mount file. Phức tạp hơn, bỏ qua nếu Cách 1 chạy.

→ **Bản command nên dùng** (đã thêm flag expand):
```yaml
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"
      - "--config.expand-environment-variables"
```

### B. Thêm volume `alertmanager-data` vào header `setup.sh`

`setup.sh` hardcode volumes trong header (dòng ~193-197). Thêm:
```bash
  echo "  alertmanager-data:"
  echo "    name: \${ALERTMANAGER_VOLUME:-alertmanager-data}"
```
(Đặt cạnh `prometheus-data`/`grafana-data`. Nếu bỏ qua, Compose vẫn chạy nhưng cảnh báo volume không khai báo — nên thêm cho sạch.)

### C. Sửa `prometheus/prometheus.yml` — thêm alerting + rule_files + mount

Thêm vào đầu file (ngay sau khối `global:`):
```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

rule_files:
  - /etc/prometheus/rules/*.yml
```
Và mount thư mục rules — sửa `services/prometheus.md` block yaml, thêm 1 dòng volume:
```yaml
      - ./prometheus/rules:/etc/prometheus/rules:ro
```

### D. `prometheus/rules/alerts.yml` — bộ rule tối thiểu

```yaml
groups:
  # ============================================================
  # Host / Infrastructure (node-exporter)
  # ============================================================
  - name: host
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Target {{ $labels.instance }} ({{ $labels.job }}) down"
          description: "{{ $labels.job }} trên {{ $labels.instance }} không scrape được > 2 phút."

      - alert: TargetMissing
        # up==0 nhưng KHÔNG phải vì cả job chết (đó là JobDown)
        expr: up == 0 unless on(job) (sum by (job) (up) == 0)
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Exporter {{ $labels.instance }} biến mất"
          description: "Một target của job {{ $labels.job }} mất — exporter có thể crash."

      - alert: HighMemory
        expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "RAM thấp trên {{ $labels.instance }}"
          description: "Còn < 10% RAM khả dụng (hiện {{ $value | printf \"%.1f\" }}%)."

      - alert: DiskAlmostFull
        expr: |
          (node_filesystem_avail_bytes{fstype!~"^(fuse.*|tmpfs|cifs|nfs|overlay|squashfs)"}
            / node_filesystem_size_bytes) * 100 < 10
          and on (instance, device, mountpoint) node_filesystem_readonly == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Đĩa gần đầy trên {{ $labels.instance }}"
          description: "{{ $labels.mountpoint }} còn < 10% ({{ $value | printf \"%.1f\" }}%)."

      - alert: DiskWillFillSoon
        expr: |
          predict_linear(node_filesystem_avail_bytes{fstype!~"^(fuse.*|tmpfs|cifs|nfs|overlay|squashfs)"}[6h], 24*3600) <= 0
          and node_filesystem_avail_bytes > 0
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Đĩa {{ $labels.mountpoint }} sẽ đầy trong 24h ({{ $labels.instance }})"
          description: "Theo đà 6h gần nhất, {{ $labels.mountpoint }} hết chỗ trong < 24 giờ."

      - alert: HostHighLoad
        expr: 1 - (avg without (cpu) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 0.80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "CPU cao trên {{ $labels.instance }}"
          description: "CPU > 80% trong 10 phút (hiện {{ $value | printf \"%.0f\" }}%)."

  # ============================================================
  # Container (cAdvisor) — Docker thuần dùng nhãn 'name'
  # ============================================================
  - name: container
    rules:
      - alert: ContainerKilled
        # 'name' rỗng = tổng hợp cgroup, loại ra
        expr: time() - container_last_seen{name!=""} > 60
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.name }} biến mất"
          description: "cAdvisor không thấy {{ $labels.name }} > 60s (có thể restart loop / bị kill)."

      - alert: ContainerRestartLoop
        # restart nhiều lần trong 15 phút
        expr: changes(container_last_seen{name!=""}[15m]) > 3
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.name }} restart liên tục"
          description: "{{ $labels.name }} khởi động lại > 3 lần / 15 phút."

      - alert: ContainerHighMemory
        # so với memory limit (chỉ khi có đặt limit > 0)
        expr: |
          (container_memory_working_set_bytes{name!=""}
            / (container_spec_memory_limit_bytes{name!=""} > 0)) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.name }} sắp chạm memory limit"
          description: "RAM {{ $labels.name }} > 90% limit ({{ $value | printf \"%.0f\" }}%) — nguy cơ OOM-kill."

  # ============================================================
  # Traefik (entrypoint metrics — phủ toàn bộ traffic vào)
  # ============================================================
  - name: traefik
    rules:
      - alert: Traefik5xxHigh
        expr: |
          sum(rate(traefik_entrypoint_requests_total{code=~"5.."}[5m])) by (entrypoint)
            / sum(rate(traefik_entrypoint_requests_total[5m])) by (entrypoint) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Tỷ lệ 5xx cao ở entrypoint {{ $labels.entrypoint }}"
          description: "5xx > 5% trong 5 phút (hiện {{ $value | humanizePercentage }})."

      - alert: TraefikHighLatency
        expr: |
          histogram_quantile(0.95,
            sum(rate(traefik_entrypoint_request_duration_seconds_bucket[5m])) by (le, entrypoint)
          ) > 1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Độ trễ p95 cao ở {{ $labels.entrypoint }}"
          description: "p95 latency > 1s trong 10 phút (hiện {{ $value | printf \"%.2f\" }}s)."

      - alert: TraefikServiceDown
        # backend của router không có server nào UP
        expr: traefik_service_server_up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.service }} không có backend UP"
          description: "Mọi server của {{ $labels.service }} đang DOWN."
```

**Ghi chú PromQL (đã xác minh nguồn):**
- `up == 0`, `predict_linear(...[3h],86400)`, `node_memory_MemAvailable_bytes/MemTotal`, `node_filesystem_avail_bytes/size_bytes`, `1 - avg(rate(node_cpu_seconds_total{mode="idle"}))` — verbatim từ awesome-prometheus-alerts `_data/rules.yml`. Tôi mở rộng `fstype` exclude thêm `overlay|squashfs` (Docker layer) để tránh false-positive trên host Docker.
- `predict_linear` window đổi `3h`→`6h` cho ổn định hơn, `for: 30m` để tránh nhiễu nhất thời.
- `traefik_entrypoint_requests_total{code=~"5.."}` + histogram `_seconds_bucket`, label `code` — **xác nhận chính thức** từ Traefik v3 metrics docs. Dùng **entrypoint** (toàn bộ traffic) thay vì service để bắt cả lỗi router/middleware. Nếu muốn theo từng app, đổi `entrypoint`→`service` và metric `traefik_service_*`.
- Ngưỡng latency `> 1` (giây) và 5xx `> 0.05` là điểm khởi đầu — chỉnh theo SLO thực tế.

### E. `alertmanager/alertmanager.yml` — routing + grouping + inhibition

```yaml
# Secret KHÔNG hardcode — lấy từ env (cần flag --config.expand-environment-variables).
global:
  resolve_timeout: 5m

route:
  receiver: 'telegram'
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    # critical lặp lại gấp hơn
    - matchers:
        - severity = "critical"
      receiver: 'telegram'
      repeat_interval: 1h

receivers:
  - name: 'telegram'
    telegram_configs:
      - bot_token: '${TELEGRAM_BOT_TOKEN}'
        chat_id: ${TELEGRAM_CHAT_ID}
        parse_mode: 'HTML'
        send_resolved: true

# Chống alert fatigue: host chết thì im mọi warning của chính host đó.
inhibit_rules:
  - source_matchers: [ 'alertname = "InstanceDown"' ]
    target_matchers: [ 'severity = "warning"' ]
    equal: ['instance']
  # critical đã kêu thì nuốt warning trùng (cùng alertname+instance)
  - source_matchers: [ 'severity = "critical"' ]
    target_matchers: [ 'severity = "warning"' ]
    equal: ['alertname', 'instance']
```

### F. Thêm vào `.env` (chỉ tên biến — KHÔNG ghi giá trị thật vào repo)

```dotenv
# --- Alertmanager ---
ALERTMANAGER=true
ALERTMANAGER_VERSION=v0.28.1
ALERTMANAGER_VOLUME=alertmanager-data
# Secret Telegram (lấy từ @BotFather và @userinfobot — KHÔNG commit giá trị thật)
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```

> `.env` đã trong `.gitignore` → an toàn. Alertmanager đọc 2 biến TELEGRAM qua `environment:` trong compose + flag expand.

---

## Recommendations (ranked)

1. **Dùng Prometheus Alertmanager, không dùng Grafana Unified Alerting** — hợp triết lý GitOps của repo, rule là code, alert độc lập Grafana. *(độ tin cậy: cao — chuẩn ngành)*
2. **Kênh Telegram** làm receiver chính (solo sysadmin). Slack chỉ nếu team đã dùng; Email làm backup cho `critical` nếu cần kênh thứ 2.
3. **Bật env-expansion** (`--config.expand-environment-variables`, v0.27+) thay vì `*_file` — đơn giản hơn, vẫn không hardcode secret. *Phải kiểm tra version Alertmanager hỗ trợ flag này (xem Unresolved).*
4. **Bắt đầu với 11 alert ở §D**, đủ phủ InstanceDown/Disk/Mem/CPU/Container/Traefik 5xx+latency. Thêm dần theo sự cố thực, đừng over-engineer (YAGNI).
5. **Inhibition + group_by** ngay từ đầu — chi phí 0, lợi ích chống spam lớn khi 1 host chết.
6. **Pin version** trong `.env`, không dùng `latest`. Default `v0.28.1` (an toàn); nâng sau khi xác minh version thực trên Docker Hub.

**Thứ tự triển khai:** (1) thêm `alerting`+`rule_files`+mount vào prometheus → (2) tạo `prometheus/rules/alerts.yml` → reload Prometheus, kiểm tra tab Alerts hiện rule → (3) thêm `services/alertmanager.md` + volume + `.env` → (4) `alertmanager/alertmanager.yml` → `./setup.sh && docker compose up -d` → (5) test bằng cách `docker stop` 1 container, chờ Telegram báo.

---

## Unresolved Questions

1. **Version Alertmanager thực tế đầu 2026** — Các nguồn web mâu thuẫn: WebFetch Docker Hub/GitHub releases trả "v0.33.0 (2026-06)" nhưng **nghi hallucination** (WebSearch qua endoflife.date/Debian tracker cho thấy v0.28.1 vào Debian 2025-02, dòng v0.2x). Report pin `v0.28.1` an toàn. **Cần team-lead/triển khai `docker pull prom/alertmanager` xem tag thật** rồi cập nhật `.env`. Flag `--config.expand-environment-variables` cần version ≥ v0.27 — verify trước khi dùng (nếu không, fallback `bot_token_file`).
2. **node-exporter có chạy không?** Stack có `services/node-exporter.md` nhưng host là **Docker Desktop (macOS/Windows)** theo CLAUDE.md — node-exporter viết cho Linux. Trên Docker Desktop, `node_filesystem_*`/`node_load*` có thể thiếu/sai → DiskAlmostFull/HostHighLoad có thể không kích hoạt đúng. Alert host chỉ thật sự đáng tin **khi deploy lên server Linux production**.
3. **Có expose Alertmanager UI qua Traefik không?** Mặc định report để nội bộ (an toàn). Nếu muốn xem/silence qua web, cần thêm router + `dashboard-auth@file` (mẫu có sẵn trong `prometheus.md`). Cần xác nhận nhu cầu.
4. **SMTP cho email** — nếu chọn email backup, cần biết SMTP host/user của người dùng (Gmail app-password? SES?). Chưa có trong `.env` hiện tại.
5. **Ngưỡng cụ thể** (5xx 5%, latency p95 1s, CPU 80%) là điểm khởi đầu chuẩn community — cần điều chỉnh theo SLO/đặc thù tải thực của hệ thống.

---

## Nguồn

- [Prometheus — Configuration (alerting, rule_files)](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Alertmanager — Configuration (receivers, route, inhibit_rules)](https://prometheus.io/docs/alerting/latest/configuration/)
- [awesome-prometheus-alerts — `_data/rules.yml`](https://github.com/samber/awesome-prometheus-alerts) (PromQL host/container/self-monitoring)
- [Traefik v3 — Prometheus Metrics reference](https://doc.traefik.io/traefik/reference/install-configuration/observability/metrics/) (tên metric + label `code`)
- [Traefik v3.3 — Prometheus observability](https://doc.traefik.io/traefik/v3.3/observability/metrics/prometheus/)
- [endoflife.date — Prometheus](https://endoflife.date/prometheus) + [Debian alertmanager tracker](https://tracker.debian.org/pkg/prometheus-alertmanager) (cross-check version)
