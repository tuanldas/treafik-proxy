---
phase: 1
title: "P0 Fix Dashboard Errors"
status: pending
priority: P1
effort: "30m"
dependencies: []
---

# Phase 1: P0 — Vá 3 lỗi dashboard hiện có

## Overview
Sửa 3 lỗi PromQL/metric đã xác minh tận dòng trong dashboard provisioned, làm số liệu RAM/tỉ-lệ-5xx/CPU hiển thị sai. Rủi ro ~0, không thêm service. Grafana provisioning tự nạp lại sau 30s (`updateIntervalSeconds: 30`) — không cần `setup.sh`, không restart.

## Requirements
- Functional: RAM container phản ánh áp lực OOM thật (working set, loại page cache); tỉ lệ 5xx không méo khi traffic thấp; CPU% đúng khi có >1 instance.
- Non-functional: giữ nguyên bố cục/biến `${datasource}`; không phá panel khác.

## Architecture
Dashboard JSON nằm `grafana/dashboards/*.json`, mount vào `/var/lib/grafana/dashboards`, provider `default` tự nạp mỗi 30s, `allowUiUpdates: true`. Sửa file = Grafana cập nhật, không downtime.

## Related Code Files
- Modify: `grafana/dashboards/cadvisor.json` (dòng 47, 66)
- Modify: `grafana/dashboards/traefik.json` (dòng 51)
- Modify: `grafana/dashboards/node-exporter.json` (dòng 46)

## Test-First (TDD)
Định nghĩa kiểm chứng TRƯỚC khi sửa:
1. **JSON hợp lệ:** `for f in grafana/dashboards/*.json; do jq empty "$f" || echo "FAIL $f"; done` → không lỗi.
2. **Kỳ vọng số liệu:** với cùng thời điểm, `container_memory_working_set_bytes` ≤ `container_memory_usage_bytes` (working set loại cache). Ghi lại 2 giá trị trước/sau để chứng minh panel đổi.
3. **5xx không méo:** khi traffic≈0, biểu thức mới trả `NaN`/0 (không phải số bị ép bởi `clamp_min`); khi có traffic, tỉ lệ khớp `5xx/total`.
4. **CPU multi-instance:** thêm tạm 1 instance giả (hoặc lý luận PromQL) → `avg by(instance)` không trộn series.

## Implementation Steps
1. **cadvisor.json** — đổi `container_memory_usage_bytes` → `container_memory_working_set_bytes` tại:
   - dòng 47 (panel "Tổng RAM container"): `sum(container_memory_working_set_bytes{name!=""})`
   - dòng 66 (panel "RAM theo container"): `sum by (name) (container_memory_working_set_bytes{name!=""})`
2. **traefik.json** — dòng 51, bỏ `clamp_min(...,1)` ở mẫu số:
   ```promql
   100 * sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) / sum(rate(traefik_service_requests_total[5m]))
   ```
   (Nếu lo NaN khi 0 traffic: xử lý ở alert bằng `> 0`, KHÔNG ép mẫu số ở dashboard.)
3. **node-exporter.json** — dòng 46, thêm `by(instance)`:
   ```promql
   100 * (1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle",instance="$instance"}[5m])))
   ```
4. Lưu file → đợi ≤30s → mở Grafana kiểm 3 panel.

## Success Criteria
- [ ] `jq empty` PASS cho cả 3 file.
- [ ] Panel RAM cAdvisor giảm xuống giá trị working-set (chứng minh bằng 2 số liệu trước/sau).
- [ ] Panel 5xx% Traefik không còn bị `clamp_min`; hiển thị đúng tỉ lệ khi có traffic.
- [ ] Panel CPU node-exporter có `avg by(instance)`.
- [ ] Không panel nào khác bị vỡ (so sánh visual nhanh).

## Risk Assessment
- **Thấp.** Chỉ đổi biểu thức PromQL. Rủi ro duy nhất: gõ sai JSON → `jq empty` bắt được trước khi Grafana nạp. Rollback: `git checkout` file dashboard.
- Trên Docker Desktop một số series cAdvisor có thể khác Linux, nhưng phép so sánh working_set ≤ usage vẫn đúng.
