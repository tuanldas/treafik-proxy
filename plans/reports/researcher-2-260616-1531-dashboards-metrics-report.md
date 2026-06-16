# Report — Dashboard & chỉ số chuẩn (USE / RED / 4 Golden Signals)

researcher-2 · 2026-06-16 15:31 · TASK #2 · stack: node-exporter + cAdvisor + Traefik + Prometheus/Grafana (Docker Compose)

## Executive summary

Stack đã có 3 dashboard provisioned (`grafana/dashboards/{node-exporter,cadvisor,traefik}.json`) — bố cục đúng, nhưng **thiếu nhiều tín hiệu saturation/error then chốt** và có **3 lỗi PromQL/metric** làm số liệu sai lệch. Khuyến nghị: (1) sửa tại chỗ 3 dashboard hiện có theo PromQL chuẩn USE/RED, (2) bổ sung panel còn thiếu (swap, inode, disk predict, IO %util/latency, net errors, FD, time drift; cAdvisor throttling + mem-vs-limit + OOM; Traefik router-level + in-flight + p99), (3) thêm **1 dashboard "00 — Overview / NOC"** tổng hợp sống-chết, (4) tùy chọn import dashboard cộng đồng (1860 / 17346 / 19908) làm bản tham chiếu chi tiết. Tất cả đặt vào `grafana/dashboards/` → provisioning tự nạp (`updateIntervalSeconds: 30`), không cần đụng `setup.sh`.

**3 lỗi cần sửa ngay (đã xác minh nguồn):**
1. cAdvisor RAM dùng `container_memory_usage_bytes` (gồm page cache) → phải `container_memory_working_set_bytes` để so với limit và phản ánh áp lực OOM thật.
2. Traefik tỉ lệ lỗi dùng `clamp_min(denominator,1)` → méo tỉ lệ khi traffic thấp (mẫu số bị ép =1 req/s).
3. node-exporter CPU stat panel `avg(rate(idle))*100` thiếu `by(instance)` — sai khi nhiều series; nên dùng dạng `100*(1-avg by(instance)(...idle))`.

