---
phase: 3
title: "P1 Blackbox Uptime and SSL"
status: pending
priority: P1
effort: "0.5d"
dependencies: [2]
---

# Phase 3: P1 — Blackbox exporter (uptime + SSL expiry)

## Overview
Giám sát uptime/SSL/status/latency **từ góc nhìn người dùng** cho từng domain Traefik route — bít lỗ hổng "khách có vào được không". Bổ sung 2 alert (probe fail, cert sắp hết hạn) vào `alerts.yml` của phase 2 (vì vậy phụ thuộc phase 2).

## Requirements
- Functional: probe HTTP(S) từng domain, đo `probe_success`, `probe_ssl_earliest_cert_expiry`, status code, thời gian phản hồi.
- Functional: cảnh báo khi site down hoặc cert < 14 ngày.
- Non-functional: blackbox chỉ ở network `monitoring`, không expose; probe thưa (30s) để giảm tải/cardinality.

## Architecture
Multi-target pattern: Prometheus gửi URL qua `?target=` tới `/probe`, `relabel_configs` hoán `__address__` thành `blackbox-exporter:9115`. Danh sách URL nằm trong `static_configs.targets` của Prometheus (ghi domain **tường minh** — `prometheus.yml` không nội suy `${DOMAIN}`).

## Related Code Files
- Create: `services/blackbox-exporter.md` (service, network `monitoring`)
- Create: `blackbox/blackbox.yml` (module http_2xx / tcp / icmp)
- Modify: `prometheus/prometheus.yml` (job `blackbox-http` multi-target + relabel; job self-metric)
- Modify: `prometheus/rules/alerts.yml` (thêm nhóm `blackbox`: BlackboxProbeFailed, SSLCertExpiringSoon, SSLCertExpired)
- Modify: `.env` (cờ `BLACKBOX_EXPORTER`, version)

## Test-First (TDD)
1. `docker compose config >/dev/null` hợp lệ sau khi bật cờ.
2. Sau up: `curl -s 'http://localhost:9115/probe?target=https://<domain>&module=http_2xx'` (exec trong network) trả `probe_success 1` cho site sống.
3. Prometheus `/targets` cho job `blackbox-http` ở trạng thái UP; metric `probe_ssl_earliest_cert_expiry` > 0 với site HTTPS.
4. `promtool check rules` PASS sau khi thêm nhóm blackbox.
5. PromQL `(probe_ssl_earliest_cert_expiry - time())/86400` trả số ngày hợp lý.

## Implementation Steps
1. **`services/blackbox-exporter.md`** — `prom/blackbox-exporter:${BLACKBOX_EXPORTER_VERSION:-<verify>}`, command `--config.file=/etc/blackbox_exporter/config.yml`, mount `./blackbox/blackbox.yml:...:ro`, network `monitoring`. (ICMP cần `cap_add: [NET_RAW]` — chỉ thêm nếu probe ICMP.)
2. **`blackbox/blackbox.yml`** — module `http_2xx` (follow_redirects, `fail_if_not_ssl: false`), `http_2xx_strict_tls` (`fail_if_not_ssl: true`), `tcp_connect`, `icmp`. Nguồn: blackbox_exporter `example.yml`.
3. **`prometheus/prometheus.yml`** — job `blackbox-http` (`metrics_path: /probe`, `params.module: [http_2xx]`, `scrape_interval: 30s`, `static_configs.targets` = danh sách URL **tường minh**, `relabel_configs` chuẩn 3 bước → `blackbox-exporter:9115`) + job `blackbox-exporter` (self).
4. **`prometheus/rules/alerts.yml`** — thêm nhóm `blackbox`:
   - `BlackboxProbeFailed`: `probe_success == 0` for 2m, critical.
   - `SSLCertExpiringSoon`: `(probe_ssl_earliest_cert_expiry - time())/86400 < 14` for 1h, warning.
   - `SSLCertExpired`: `probe_ssl_earliest_cert_expiry - time() <= 0`, critical.
5. **`.env`** — `BLACKBOX_EXPORTER=true`, `BLACKBOX_EXPORTER_VERSION=` (verify).
6. Chạy TDD.

## Success Criteria
- [ ] Job blackbox UP trong Prometheus `/targets`.
- [ ] `probe_success` + `probe_ssl_earliest_cert_expiry` có giá trị cho mỗi domain.
- [ ] 3 alert blackbox parse PASS; test bằng domain giả/sai để thấy `BlackboxProbeFailed` fire.
- [ ] Blackbox không expose ra ngoài (chỉ `monitoring`).

## Risk Assessment
- **Domain tường minh:** `prometheus.yml` không đọc `${DOMAIN}` → phải điền domain thật; nếu nhiều domain, danh sách dài. Quyết định "liệt kê tay vs tự sinh từ `services/*.md`" để mở (xem Open Questions plan). Mặc định: liệt kê tay (KISS).
- **Probe nội bộ vs ngoài:** blackbox trong network `monitoring` probe qua tên Traefik/`websecure` — đảm bảo blackbox cùng được Traefik phục vụ hoặc probe IP công khai. Cần xác nhận đường probe (qua `proxy` network hay public URL).
- **SSL=false (Cloudflare origin HTTP):** nếu origin không TLS, dùng module thường, cert đo ở phía Cloudflare (ngoài tầm) — ghi chú.
