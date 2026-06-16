---
phase: 4
title: "P1 NOC Overview Dashboard"
status: pending
priority: P1
effort: "0.5d"
dependencies: [1]
---

# Phase 4: P1 — Dashboard "00 — Overview / NOC"

## Overview
Một màn hình trực "1-nhìn-biết-sống-chết" hiện thực hóa 4 Golden Signals: Up/Down + Saturation host (USE) + RED Traefik + cảnh báo sớm. Giá trị cao nhất / ít công nhất sau khi đã vá lỗi PromQL (phụ thuộc phase 1 để dùng biểu thức đúng).

## Requirements
- Functional: 4 hàng panel — sống/chết, saturation host, RED Traefik, cảnh báo sớm (disk-predict/OOM/throttle/drift).
- Non-functional: dùng biến `${datasource}` (tên `Prometheus`) như 3 dashboard hiện có; prefix `00-` để nổi lên đầu danh sách.

## Architecture
File mới `grafana/dashboards/00-overview-noc.json`, schemaVersion 39 (khớp dashboard hiện có), templating biến `datasource` type `datasource` query `prometheus`. Provisioning tự nạp ≤30s.

## Related Code Files
- Create: `grafana/dashboards/00-overview-noc.json`

## Test-First (TDD)
1. `jq empty grafana/dashboards/00-overview-noc.json` PASS.
2. Mỗi `expr` chạy được trong Prometheus (copy vào Graph, không lỗi parse).
3. Sau nạp: panel "Up/Down" xanh cho job đang chạy; không panel nào "No data" (trên Linux; trên Docker Desktop ghi chú panel host có thể trống).

## Implementation Steps
1. Tạo JSON theo khung 4 hàng (PromQL trong report researcher-2 §D):
   - **Hàng 1 — Up/Down:** `up{job="node-exporter"}`, `up{job="cadvisor"}`, `up{job="traefik"}`, `up{job="prometheus"}`, `count(count by(name)(container_last_seen{name!=""}))`. Stat đỏ/xanh (mapping value 0→đỏ, 1→xanh).
   - **Hàng 2 — Saturation host (USE):** CPU% `100*(1-avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])))`; RAM% `100*(1-node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)`; Disk% `100*(1-node_filesystem_avail_bytes{mountpoint="/"}/node_filesystem_size_bytes{mountpoint="/"})`; load/core `node_load1/count(count by(cpu)(node_cpu_seconds_total))`. Threshold đỏ.
   - **Hàng 3 — RED Traefik:** req/s `sum(rate(traefik_service_requests_total[5m]))`; 5xx% (biểu thức đã sửa, không clamp_min); p95 `histogram_quantile(0.95, sum(rate(traefik_service_request_duration_seconds_bucket[5m])) by (le))`.
   - **Hàng 4 — Cảnh báo sớm:** disk đầy <24h `predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 24*3600) < 0`; OOM `sum by(name)(increase(container_oom_events_total{name!=""}[1h])) > 0`; throttle `... cfs_throttled .../cfs_periods... > 0.25`; time drift `node_timex_offset_seconds`.
2. Đặt `gridPos` hợp lý (4 hàng × các cột), `refresh: "30s"`, `time: now-6h`.
3. Lưu → kiểm Grafana.

## Success Criteria
- [ ] `jq empty` PASS.
- [ ] Dashboard xuất hiện đầu danh sách (prefix `00-`).
- [ ] Hàng Up/Down phản ánh đúng trạng thái (test bằng `docker stop` 1 service → ô chuyển đỏ).
- [ ] RED Traefik dùng biểu thức 5xx đã sửa ở phase 1 (không clamp_min).

## Risk Assessment
- **Thấp.** Chỉ thêm 1 file dashboard. Rủi ro: JSON sai → `jq` bắt; uid datasource phải là `${datasource}` (không cứng) để không "No data".
- Panel host (disk-predict, OOM, time-drift) có thể trống trên Docker Desktop — thêm text panel ghi chú "host panels cần Linux".
