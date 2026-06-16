---
title: "Giam sat & canh bao toan dien cho stack Traefik/Prometheus/Grafana (P0-P3)"
description: "Va loi dashboard, them Alertmanager + alert rules (3 kenh chon qua env), Blackbox uptime/SSL, dashboard NOC, panel USE/RED, Loki/Alloy logs, exporter tuy chon"
status: pending
priority: P1
branch: "main"
tags: [observability, prometheus, grafana, alerting, traefik]
blockedBy: []
blocks: []
created: "2026-06-16T09:06:40.959Z"
createdBy: "ck:plan"
source: skill
---

# Giám sát & cảnh báo toàn diện cho stack Traefik/Prometheus/Grafana (P0–P3)

## Overview

Stack hiện thu metric tốt (Prometheus 4 job) + 3 dashboard, nhưng **không có cảnh báo**, **không giám sát uptime/SSL đầu-cuối**, và có **3 lỗi PromQL** làm số liệu sai. Plan này triển khai đầy đủ roadmap P0→P3 từ bản tổng hợp research (`plans/reports/research-summary-260616-1529-server-observability.md`), **bám đúng cơ chế repo**: mỗi service = 1 file `services/<ten>.md` (đúng 1 block ```yaml), bật bằng cờ `.env`, `setup.sh` sinh `docker-compose.yml`. Secret từ `.env`, không hardcode.

**Bối cảnh đã chốt với người dùng:**
- **Môi trường đích:** Linux production **Ubuntu + CentOS/RHEL**. Dev hiện tại trên macOS/Docker Desktop → alert/metric host chỉ đáng tin đầy đủ trên Linux thật; plan tách rõ điều này.
- **Kênh cảnh báo:** **cả 3 — Telegram + Slack + Email**, **bật/tắt từng kênh qua `.env`**. Hiện thực bằng cách `setup.sh` sinh `alertmanager.generated.yml` theo cờ (tái dùng pattern đã có khi sinh `auth.generated.yml`).
- **Phạm vi:** đầy đủ P0→P3 (P3 exporter DB/Pushgateway là optional/YAGNI — chỉ kích hoạt khi có backend tương ứng).

## Phases

| Phase | Tier | Name | Status | Phụ thuộc |
|-------|------|------|--------|-----------|
| 1 | P0 | [Fix Dashboard Errors](./phase-01-p0-fix-dashboard-errors.md) | ✅ Done | — |
| 2 | P1 | [Alertmanager + Alert Rules (3 kênh qua env)](./phase-02-p1-alertmanager-and-alert-rules.md) | ✅ Done (cần secret để test gửi) | — |
| 3 | P1 | [Blackbox Uptime + SSL](./phase-03-p1-blackbox-uptime-and-ssl.md) | ✅ Done (cần stack chạy để probe thật) | 2 |
| 4 | P1 | [NOC Overview Dashboard](./phase-04-p1-noc-overview-dashboard.md) | ✅ Done | 1 |
| 5 | P2 | [USE/RED Panels bổ sung](./phase-05-p2-use-red-panels.md) | ✅ Done | 1 |
| 6 | P2 | [Loki + Alloy Logs](./phase-06-p2-loki-and-alloy-logs.md) | ✅ Done (test SELinux trên CentOS) | — |
| 7 | P3 | [Exporter tùy chọn (DB + Pushgateway)](./phase-07-p3-optional-exporters.md) | ⏸ Optional — chờ backend (YAGNI) | 2 |
| 8 | P1 | [Discord channel (kênh báo thứ 4)](./phase-08-p1-discord-channel.md) | ✅ Done (cần webhook để test gửi) | 2 |

**Thứ tự khuyến nghị:** 1 (nhanh, rủi ro ~0) → 2 → 3 → 4 → 5 → 6 → 7 (optional). Phase 1, 2, 6 độc lập, có thể làm song song nếu cần.

## Quyết định toàn cục (chốt từ research + đọc codebase)

1. **Engine alert:** Prometheus Alertmanager (không Grafana Unified Alerting) — hợp GitOps, rule là code, alert độc lập Grafana.
2. **Receiver chọn qua env:** `setup.sh` sinh `alertmanager/alertmanager.generated.yml` từ cờ `ALERT_TELEGRAM/ALERT_SLACK/ALERT_EMAIL/ALERT_DISCORD` (Discord native v0.33.0 — verify amtool), ghi **thẳng giá trị secret** từ `.env` vào file (dùng `get_raw` — đúng pattern `auth.generated.yml` đang chứa hash mật khẩu thật). File **gitignore** (nhất quán với `docker-compose.yml`, `auth.generated.yml`). **Đã verify (docker pull, 2026-06-16): Alertmanager `v0.33.0` KHÔNG có flag `--config.expand-environment-variables`** → KHÔNG dùng env-expansion; ghi giá trị vào file gitignore là cách KISS + nhất quán repo (`docker inspect` cũng không lộ vì secret không nằm trong `environment:`).
3. **Volume service mới:** dùng **bind-mount** (`./loki/data`, `./alertmanager/data`) — header volume trong `setup.sh` hardcode chỉ `prometheus-data`/`grafana-data`; bind-mount né sửa generator (KISS).
4. **Scrape config tĩnh:** mọi target mới (blackbox, exporter) **thêm tay** vào `prometheus/prometheus.yml` (đây là thiết kế hiện tại, không phải lỗi).
5. **Bảo mật `/metrics`:** mọi exporter chỉ ở network `monitoring`, không gắn label Traefik → không expose. Giữ nguyên (repo đã đúng).
6. **Dashboard tự viết** dùng biến `${datasource}` (tên `Prometheus`) như 3 dashboard hiện có; dashboard cộng đồng (1860/17346/19908) chỉ import làm bản tra cứu, **phải đổi datasource cứng** trước khi lưu.
7. **Version pin:** verify bằng `docker pull` trước khi khóa trong `.env`; không dùng `latest`. **Đã verify: Alertmanager = `v0.33.0`** (build 2026-06-12). Các image còn lại (blackbox, loki, alloy, exporter) verify khi triển khai từng phase.
8. **Log/metric dùng chung nhãn `container`** (Alloy relabel `__meta_docker_container_name` → khớp nhãn `name` của cAdvisor).

## Acceptance criteria (toàn plan)

- [ ] `./setup.sh` chạy sạch với mọi tổ hợp cờ mới; `docker compose config` hợp lệ.
- [ ] `promtool check rules prometheus/rules/*.yml` PASS; `amtool check-config` PASS.
- [ ] Stop thử 1 container → nhận cảnh báo qua đúng (các) kênh đang bật trong `.env`.
- [ ] 3 lỗi dashboard đã sửa; số liệu RAM/5xx/CPU hiển thị đúng.
- [ ] Blackbox probe trả `probe_success` + `probe_ssl_earliest_cert_expiry` cho mỗi domain.
- [ ] Dashboard NOC + panel USE/RED bổ sung load không "No data" (trên Linux).
- [ ] Loki nhận log container, query LogQL trong Grafana được; retention đã set.
- [ ] Không secret nào bị commit; file generated đã gitignore.

## Open Questions (validate — xác nhận khi triển khai phase tương ứng)

1. **Blackbox (phase 3):** probe qua URL công khai (`https://x.${DOMAIN}` — cần DNS/cert thật) hay nội bộ qua network `proxy`? Danh sách domain **liệt kê tay** (KISS, mặc định) hay mở rộng `setup.sh` tự sinh từ `Host()` trong `services/*.md`?
2. **Expose UI:** route Alertmanager/Prometheus UI ra ngoài qua Traefik + `dashboard-auth@file`? **Mặc định: KHÔNG** (chỉ nội bộ, an toàn).
3. **Ngưỡng SLO (phase 2):** giữ mặc định community (5xx>5%, p95>1s, CPU>80%, disk<24h) hay chỉnh theo tải thực?
4. **Loki retention (phase 6):** đề xuất **31 ngày (744h)** khớp Prometheus 30d — đồng ý?
5. **Email SMTP (nếu `ALERT_EMAIL=true`):** provider nào (Gmail app-password / SES / SMTP nội bộ)? Cần điền `SMTP_*` trong `.env`.
6. **P3 exporter (phase 7):** stack sắp có DB (Postgres/MySQL/Redis) hoặc batch job? Nếu không → giữ phase 7 **tắt** (YAGNI).

> Không câu nào chặn **phase 1** (P0 vá lỗi — sẵn sàng cook ngay). Phase 2 chỉ cần secret kênh đã chọn (Telegram). Phase 3/6/7 cần các câu trên trước khi cook.

## Rollback chung

Mọi thay đổi compose đều qua `setup.sh` + cờ `.env`. Rollback = set cờ service mới về `false` (hoặc xóa khối thêm trong `prometheus.yml`) → `./setup.sh && docker compose up -d`. Dashboard/alert là file text, revert bằng git. Không có thay đổi phá hủy dữ liệu.

## Nguồn

- `plans/reports/research-summary-260616-1529-server-observability.md` (tổng hợp)
- `plans/reports/researcher-{1,2,3}-260616-*.md` (chi tiết alerting / dashboard / observability)
