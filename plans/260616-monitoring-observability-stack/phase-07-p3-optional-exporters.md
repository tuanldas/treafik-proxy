---
phase: 7
title: "P3 Optional Exporters"
status: pending
priority: P3
effort: "0.5d/exporter"
dependencies: [2]
---

# Phase 7: P3 — Exporter tùy chọn (DB + Pushgateway)

## Overview
**Optional / YAGNI.** Chỉ triển khai khi stack thực sự chạy backend tương ứng. Stack hiện **không có** Postgres/MySQL/Redis/batch job → mặc định KHÔNG kích hoạt. Đưa vào plan để có khuôn sẵn-dùng khi cần. Phụ thuộc phase 2 để bổ sung alert tương ứng (exporter down, replication lag).

## Requirements
- Functional (khi bật): mỗi DB có exporter riêng ở network `monitoring`, secret/DSN từ `.env`; Pushgateway nhận metric job batch.
- Non-functional: chỉ thêm exporter có backend thật; secret không hardcode; mysqld dùng `.my.cnf` (gitignore).

## Architecture
Mỗi exporter = 1 `services/<ten>.md` (mẫu `node-exporter.md`), network `monitoring`, + 1 job tĩnh trong `prometheus.yml`. Pushgateway: job `honor_labels: true`.

## Related Code Files (chỉ tạo khi cần)
- Create (cond.): `services/postgres-exporter.md` — `DATA_SOURCE_NAME=${POSTGRES_DSN}`
- Create (cond.): `services/redis-exporter.md` — `REDIS_ADDR`/`REDIS_PASSWORD`
- Create (cond.): `services/mysqld-exporter.md` + `mysqld/.my.cnf` (gitignore)
- Create (cond.): `services/pushgateway.md`
- Modify: `prometheus/prometheus.yml` (job tương ứng)
- Modify: `prometheus/rules/alerts.yml` (alert exporter down / replication lag — tùy backend)
- Modify: `.env` (cờ + DSN/secret), `.gitignore` (`mysqld/.my.cnf`)

## Test-First (TDD) — khi bật
1. `docker compose config >/dev/null` hợp lệ.
2. Exporter `up == 1` trong Prometheus `/targets` khi backend tồn tại.
3. Metric chủ chốt có giá trị: `pg_up`/`redis_up`/`mysql_up == 1`.
4. `promtool check rules` PASS nếu thêm alert.

## Implementation Steps (khi có backend)
1. **postgres_exporter** (`quay.io/prometheuscommunity/postgres-exporter`, :9187) — env `DATA_SOURCE_NAME=${POSTGRES_DSN}`. Metric: `pg_up`, `pg_stat_database_numbackends`, `pg_stat_replication`/lag, cache hit, `pg_database_size_bytes`.
2. **redis_exporter** (`oliver006/redis_exporter`, :9121) — `REDIS_ADDR`, `REDIS_PASSWORD`. Metric: `redis_up`, connected_clients, mem used/max, keyspace hit/miss, evicted, replication.
3. **mysqld_exporter** (`prom/mysqld-exporter`, :9104) — mount `./mysqld/.my.cnf:/etc/mysql/.my.cnf:ro` (KHÔNG env DSN — lộ qua `docker inspect`). Tạo user `exporter` với `PROCESS, REPLICATION CLIENT, SELECT`. **Thêm `mysqld/.my.cnf` vào `.gitignore`.** Metric: `mysql_up`, threads_connected, slow_queries, `seconds_behind_master`, buffer pool hit.
4. **Pushgateway** (`prom/pushgateway`, :9091) — **CHỈ** khi có cron/backup job. Scrape `honor_labels: true`. Alert: `time()-backup_last_success_timestamp_seconds > 86400`, `time()-push_time_seconds > 3600`.
5. Thêm job tĩnh vào `prometheus.yml`; alert tương ứng vào `alerts.yml`.

## Success Criteria
- [ ] (Khi bật) exporter `up==1`, metric chủ chốt có giá trị.
- [ ] mysqld dùng `.my.cnf` đã gitignore; không secret trong compose/inspect.
- [ ] Không kích hoạt exporter cho backend không tồn tại (YAGNI).

## Risk Assessment
- **YAGNI:** nguy cơ thêm exporter thừa cho DB không có → mặc định tắt, chỉ bật khi xác nhận backend.
- **Pushgateway anti-pattern:** metric không tự expire (job phải tự DELETE), single point of failure, không phản ánh "job có chạy". Chỉ dùng cho batch thật. Bỏ nginx-exporter (Traefik đã có RED).
- **Cardinality:** DSN/label tĩnh → lành tính; nhưng Pushgateway + label động (timestamp/UUID) = cardinality bomb vĩnh viễn — cấm.
- **Secret:** DSN/password chỉ trong `.env`; mysqld bắt buộc `.my.cnf` gitignore.
