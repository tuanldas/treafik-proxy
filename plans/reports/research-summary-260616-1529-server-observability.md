# Tổng hợp Research — Giám sát & Cảnh báo toàn diện cho stack

**Team:** server-observability (3 researcher) · **Date:** 2026-06-16 · **Lead synthesis**
**Stack:** Traefik + Prometheus + Grafana + node-exporter + cAdvisor (docker-compose sinh từ `services/*.md` + `.env` qua `setup.sh`)

**3 report nguồn:**
- [researcher-1 — Alerting](researcher-1-260616-1530-alerting-stack-report.md)
- [researcher-2 — Dashboard & chỉ số](researcher-2-260616-1531-dashboards-metrics-report.md)
- [researcher-3 — Mở rộng observability](researcher-3-260616-1531-observability-expansion-report.md)

---

## Executive summary

Stack hiện **thu thập metric tốt** (Prometheus 4 job: self, traefik, node-exporter, cadvisor) và có 3 dashboard provisioned. Nhưng đứng ở góc sysadmin, có **2 lỗ hổng vận hành lớn** và **3 lỗi số liệu**:

1. **Không có cảnh báo** → sự cố chỉ lộ khi có người mở dashboard ra nhìn. Thiếu thứ "gọi dậy lúc 3h sáng".
2. **Không giám sát uptime đầu-cuối** → biết container *chạy*, không biết khách *vào được* hay SSL sắp hết hạn.
3. **3 lỗi PromQL/metric** trong dashboard hiện có làm số liệu sai lệch (đã xác minh tận dòng).

Bản tổng hợp đưa ra **roadmap 4 tầng (P0→P3)**, mọi thứ đóng gói đúng cơ chế repo (file `services/*.md` + cờ `.env`, secret không hardcode). Tầng P0 gần như 0 công nhưng sửa số liệu sai; P1 bít 2 lỗ hổng lớn nhất.

---

## Quyết định kiến trúc đã chốt

| Vấn đề | Quyết định | Lý do |
|--------|-----------|-------|
| Engine cảnh báo | **Prometheus Alertmanager** (không Grafana Unified Alerting) | Hợp triết lý GitOps repo; rule là code copy-là-chạy; alert độc lập, Grafana down vẫn báo |
| Kênh thông báo | **Telegram** (mặc định) | Solo sysadmin, push điện thoại tức thì, free, native trong Alertmanager. Slack/email tùy chọn |
| Thu log | **Loki + Grafana Alloy** (KHÔNG Promtail) | Promtail **EOL 2026-03-02** — đã quá mốc tính tới hôm nay. Alloy là bản thay thế chính thức |
| Volume service mới | **Bind-mount** (vd `./loki/data`) | `setup.sh` header hardcode chỉ 2 named volume; bind-mount né sửa generator (KISS) |
| Bảo mật `/metrics` | **Giữ nguyên** | Mọi exporter chỉ ở network `monitoring`, không expose — repo đã làm ĐÚNG |
| Exporter app (DB) | **Hoãn (YAGNI)** | Stack hiện chỉ có proxy+monitoring, **không có** Postgres/MySQL/Redis. Chỉ thêm khi có DB thật |
| Pushgateway | **Hoãn** | Chưa có batch/cron job. Nhiều anti-pattern |

---

## Roadmap thống nhất

| Tầng | Hạng mục | Công sức | Giá trị | Nguồn |
|------|----------|----------|---------|-------|
| **P0** | Vá 3 lỗi dashboard hiện có | ~10 phút | Sửa số liệu sai đang hiển thị | r2 |
| **P1** | Alertmanager + 11 alert rules + Telegram | ~3 file mới + sửa nhẹ | **Bít lỗ hổng "được gọi dậy"** | r1 |
| **P1** | Blackbox exporter (uptime + SSL expiry) | 2 file + job scrape | **Bít lỗ hổng "khách vào được không"** | r3 |
| **P1** | Dashboard `00-overview-noc.json` | 1 file JSON | Màn trực 1-nhìn-biết-sống-chết (4 Golden Signals) | r2 |
| **P2** | Bổ sung panel USE/RED còn thiếu | sửa 3 JSON | Chiều sâu chẩn đoán (swap/inode/IO/throttle/OOM…) | r2 |
| **P2** | Loki 3.7 + Alloy (log tập trung) | 3 file + datasource | Xem log cạnh metric | r3 |
| **P3** | DB exporter (postgres/redis/mysqld) | 1 file/exporter | **Chỉ khi** stack chạy DB đó | r3 |
| **P3** | Pushgateway | 1 file | **Chỉ khi** có cron/backup cần báo cáo | r3 |
| **∞** | Cardinality, retention, version-pin | liên tục | Chống phình TSDB, ổn định | r3 |