**1 giới hạn môi trường quan trọng:** trong Docker Compose thuần (không K8s), **cAdvisor KHÔNG export restart count** — `container_start_time_seconds` là hằng số, không đổi sau restart (cadvisor#2169). Muốn đếm restart phải thêm `docker_state_exporter` (xem Unresolved). Trên Docker Desktop/macOS, `container_oom_events_total` có thể vắng (đọc `/dev/kmsg`).

## Key findings

### 1. Map khung lý thuyết → panel (áp vào đúng stack này)

| Framework | Áp cho | Tín hiệu | Metric/panel cụ thể trong stack |
|---|---|---|---|
| **USE** (Brendan Gregg) | Host & tài nguyên (node-exporter) | **U**tilization | CPU %busy, RAM used%, Disk used%, IO %util |
| | | **S**aturation | load1/core, swap in/out, IO await/queue, FD%, cAdvisor CPU throttle |
| | | **E**rrors | net errors/drops, disk errors, OOM events |
| **RED** (Tom Wilkie) | Dịch vụ HTTP (Traefik) | **R**ate | `traefik_service_requests_total` req/s |
| | | **E**rrors | tỉ lệ 5xx (+ 4xx tách riêng) |
| | | **D**uration | p50/p95/p99 từ `*_request_duration_seconds_bucket` |
| **4 Golden Signals** (Google SRE) | Tổng thể / NOC | Latency, Traffic, Errors, Saturation | Traefik p95 + req/s + 5xx% (3 cái đầu); host CPU/RAM/Disk/throttle (Saturation) |

Nguyên tắc: **USE cho "máy", RED cho "request", Golden Signals cho dashboard tổng/NOC.** Dashboard Overview ở mục 6 chính là hiện thực hóa 4 Golden Signals.

### 2. node-exporter — gap so với dashboard hiện có

Dashboard `node-exporter.json` hiện có: CPU%, RAM%, Disk/%, load1, RAM/Disk bytes, CPU-by-mode, net bytes, disk I/O bytes. **Thiếu** (theo USE): swap, inode, **disk-fill prediction**, **IO %util & latency (await)**, **net errors/drops**, **file descriptors**, **uptime**, **time drift**, **load/core**. Panel CPU stat có lỗi thiếu `by(instance)` (mục Evidence).

### 3. cAdvisor — gap so với dashboard hiện có

Dashboard `cadvisor.json` hiện có: số container, tổng CPU cores, tổng RAM, CPU/RAM/net theo container. **Thiếu (quan trọng nhất theo USE-saturation):** **CPU throttling** (`container_cpu_cfs_throttled_*`), **RAM vs limit %** (dùng working_set), **OOM events**, **top-N** (bar gauge), **restart count** (xem giới hạn môi trường). RAM panel dùng `usage_bytes` → nên đổi `working_set_bytes`.

### 4. Traefik — gap so với dashboard hiện có

Dashboard `traefik.json` hiện có: tổng req/s, 5xx%, open conns, p95, req/s theo service, theo code, latency p50/95/99 theo service. Khá tốt. **Thiếu:** **router-level** req/s (label `router` đã bật qua `addRoutersLabels: true` trong `traefik.yml:65`), **requests in-flight**, **4xx tách riêng**, **p99 stat ở hàng KPI**, **req/s theo entrypoint**. Lỗi `clamp_min` ở panel 5xx% (mục Evidence).

### 5. Dashboard cộng đồng đáng dùng (xác minh trên grafana.com)

| ID | Tên | Dùng cho | Lưu ý phiên bản |
|---|---|---|---|
| **1860** | Node Exporter Full | node-exporter (tham chiếu host đầy đủ) | rev16+ cần node_exporter ≥ v0.18; khuyến nghị bật collector `--collector.systemd --collector.processes`; biến `$instance` dựa `node_uname_info` |
| **17346** | Traefik Official Standalone | Traefik | Native prometheus metrics, lọc theo DataSource/Service/Entrypoint — **bản Traefik nên dùng**. (Cũ: 4475, 12250 "Traefik 2.2", 2870) |
| **19908** | cAdvisor "Docker Insights" | cAdvisor | Cho Docker/Compose; alt **193**, **14282**, **893**. Một số panel restart sẽ trống (giới hạn cAdvisor non-K8s) |

**Cách đưa vào theo repo:** tải JSON model (Grafana.com → Download JSON), lưu `grafana/dashboards/<ten>.json`. Provisioning (`grafana/provisioning/dashboards/dashboard.yml`) tự nạp từ `/var/lib/grafana/dashboards` mỗi 30s. **Cảnh báo tương thích:** JSON cộng đồng thường gắn `__inputs`/`DS_PROMETHEUS` và `uid` datasource cứng → trước khi lưu phải **đổi datasource về biến `${datasource}`/`Prometheus`** cho khớp `datasource.yml` (datasource tên `Prometheus`, `isDefault: true`), nếu không panel "No data". 3 dashboard tự viết của repo nhẹ và đã khớp sẵn — khuyến nghị **giữ dashboard tự viết làm chính, import cộng đồng làm bản tra cứu sâu** (đặt tên `1860-node-exporter-full.json`…), tránh trùng tiêu đề.

## Evidence — PromQL chính xác + panel (khả dụng ngay)

Tất cả PromQL dùng biến `$instance` (node-exporter) / không cần biến (cAdvisor, Traefik hiện scrape 1 target). Ngưỡng đỏ = thực dụng cho 1 host nhỏ.

### A. node-exporter (bổ sung / sửa)

**A0. Sửa CPU stat (multi-core safe)** — thay panel "CPU sử dụng (%)":
```promql
100 * (1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle",instance="$instance"}[5m])))
```
Ngưỡng: vàng 70, đỏ 90 (giữ nguyên).

**A1. Load per core** (saturation thật, độc lập số nhân):
```promql
node_load1{instance="$instance"} / count(count by(cpu)(node_cpu_seconds_total{instance="$instance"}))
```
Đỏ > 1.0 (kéo dài), vàng > 0.7.

**A2. Swap đang dùng %** (saturation RAM):
```promql
100 * (1 - node_memory_SwapFree_bytes{instance="$instance"} / clamp_min(node_memory_SwapTotal_bytes{instance="$instance"}, 1))
```
Bất kỳ swap-in/out kéo dài = cảnh báo. Đỏ > 50%. (Swap activity: `rate(node_vmstat_pswpin[5m])`.)

**A3. Disk-fill prediction** (panel quan trọng nhất phòng đầy đĩa) — stat/table:
```promql
predict_linear(node_filesystem_avail_bytes{instance="$instance",mountpoint="/",fstype!~"tmpfs|overlay"}[6h], 24*3600) < 0
```
= "đĩa sẽ đầy trong 24h" (trả về <0 nếu sẽ cạn). Biến thể "giờ còn lại":
```promql
node_filesystem_avail_bytes{mountpoint="/"} / clamp_min(-deriv(node_filesystem_avail_bytes{mountpoint="/"}[6h]), 1)
```
Ngưỡng cho alert (chuyển team-1): còn < 4h = đỏ, < 24h = vàng.

**A4. Inode used %** (đầy inode = "no space" dù còn dung lượng):
```promql
100 * (1 - node_filesystem_files_free{instance="$instance",mountpoint="/"} / node_filesystem_files{instance="$instance",mountpoint="/"})
```
Lưu ý: node_exporter đặt tên `*_files` (không phải `*_inodes`). Đỏ > 90.

**A5. Disk %util** (USE-utilization của đĩa) — timeseries by device:
```promql
rate(node_disk_io_time_seconds_total{instance="$instance"}[5m]) * 100
```
≈ % thời gian thiết bị bận. Đỏ > 90 kéo dài.

**A6. Disk IO latency (await)** — đọc & ghi, giây/thao tác:
```promql
rate(node_disk_read_time_seconds_total{instance="$instance"}[5m]) / clamp_min(rate(node_disk_reads_completed_total{instance="$instance"}[5m]), 1)
rate(node_disk_write_time_seconds_total{instance="$instance"}[5m]) / clamp_min(rate(node_disk_writes_completed_total{instance="$instance"}[5m]), 1)
```
Đỏ > 100ms (HDD/SSD chậm), > 20ms cho SSD tốt.

**A7. Network errors & drops** (USE-errors) — timeseries:
```promql
rate(node_network_receive_errs_total{instance="$instance",device!~"lo|veth.*|docker.*|br-.*"}[5m])
rate(node_network_receive_drop_total{instance="$instance",device!~"lo|veth.*|docker.*|br-.*"}[5m])
rate(node_network_transmit_errs_total{instance="$instance",device!~"lo|veth.*|docker.*|br-.*"}[5m])
```
Bất kỳ giá trị > 0 kéo dài = bất thường (đỏ).

**A8. File descriptors %**:
```promql
100 * node_filefd_allocated{instance="$instance"} / node_filefd_maximum{instance="$instance"}
```
Đỏ > 90.

**A9. Uptime** (stat, unit seconds → "duration"):
```promql
node_time_seconds{instance="$instance"} - node_boot_time_seconds{instance="$instance"}
```
Sụt đột ngột = vừa reboot (dùng cho annotation/alert team-1).

**A10. Time drift / clock offset**:
```promql
node_timex_offset_seconds{instance="$instance"}
```
Đỏ > 0.05s (50ms) lệch. **Lưu ý:** timex collector cần `--cap-add=SYS_TIME` cho container node-exporter (hiện service chưa chắc có → ghi vào Unresolved).

**A11. Conntrack (nếu là gateway, optional):**
```promql
100 * node_nf_conntrack_entries / node_nf_conntrack_entries_limit
```

### B. cAdvisor (bổ sung / sửa) — luôn lọc `{name!=""}`

**B1. CPU throttling** (saturation #1 cho container có CPU limit) — timeseries by name:
```promql
sum by(name)(rate(container_cpu_cfs_throttled_periods_total{name!=""}[5m]))
  / clamp_min(sum by(name)(rate(container_cpu_cfs_periods_total{name!=""}[5m])), 1)
```
= tỉ lệ chu kỳ bị bóp ga. Đỏ > 25%. (Hoặc `container_cpu_cfs_throttled_seconds_total` cho "giây bị bóp".)

**B2. RAM vs limit %** (dùng working_set, KHÔNG usage_bytes) — bar gauge top:
```promql
100 * container_memory_working_set_bytes{name!=""}
  / clamp_min(container_spec_memory_limit_bytes{name!=""}, 1)
  and container_spec_memory_limit_bytes{name!=""} > 0
```
`> 0` loại container không đặt limit (limit=0 khi unlimited). Đỏ > 90 (sắp OOM).

**B3. Sửa panel "RAM theo container"** → working_set (loại page cache):
```promql
sum by(name)(container_memory_working_set_bytes{name!=""})
```

**B4. OOM events** (USE-errors) — stat/timeseries:
```promql
sum by(name)(increase(container_oom_events_total{name!=""}[1h]))
```
> 0 = đỏ. cAdvisor ≥ v0.39.1. **Có thể vắng trên Docker Desktop/macOS** (đọc `/dev/kmsg`) — ghi Unresolved.

**B5. Top-N CPU** (per-container top, bar gauge, "Show: calculate / last"):
```promql
topk(10, sum by(name)(rate(container_cpu_usage_seconds_total{name!=""}[5m])))
```

**B6. Restart count** — **KHÔNG khả dụng từ cAdvisor trong Docker Compose** (`container_start_time_seconds` hằng số). Giải pháp: thêm `docker_state_exporter` (xem Unresolved). Tạm thời panel thay thế = "uptime container" (phát hiện gián tiếp khi tụt về 0):
```promql
time() - container_start_time_seconds{name!=""}
```

### C. Traefik (bổ sung / sửa)

**C1. Sửa panel 5xx%** (bỏ clamp_min méo số):
```promql
100 * sum(rate(traefik_service_requests_total{code=~"5.."}[5m]))
  / sum(rate(traefik_service_requests_total[5m]))
```
Nếu lo NaN khi 0 traffic, bọc `(... ) > 0` ở alert, KHÔNG ép mẫu số. Đỏ > 5%, vàng > 1%.

**C2. 4xx% tách riêng** (phân biệt lỗi client vs server):
```promql
100 * sum(rate(traefik_service_requests_total{code=~"4.."}[5m]))
  / sum(rate(traefik_service_requests_total[5m]))
```

**C3. Req/s theo ROUTER** (label đã bật `addRoutersLabels: true`) — timeseries:
```promql
sum by(router)(rate(traefik_router_requests_total[5m]))
```

**C4. Req/s theo entrypoint** (web vs websecure):
```promql
sum by(entrypoint)(rate(traefik_entrypoint_requests_total[5m]))
```

**C5. Requests in-flight** (saturation):
```promql
sum by(service)(traefik_service_requests_in_flight)
```
(Hoặc `traefik_entrypoint_requests_in_flight` nếu phiên bản expose ở entrypoint.)

**C6. p99 stat ở hàng KPI** (bổ sung cạnh p95 có sẵn):
```promql
histogram_quantile(0.99, sum(rate(traefik_service_request_duration_seconds_bucket[5m])) by (le))
```
Ngưỡng latency p99: vàng > 0.5s, đỏ > 1s (tùy app).

**C7. TLS cert sắp hết hạn** (nếu Traefik expose; optional, hữu ích cho ACME):
```promql
(traefik_tls_certs_not_after - time()) / 86400
```
Đỏ < 14 ngày.

### D. Dashboard "00 — Overview / NOC" (đề xuất mới)

File mới `grafana/dashboards/00-overview-noc.json` (prefix `00-` để nổi lên đầu danh sách). **4 Golden Signals + sống-chết** trên 1 màn:

Hàng 1 — **Up/Down (sống-chết)**, stat đỏ/xanh:
```promql
up{job="node-exporter"}     # host
up{job="cadvisor"}
up{job="traefik"}
up{job="prometheus"}
count(count by(name)(container_last_seen{name!=""}))   # số container sống
```

Hàng 2 — **Saturation host** (USE), stat + threshold:
```promql
100 * (1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])))      # CPU%
100 * (1 - node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)            # RAM%
100 * (1 - node_filesystem_avail_bytes{mountpoint="/"}/node_filesystem_size_bytes{mountpoint="/"})  # Disk%
node_load1 / count(count by(cpu)(node_cpu_seconds_total))                        # load/core
```

Hàng 3 — **RED Traefik** (Traffic/Errors/Latency):
```promql
sum(rate(traefik_service_requests_total[5m]))                                    # req/s
100 * sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) / sum(rate(traefik_service_requests_total[5m]))  # 5xx%
histogram_quantile(0.95, sum(rate(traefik_service_request_duration_seconds_bucket[5m])) by (le))  # p95
```

Hàng 4 — **Cảnh báo sớm** (table/stat):
```promql
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 24*3600) < 0     # đĩa đầy <24h
sum by(name)(increase(container_oom_events_total{name!=""}[1h])) > 0              # OOM
sum by(name)(rate(container_cpu_cfs_throttled_periods_total{name!=""}[5m])) / clamp_min(sum by(name)(rate(container_cpu_cfs_periods_total{name!=""}[5m])),1) > 0.25  # throttle
node_timex_offset_seconds                                                         # time drift
```

## Recommendations (ưu tiên giảm dần)

1. **[P0 — sửa lỗi] Vá 3 dashboard hiện có:**
   - `cadvisor.json`: đổi `container_memory_usage_bytes` → `container_memory_working_set_bytes` (panel RAM + tổng RAM).
   - `traefik.json`: bỏ `clamp_min(...,1)` ở panel 5xx%; thêm p99 stat + 4xx%.
   - `node-exporter.json`: thêm `by(instance)` cho CPU stat.
2. **[P0 — thêm dashboard mới] Tạo `grafana/dashboards/00-overview-noc.json`** (mục D). Đây là màn hình trực 1-nhìn-biết-sống-chết. Cao giá trị nhất, ít công nhất.
3. **[P1 — bổ sung panel USE host]** thêm vào `node-exporter.json`: swap%, inode%, disk-predict, IO %util, IO latency, net errors/drops, FD%, uptime, time-drift, load/core (A1–A10).
4. **[P1 — bổ sung panel USE container]** thêm vào `cadvisor.json`: CPU throttle (B1), RAM-vs-limit bar (B2), OOM (B4), top-N CPU (B5).
5. **[P1 — bổ sung Traefik]** router req/s (C3), entrypoint (C4), in-flight (C5).
6. **[P2 — tùy chọn] Import dashboard cộng đồng** làm bản tra cứu sâu: `1860-node-exporter-full.json`, `17346-traefik-official.json`, `19908-cadvisor.json` vào `grafana/dashboards/` — **nhớ đổi datasource cứng → `Prometheus`/`${datasource}`** trước khi lưu, đặt tên có prefix ID, đổi `title` để không trùng dashboard tự viết.
7. **Bàn giao cho team-1 (alert):** ngưỡng đỏ ở mục Evidence (disk-predict < 4h, OOM > 0, throttle > 25%, 5xx > 5%, FD > 90%, time-drift > 50ms) dùng trực tiếp làm alert rules — PromQL giống hệt, chỉ thêm `for:` và so sánh ngưỡng.

**Tuân cơ chế repo:** mọi thay đổi chỉ ở `grafana/dashboards/*.json`; provisioning tự nạp (30s), **không cần `setup.sh`, không cần restart Grafana**. Không thêm service mới nào cho phần này (trừ khi quyết định lấy restart-count thì mới thêm `docker_state_exporter` qua `services/<ten>.md` + cờ `.env`).

## Unresolved questions

1. **Restart count:** chấp nhận giới hạn cAdvisor (không có) hay thêm `services/docker-state-exporter.md` (karugaru/docker_state_exporter, cổng 8080, scrape job mới + `container_status`/`restarts_total`)? → trùng phạm vi TASK #3 (exporter bổ sung), nên để team-3 quyết.
2. **OOM trên host hiện tại:** host chạy production là Linux thật hay Docker Desktop/macOS? Nếu Docker Desktop, `container_oom_events_total` + nhiều metric đĩa/IO có thể vắng (đã ghi trong CLAUDE.md) → panel sẽ "No data", cần ghi chú trên dashboard.
3. **timex collector:** service node-exporter hiện có `--cap-add=SYS_TIME` chưa? Nếu chưa, panel time-drift (A10) trống — cần sửa `services/node-exporter.md`. (Chưa đọc file service để tránh ngoài phạm vi; đề nghị team-lead/team-3 xác nhận.)
4. **Đa host tương lai:** stack hiện scrape 1 target mỗi job (static). Nếu mở rộng nhiều host, các panel Traefik/cAdvisor cần thêm biến `$instance`/`$job` và `by(instance)` — hiện chưa cần (YAGNI).
5. **Histogram resolution:** Traefik dùng classic histogram bucket mặc định; nếu cần p99 chính xác hơn ở latency cao, cân nhắc cấu hình `buckets` trong `metrics.prometheus` (traefik.yml) — chưa cần cho tải nhỏ.
