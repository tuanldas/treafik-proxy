---
phase: 5
title: "P2 USE-RED Panels"
status: pending
priority: P2
effort: "1d"
dependencies: [1]
---

# Phase 5: P2 — Bổ sung panel USE/RED còn thiếu

## Overview
Bổ sung các panel saturation/error then chốt còn thiếu vào 3 dashboard hiện có, phủ đủ USE (host) và RED (Traefik). Phụ thuộc phase 1 vì sửa cùng 3 file dashboard (tránh xung đột — làm sau khi phase 1 đã vá lỗi).

## Requirements
- Functional: thêm panel theo USE (host/container) và RED (Traefik) với PromQL + ngưỡng đỏ đã verify.
- Non-functional: không phá panel cũ; giữ biến `${datasource}`/`$instance`.

## Architecture
Sửa 3 file JSON trong `grafana/dashboards/`. Provisioning tự nạp. Mỗi panel = 1 entry trong mảng `panels` với `gridPos` mới (đặt dưới panel hiện có).

## Related Code Files
- Modify: `grafana/dashboards/node-exporter.json` (swap, inode, disk predict, IO %util & await, net errors/drops, FD%, uptime, time-drift, load/core)
- Modify: `grafana/dashboards/cadvisor.json` (CPU throttling, RAM-vs-limit bar, OOM, top-N CPU)
- Modify: `grafana/dashboards/traefik.json` (router-level req/s, entrypoint, in-flight, p99, 4xx tách)

## Test-First (TDD)
1. `jq empty` PASS cho cả 3 file sau mỗi lần sửa.
2. Mỗi `expr` mới chạy không lỗi parse trong Prometheus.
3. So sánh trước/sau: số panel tăng đúng số thêm; panel cũ không đổi vị trí gây vỡ layout.

## Implementation Steps
1. **node-exporter.json** — thêm panel (PromQL report researcher-2 §A): A1 load/core, A2 swap%, A3 disk predict (giờ còn lại), A4 inode%, A5 disk %util, A6 IO await đọc/ghi, A7 net errors/drops, A8 FD%, A9 uptime, A10 time-drift (`node_timex_offset_seconds` — **không cần** `--cap-add=SYS_TIME` để đọc; chạy trên Linux host thật, có thể trống trên Docker Desktop).
2. **cadvisor.json** — thêm (report §B): B1 CPU throttling (`cfs_throttled/cfs_periods`), B2 RAM-vs-limit bar gauge (working_set / spec_memory_limit, lọc limit>0), B4 OOM (`increase(container_oom_events_total[1h])`), B5 top-N CPU. **Lưu ý:** restart count KHÔNG khả dụng từ cAdvisor Docker thuần (`container_start_time_seconds` hằng số) → để phase 7 nếu cần (docker_state_exporter); ở đây dùng "uptime container" thay thế.
3. **traefik.json** — thêm (report §C): C2 4xx% tách, C3 req/s theo `router` (label `addRoutersLabels: true` đã bật ở `traefik.yml:65`), C4 theo entrypoint, C5 in-flight, C6 p99 stat.
4. Mỗi lần sửa 1 file → `jq empty` → kiểm Grafana.

## Success Criteria
- [ ] `jq empty` PASS cả 3 file.
- [ ] Panel mới hiện data trên Linux (ghi chú panel có thể trống trên Docker Desktop: OOM, IO, time-drift).
- [ ] Layout cũ không vỡ; biến `$instance` hoạt động ở node-exporter.

## Risk Assessment
- **Trung bình** (sửa nhiều JSON tay dễ lỗi cú pháp) — `jq empty` sau mỗi sửa là bắt buộc.
- **Trùng file với phase 1** → BẮT BUỘC làm sau phase 1, không song song, để tránh ghi đè bản sửa lỗi.
- Một số metric (OOM, IO latency, time-drift, conntrack) vắng trên Docker Desktop/macOS — bình thường, có thật trên Ubuntu/CentOS.
- cAdvisor `container_oom_events_total` cần cAdvisor ≥ v0.39.1 — xác nhận version đang dùng.