---

## P0 — Vá 3 lỗi dashboard (đã xác minh tận dòng)

| Lỗi | File:dòng | Hiện tại | Sửa thành |
|-----|-----------|----------|-----------|
| RAM gồm page cache → sai áp lực OOM | `grafana/dashboards/cadvisor.json:47,66` | `container_memory_usage_bytes` | `container_memory_working_set_bytes` |
| Méo tỉ lệ 5xx khi traffic thấp | `grafana/dashboards/traefik.json:51` | `clamp_min(<mẫu số>,1)` | bỏ `clamp_min`; nếu lo NaN thì bọc `>0` ở alert, không ép mẫu số |
| CPU stat thiếu gộp (sai khi >1 instance) | `grafana/dashboards/node-exporter.json:46` | `100 - avg(rate(...idle...))*100` | `100*(1 - avg by(instance)(rate(...idle...)))` |

Provisioning tự nạp lại sau 30s — **không cần `setup.sh`, không restart Grafana**.

## P1 — Ba mảnh bít lỗ hổng lớn nhất

**1. Alerting (r1):** thêm `services/alertmanager.md` (cờ `ALERTMANAGER`, network `monitoring`, secret Telegram qua env + flag `--config.expand-environment-variables`) + 2 khối `alerting:`/`rule_files:` vào `prometheus.yml` + mount `prometheus/rules/` + file `alerts.yml` (11 alert: InstanceDown, TargetMissing, HighMemory, DiskAlmostFull, DiskWillFillSoon, HostHighLoad, ContainerKilled, ContainerRestartLoop, ContainerHighMemory, Traefik5xxHigh, TraefikHighLatency, TraefikServiceDown) + `alertmanager.yml` (routing + group_by + inhibition chống alert fatigue). PromQL & YAML đầy đủ trong report r1 §D–E.

**2. Blackbox (r3):** `services/blackbox-exporter.md` + `blackbox/blackbox.yml` (module http_2xx/tcp/icmp) + job multi-target `blackbox-http` trong `prometheus.yml` (relabel `__param_target`). Cho uptime (`probe_success==0`), SSL expiry (`(probe_ssl_earliest_cert_expiry-time())/86400 < 14`), status, latency đầu-cuối từng domain. Config sẵn-dùng trong report r3 §1.

**3. Dashboard NOC (r2):** `grafana/dashboards/00-overview-noc.json` — 4 hàng: Up/Down · Saturation host (USE) · RED Traefik · Cảnh báo sớm (disk-predict/OOM/throttle/drift). PromQL từng panel trong report r2 §D. **Giá trị cao nhất / ít công nhất.**

## P2 — Chiều sâu (khi P1 ổn định)

- **Panel USE/RED còn thiếu (r2 §A–C):** node-exporter — swap, inode, disk predict_linear, IO %util & await, net errors/drops, FD%, uptime, time-drift, load/core; cAdvisor — CPU throttling, RAM-vs-limit, OOM, top-N; Traefik — router-level, in-flight, p99, 4xx tách.
- **Loki + Alloy (r3 §2):** `services/loki.md` (bind-mount) + `services/alloy.md` (đọc docker.sock ro) + `alloy/config.alloy` (River) + `grafana/provisioning/datasources/loki.yml`. **Phải set Loki retention** (mặc định vô hạn).

## P3 — Theo nhu cầu (đừng làm sớm)

DB exporter chỉ khi có DB tương ứng; Pushgateway chỉ khi có batch/backup job. Chi tiết r3 §3–4.

---

## Điểm điều phối chéo (giá trị của việc tổng hợp)

1. **PromQL dùng chung — đừng viết 2 lần.** Ngưỡng đỏ của r2 (disk<4h, OOM>0, throttle>25%, 5xx>5%, FD>90%) và biểu thức blackbox của r3 (site-down, cert<14d) **chính là** alert rules của r1. Khi triển khai blackbox, **bổ sung 2 alert vào `alerts.yml`**: `BlackboxProbeFailed` (`probe_success==0`) và `SSLCertExpiringSoon` (`(probe_ssl_earliest_cert_expiry-time())/86400 < 14`) — r1 chưa có vì lúc đó chưa có blackbox.
2. **Restart count:** cAdvisor **không** export restart count trong Docker Compose thuần (`container_start_time_seconds` là hằng số). Nếu thực sự cần đếm restart → thêm `docker_state_exporter` (P3, optional). Tạm thời `ContainerKilled`/`ContainerRestartLoop` của r1 (dựa `container_last_seen`) đã phủ được "container biến mất/restart loop".
3. **Mọi target mới sửa tay `prometheus.yml`** (scrape config tĩnh, không codegen) — đúng cho blackbox + mọi exporter.

## Đính chính / xác minh của lead

- **Time-drift (r2 A10):** r2 ghi cần `--cap-add=SYS_TIME`. **Đính chính:** đọc `node_timex_offset_seconds` chỉ gọi `adjtimex` chế độ đọc → **không cần** cap (cap chỉ cần khi *ghi* clock). Đã kiểm `services/node-exporter.md`: không có cap đó, panel **vẫn chạy trên Linux host thật**. Trên Docker Desktop/macOS metric phản ánh VM (ít ý nghĩa).
- **Version pin:** r1 cảnh báo nguồn web mâu thuẫn (Alertmanager `v0.28.1` vs nghi-hallucination `v0.33`). **Chưa pin cứng** — verify bằng `docker pull prom/alertmanager` / trang releases trước khi điền `.env`. Tương tự Alloy (`v1.10.0` là ước lượng).
- **Môi trường:** host metrics (disk/load/OOM) chỉ **đáng tin trên Linux production**. Trên Docker Desktop/macOS hiện tại một số sẽ "No data" — không phải lỗi cấu hình (CLAUDE.md đã ghi). Alert host thực sự có ý nghĩa khi deploy lên server Linux.

---

## Câu hỏi cần người dùng quyết (trước khi triển khai)

1. **Môi trường đích thật** là Linux production hay vẫn Docker Desktop? (quyết định độ tin cậy của alert host)
2. **Kênh thông báo:** Telegram (khuyến nghị) — nếu đồng ý cần chuẩn bị `TELEGRAM_BOT_TOKEN` (@BotFather) + `TELEGRAM_CHAT_ID`. Hay Slack/email?
3. **Blackbox:** liệt kê domain probe **tay** trong `prometheus.yml` (KISS) hay mở rộng `setup.sh` sinh tự động từ `Host()` trong `services/*.md`? Và `DOMAIN` thật là gì?
4. **Expose UI ra ngoài?** Alertmanager/Prometheus mặc định để nội bộ (an toàn). Có muốn route qua Traefik + basic-auth không?
5. **Ngưỡng SLO:** chấp nhận mặc định (5xx>5%, p95>1s, CPU>80%) hay chỉnh theo tải thực?
6. **Loki retention:** đề xuất 31 ngày (khớp Prometheus 30d) — đồng ý?

---

## Nguồn (đã researcher xác minh)

- Prometheus / Alertmanager config docs · awesome-prometheus-alerts (`_data/rules.yml`) · Traefik v3 metrics reference
- prometheus/blackbox_exporter `example.yml` · Grafana Alloy docs (`loki.source.docker`) · Loki docs
- Grafana.com dashboards: Node Exporter Full **1860**, Traefik Official **17346**, cAdvisor **19908**
- endoflife.date (Promtail EOL, version cross-check)
