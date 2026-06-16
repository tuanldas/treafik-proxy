# Mở rộng Observability — Blackbox, Loki/Alloy, Exporter bổ sung, Pushgateway, Vận hành

> researcher-3 · 2026-06-16 · stack Traefik + Prometheus + Grafana (codegen từ `services/*.md`)

## Executive summary

5 hướng mở rộng, tất cả đóng gói được theo cơ chế repo (1 file `services/<ten>.md` + cờ `.env`), trừ 2 va chạm cần xử lý tay (nêu rõ bên dưới).

1. **Blackbox exporter v0.28.0** — giám sát uptime/SSL/status/latency từng domain Traefik route. Đóng gói `services/blackbox-exporter.md` (network `monitoring`). Scrape multi-target thêm vào `prometheus/prometheus.yml` (sửa tay, vì scrape config tĩnh). PromQL cert-expiry + site-down sẵn dùng.
2. **Log tập trung: Loki 3.7 + Grafana Alloy** — **KHÔNG dùng Promtail (EOL 2026-03-02)**. Alloy thu log Docker qua socket. Thêm datasource Loki vào Grafana provisioning. **Va chạm:** Loki cần volume mới mà `setup.sh` header chỉ khai báo cứng 2 volume → dùng bind-mount.
3. **Exporter app (postgres/mysqld/redis)** — mỗi cái 1 file service, network `monitoring`, secret/DSN từ `.env`. mysqld cần `.my.cnf` (không nhận DSN qua env tốt như 2 cái kia).
4. **Pushgateway v1.9.0** — CHỈ cho batch/cron/backup job thoát trước khi scrape. Nhiều anti-pattern; mặc định **chưa cần** cho stack hiện tại.
5. **Vận hành** — bảo mật `/metrics` (đã đúng: exporter chỉ ở `monitoring`, không expose); cardinality là rủi ro phình TSDB lớn nhất; công thức ước lượng đĩa; chiến lược retention.

**Khuyến nghị triển khai theo thứ tự ưu tiên:** Blackbox (1) → Loki+Alloy (2) → exporter theo nhu cầu app (3). Pushgateway (4) chỉ khi có cron/backup cần báo cáo.

---

## Key findings

### F1. Cơ chế repo tương thích tốt với exporter, nhưng có 2 ràng buộc

- **`apply_ssl` an toàn với exporter:** `setup.sh` chỉ `sed` các dòng `entrypoints=websecure`/`tls.certresolver=`. Exporter chỉ ở network `monitoring` (không có label Traefik) → không bị đụng. Copy mẫu `node-exporter.md` là an toàn nhất.
- **RÀNG BUỘC A — Volume:** Header `setup.sh` (dòng 193-197) hardcode **chỉ** `prometheus-data` + `grafana-data`. Service mới cần named volume (Loki, Pushgateway `--persistence`) sẽ tham chiếu volume **không được khai báo** → `docker compose` lỗi. **Giải pháp KISS:** dùng **bind-mount** (`./loki/data:/loki`) thay vì named volume → không phải sửa generator. (Phương án khác: sửa header `setup.sh`, nhưng tăng phạm vi.)
- **RÀNG BUỘC B — Scrape config tĩnh:** `prometheus/prometheus.yml` không sinh tự động. Mọi target mới (blackbox, exporter) phải **thêm tay** vào file này. Đây là thiết kế hiện tại, không phải lỗi.

### F2. Blackbox: multi-target pattern, không phải scrape trực tiếp

Blackbox không tự biết URL nào cần probe. Prometheus gửi URL qua `?target=...` tới `/probe`, dùng `relabel_configs` hoán đổi `__address__`. Danh sách URL nằm trong `static_configs.targets` của Prometheus (không phải trong service blackbox). Cert expiry đo qua `probe_ssl_earliest_cert_expiry` (unix timestamp).

### F3. Promtail đã chết — bắt buộc Alloy

Promtail **EOL 2026-03-02** (hôm nay đã quá mốc), LTS từ 2025-02-13, không còn feature/bugfix mới. Grafana đẩy sang **Alloy** (dựa trên OpenTelemetry Collector, config ngôn ngữ River). Mọi tài liệu mới 2026 đều dùng Alloy. Không khuyến nghị Promtail cho deployment mới.

### F4. mysqld_exporter khác postgres/redis về secret

postgres_exporter và redis_exporter nhận connection qua **env var** (hợp `.env` của repo). mysqld_exporter **ưu tiên file `.my.cnf`** `[client]` — truyền DSN qua env kém tiện hơn và bị lộ trong `docker inspect`. → mysqld nên mount file cnf (vẫn sinh nội dung từ `.env` nếu muốn).

### F5. Cardinality là rủi ro vận hành số 1

Đĩa TSDB phình theo **số time-series active**, không theo số request. Label động (user_id, path đầy đủ, UUID, request_id) gây nổ cardinality. Blackbox/exporter thêm vào lành tính (cardinality cố định theo số target). Cảnh báo chính: đừng thêm label động khi tự viết metric / khi dùng Pushgateway.

---

## Evidence

### 1) Blackbox exporter

#### 1a. `services/blackbox-exporter.md` (đóng gói theo cơ chế repo)

Network `monitoring` (không expose). Cần file module config mount vào (giống prometheus mount `prometheus.yml`).

````markdown
# Service: blackbox-exporter

Probe uptime/SSL/HTTP từ góc nhìn người dùng cho từng domain Traefik route.
Không expose ra ngoài — chỉ network `monitoring`. Prometheus gọi qua `/probe`.

> Thuộc nhóm giám sát. **Phụ thuộc:** `blackbox/blackbox.yml` (module config).
> Sau khi bật: thêm job `blackbox` vào `prometheus/prometheus.yml` (xem README mục dưới).

```yaml
  blackbox-exporter:
    image: "prom/blackbox-exporter:${BLACKBOX_EXPORTER_VERSION:-v0.28.0}"
    container_name: blackbox-exporter
    restart: unless-stopped
    command:
      - "--config.file=/etc/blackbox_exporter/config.yml"
    volumes:
      - ./blackbox/blackbox.yml:/etc/blackbox_exporter/config.yml:ro
    networks:
      - monitoring
```
````

Thêm cờ `.env`:
```dotenv
BLACKBOX_EXPORTER=true
BLACKBOX_EXPORTER_VERSION=v0.28.0
```

> ICMP (ping) cần `cap_add: [NET_RAW]`. Chỉ thêm khi thật sự probe ICMP — mặc định HTTP/TCP không cần, giữ KISS.

#### 1b. `blackbox/blackbox.yml` (module config — file mới)

```yaml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: []        # rỗng = chấp nhận mọi 2xx
      method: GET
      follow_redirects: true
      fail_if_not_ssl: false        # đặt true nếu BẮT BUỘC site phải có TLS
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
  http_2xx_strict_tls:
    prober: http
    timeout: 5s
    http:
      method: GET
      fail_if_not_ssl: true         # probe FAIL nếu không phải HTTPS hợp lệ
      preferred_ip_protocol: "ip4"
  tcp_connect:
    prober: tcp
    timeout: 5s
  tls_connect:                       # kiểm TLS handshake cho port không-HTTP
    prober: tcp
    timeout: 5s
    tcp:
      tls: true
  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: "ip4"
```
Nguồn: prometheus/blackbox_exporter `example.yml` (master).

#### 1c. Thêm vào `prometheus/prometheus.yml` (sửa tay — scrape config tĩnh)

```yaml
  # Blackbox: probe uptime/SSL từng domain. targets = danh sách URL cần probe.
  - job_name: "blackbox-http"
    metrics_path: /probe
    params:
      module: [http_2xx]
    scrape_interval: 30s          # probe thưa hơn metric thường (giảm tải + cardinality)
    static_configs:
      - targets:
          - https://whoami.${DOMAIN}      # thay bằng domain thật, hoặc liệt kê tay
          - https://grafana.${DOMAIN}
          - https://prometheus.${DOMAIN}
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115   # tên service:port nội bộ

  # (tuỳ chọn) metric vận hành của chính blackbox
  - job_name: "blackbox-exporter"
    static_configs:
      - targets: ["blackbox-exporter:9115"]
```

> Lưu ý: `prometheus.yml` mount `:ro` và Prometheus **không** tự đọc `${DOMAIN}` từ `.env` (đây là file config, không qua compose interpolation). → phải **ghi URL tường minh** (vd `https://whoami.example.com`), không dùng `${DOMAIN}`. Đây là khác biệt với `services/*.md`.

#### 1d. PromQL sẵn dùng

```promql
# Site down (probe thất bại)
probe_success == 0

# SSL cert còn < 14 ngày (đổi 14 tuỳ ý)
(probe_ssl_earliest_cert_expiry - time()) / 86400 < 14

# Số ngày còn lại của cert (hiển thị panel)
(probe_ssl_earliest_cert_expiry - time()) / 86400

# Cert đã hết hạn
probe_ssl_earliest_cert_expiry - time() <= 0

# HTTP status code trả về != 2xx
probe_http_status_code >= 400

# Thời gian phản hồi đầu-cuối (giây)
probe_duration_seconds

# Uptime % trong 24h
avg_over_time(probe_success[24h]) * 100
```
Metric khác hữu ích: `probe_http_duration_seconds{phase=...}` (tách resolve/connect/tls/processing/transfer), `probe_http_ssl` (1 nếu dùng TLS).

---

### 2) Log tập trung: Loki 3.7 + Grafana Alloy

#### 2a. So sánh Promtail vs Alloy

| | Promtail | **Grafana Alloy** (khuyến nghị) |
|---|---|---|
| Trạng thái | **EOL 2026-03-02**, LTS từ 2025-02-13 | Đang phát triển tích cực, thay thế chính thức |
| Nền tảng | Riêng của Loki | OpenTelemetry Collector |
| Config | YAML | River (HCL-like) |
| Thu log Docker | có | có (`loki.source.docker`) |
| Tài nguyên | nhẹ hơn chút | nặng hơn nhẹ (chấp nhận được cho 1 host) |
| Khuyến nghị | KHÔNG cho deployment mới | **CÓ** |

Quyết định: **Alloy**. Promtail đã EOL trước hôm nay (2026-06-16).

#### 2b. `services/loki.md` (bind-mount — né RÀNG BUỘC A)

````markdown
# Service: loki

Log aggregation (single-binary, target=all). Chỉ network `monitoring`.
Lưu trữ qua bind-mount ./loki/data (KHÔNG named volume — setup.sh header
chỉ khai báo prometheus-data/grafana-data).

> **Phụ thuộc:** `loki/loki-config.yml`. Datasource thêm ở grafana/provisioning.

```yaml
  loki:
    image: "grafana/loki:${LOKI_VERSION:-3.7.0}"
    container_name: loki
    restart: unless-stopped
    command: "-config.file=/etc/loki/loki-config.yml"
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - ./loki/data:/loki
    networks:
      - monitoring
```
````

#### 2c. `services/alloy.md` (thu log Docker qua socket)

````markdown
# Service: alloy

Grafana Alloy — thu log mọi container Docker, đẩy sang Loki. THAY Promtail (EOL).
Cần đọc Docker socket (ro). Chỉ network `monitoring`.

> **Phụ thuộc:** `alloy/config.alloy`. Cần `loki` bật trước.

```yaml
  alloy:
    image: "grafana/alloy:${ALLOY_VERSION:-v1.10.0}"
    container_name: alloy
    restart: unless-stopped
    command:
      - "run"
      - "--server.http.listen-addr=0.0.0.0:12345"
      - "--storage.path=/var/lib/alloy/data"
      - "/etc/alloy/config.alloy"
    volumes:
      - ./alloy/config.alloy:/etc/alloy/config.alloy:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - monitoring
```
````

Cờ `.env`:
```dotenv
LOKI=true
LOKI_VERSION=3.7.0
ALLOY=true
ALLOY_VERSION=v1.10.0
```

#### 2d. `alloy/config.alloy` (River — file mới)

```alloy
// Phát hiện container Docker qua socket
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

// Làm sạch nhãn: __meta_docker_container_name có dấu "/" đầu -> bỏ
discovery.relabel "docker_logs" {
  targets = []
  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }
}

// Thu log từ container đã phát hiện
loki.source.docker "default" {
  host          = "unix:///var/run/docker.sock"
  targets       = discovery.docker.containers.targets
  relabel_rules = discovery.relabel.docker_logs.rules
  labels        = {"job" = "docker"}
  forward_to    = [loki.write.local.receiver]
}

// Đẩy sang Loki
loki.write "local" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```
Nguồn: grafana.com/docs/alloy `loki.source.docker` + `monitor-docker-containers`.

> Tài liệu chính thức Grafana dùng `target_label = "service_name"`; ở đây đổi thành `container` cho khớp với nhãn `name` của cAdvisor (xem metric/log cạnh nhau dễ hơn).

#### 2e. Datasource Loki cho Grafana (file mới, đúng cơ chế provisioning)

`grafana/provisioning/datasources/loki.yml`:
```yaml
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: false
    editable: true
```
> Grafana đã auto-load mọi file trong thư mục này (xem `datasource.yml` Prometheus hiện có). Chỉ cần thêm file, restart grafana. **Lưu ý:** grafana hiện chỉ ở network `proxy`+`monitoring` — Loki ở `monitoring` nên reachable. OK.

#### 2f. LogQL cơ bản

```logql
# Tất cả log của 1 container
{container="traefik"}

# Lọc theo chuỗi
{container="traefik"} |= "error"

# Loại trừ + parse logfmt
{job="docker"} != "healthcheck" | logfmt

# Đếm dòng lỗi/phút theo container (cho bảng/biểu đồ)
sum by (container) (count_over_time({job="docker"} |= "error" [1m]))

# Tỉ lệ log 5xx của Traefik access log (nếu log JSON)
{container="traefik"} | json | DownstreamStatus >= 500

# Bytes log/giây mỗi container (theo dõi container "nói nhiều")
sum by (container) (bytes_rate({job="docker"}[1m]))
```

#### 2g. Tài nguyên Loki

- Single-binary `-target=all`: đủ cho ~**20GB log/ngày** / 1 host. Vượt mức này cần tách microservice.
- Loki index nhãn (label), **không** full-text index → nhẹ RAM hơn ELK rất nhiều. Giữ **số nhãn thấp** (chỉ `container`/`job`); KHÔNG đưa nội dung động (request id, IP) thành nhãn → cardinality bomb giống Prometheus.
- Bind-mount `./loki/data` cần dọn theo retention (cấu hình trong `loki-config.yml`, mục `limits_config.retention_period` + compactor). Mặc định filesystem store giữ vô hạn → set retention vd `744h` (31 ngày) cho khớp Prometheus.

---

### 3) Exporter bổ sung theo loại app

Mẫu chung: copy `node-exporter.md`, network `monitoring`, secret từ `.env`. Mỗi exporter thêm 1 job vào `prometheus/prometheus.yml` (sửa tay).

#### 3a. postgres_exporter (v0.19.1, port 9187)

````markdown
# Service: postgres-exporter

Metric PostgreSQL. Secret lấy từ .env (DATA_SOURCE_NAME). Chỉ network monitoring.

```yaml
  postgres-exporter:
    image: "quay.io/prometheuscommunity/postgres-exporter:${POSTGRES_EXPORTER_VERSION:-v0.19.1}"
    container_name: postgres-exporter
    restart: unless-stopped
    environment:
      - DATA_SOURCE_NAME=${POSTGRES_DSN}
    networks:
      - monitoring
```
````
`.env` (KHÔNG hardcode — DSN ở .env, đã gitignore):
```dotenv
POSTGRES_EXPORTER=true
POSTGRES_DSN=postgresql://exporter:PASS@db-host:5432/postgres?sslmode=disable
```
Metric quan trọng: `pg_up`, `pg_stat_database_numbackends` (connections), `pg_stat_database_xact_commit/rollback`, `pg_stat_replication` + `pg_replication_lag` (lag), `pg_database_size_bytes`, `pg_stat_database_blks_hit / (blks_hit+blks_read)` (cache hit ratio), `pg_stat_activity_count` (theo state).

#### 3b. redis_exporter (v1.86.0, port 9121)

````markdown
# Service: redis-exporter

Metric Redis/Valkey. Secret từ .env. Chỉ network monitoring.

```yaml
  redis-exporter:
    image: "oliver006/redis_exporter:${REDIS_EXPORTER_VERSION:-v1.86.0}"
    container_name: redis-exporter
    restart: unless-stopped
    environment:
      - REDIS_ADDR=${REDIS_ADDR:-redis://redis:6379}
      - REDIS_PASSWORD=${REDIS_PASSWORD:-}
    networks:
      - monitoring
```
````
```dotenv
REDIS_EXPORTER=true
REDIS_ADDR=redis://redis:6379
REDIS_PASSWORD=
```
Metric quan trọng: `redis_up`, `redis_connected_clients`, `redis_memory_used_bytes` / `redis_memory_max_bytes`, `redis_keyspace_hits_total` & `redis_keyspace_misses_total` (hit rate = hits/(hits+misses)), `redis_db_keys`, `redis_evicted_keys_total`, `redis_connected_slaves` + `redis_master_repl_offset` (replication).

#### 3c. mysqld_exporter (v0.19.0, port 9104) — dùng .my.cnf

mysqld_exporter ưu tiên file cnf hơn env DSN (an toàn hơn `docker inspect`).

````markdown
# Service: mysqld-exporter

Metric MySQL/MariaDB. Credential qua file .my.cnf (mount), KHÔNG qua env.

```yaml
  mysqld-exporter:
    image: "prom/mysqld-exporter:${MYSQLD_EXPORTER_VERSION:-v0.19.0}"
    container_name: mysqld-exporter
    restart: unless-stopped
    command:
      - "--config.my-cnf=/etc/mysql/.my.cnf"
      - "--collect.slave_status"
      - "--collect.info_schema.innodb_metrics"
    volumes:
      - ./mysqld/.my.cnf:/etc/mysql/.my.cnf:ro
    networks:
      - monitoring
```
````
`mysqld/.my.cnf` (file mới — KHÔNG commit, thêm vào `.gitignore`):
```ini
[client]
user=exporter
password=PASS
host=db-host
port=3306
```
SQL tạo user (chạy 1 lần trên DB):
```sql
CREATE USER 'exporter'@'%' IDENTIFIED BY 'PASS' WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
```
```dotenv
MYSQLD_EXPORTER=true
```
Metric quan trọng: `mysql_up`, `mysql_global_status_threads_connected` (connections), `mysql_global_status_slow_queries` (slow query counter), `mysql_global_status_queries`, `mysql_slave_status_seconds_behind_master` (replication lag), `mysql_global_status_innodb_buffer_pool_reads / read_requests` (buffer pool hit), `mysql_global_status_aborted_connects`.

> **`.gitignore`:** thêm `mysqld/.my.cnf` (chứa mật khẩu). Repo đã có nguyên tắc không hardcode secret — file cnf là ngoại lệ cần gitignore tường minh.

#### 3d. Scrape jobs cho cả 3 (thêm vào `prometheus/prometheus.yml`)

```yaml
  - job_name: "postgres-exporter"
    static_configs:
      - targets: ["postgres-exporter:9187"]
  - job_name: "redis-exporter"
    static_configs:
      - targets: ["redis-exporter:9121"]
  - job_name: "mysqld-exporter"
    static_configs:
      - targets: ["mysqld-exporter:9104"]
```
> nginx exporter: chỉ cần nếu chạy nginx **riêng** sau Traefik. Traefik **đã** xuất metric RED riêng (`traefik_*`) → cho hầu hết trường hợp KHÔNG cần nginx-exporter (YAGNI). Bỏ qua trừ khi có nginx upstream cụ thể.

---

### 4) Pushgateway (v1.9.0) — dùng có chọn lọc

#### Khi NÊN dùng
- Batch/cron/backup job **thoát trước khi Prometheus scrape** (job ngắn). Vd: job backup DB hằng đêm push `backup_last_success_timestamp_seconds` + `backup_duration_seconds`.
- Job **service-level** (không gắn máy cụ thể).

#### Khi KHÔNG nên (anti-pattern — nguồn prometheus.io/docs/practices/pushing)
- Service/daemon chạy dài → dùng scrape pull bình thường, KHÔNG push.
- Né service discovery / xuyên firewall cho service dài → sai mục đích.
- Làm event store (track release, deploy) → dùng annotation/log, không phải Pushgateway.
- Gắn label động (timestamp, UUID, request_id, instance) → **cardinality bomb vĩnh viễn** (metric Pushgateway không tự hết hạn).

#### Lưu ý vận hành
- Metric push **không tự expire** → job phải tự `DELETE` khi xong/lỗi, nếu không số liệu cũ kẹt lại gây hiểu nhầm.
- Pushgateway là **single point of failure** + không phản ánh "job có chạy không" (chỉ giữ giá trị cuối). Dùng `push_time_seconds` để phát hiện job ngừng push.

#### Đóng gói (nếu cần)
````markdown
# Service: pushgateway
```yaml
  pushgateway:
    image: "prom/pushgateway:${PUSHGATEWAY_VERSION:-v1.11.0}"
    container_name: pushgateway
    restart: unless-stopped
    networks:
      - monitoring
```
````
Job push tới `pushgateway:9091`. Thêm scrape:
```yaml
  - job_name: "pushgateway"
    honor_labels: true          # giữ label job/instance do client đẩy lên
    static_configs:
      - targets: ["pushgateway:9091"]
```
PromQL phát hiện backup trễ:
```promql
time() - backup_last_success_timestamp_seconds > 86400   # backup quá 24h chưa thành công
time() - push_time_seconds{job="nightly-backup"} > 3600   # job ngừng push > 1h
```
**Khuyến nghị:** stack hiện tại (proxy + monitoring) **chưa có** batch job → **chưa cần Pushgateway**. Thêm sau khi có cron/backup thực sự.

---

### 5) Lưu ý vận hành

#### 5a. Bảo mật endpoint `/metrics` — repo ĐÃ làm đúng
- Mọi exporter (node, cadvisor, blackbox, postgres/redis/mysqld) chỉ ở network **`monitoring`**, KHÔNG có label `traefik.enable=true` → **không expose internet**. Giữ nguyên nguyên tắc này.
- Traefik metrics ở entrypoint nội bộ `:8082` (không nằm trong `web`/`websecure`) → an toàn.
- **Đừng** thêm router Traefik cho exporter. Nếu cần xem `/metrics` từ ngoài để debug → tạm `docker compose exec` hoặc port-forward, không mở router.
- Prometheus/Grafana có route ra ngoài nhưng đã chặn: Prometheus bằng `dashboard-auth@file` (basic-auth), Grafana có login riêng. Loki/Alloy KHÔNG nên expose (chỉ `monitoring`).

#### 5b. Cardinality — rủi ro phình TSDB lớn nhất
- TSDB phình theo **số series active**, không theo lưu lượng. Mỗi tổ hợp nhãn duy nhất = 1 series.
- Nguồn nổ thường gặp: label `path`/`url` đầy đủ (Traefik có thể sinh nhiều router label), `user_id`, `status` chi tiết, IP, container id thay vì name.
- Exporter ở report này **lành tính** (cardinality cố định theo số DB/target).
- Blackbox: mỗi URL = 1 series/ metric → giữ danh sách target hợp lý, `scrape_interval` thưa (30s).
- Kiểm tra series cao nhất:
```promql
topk(10, count by (__name__)({__name__=~".+"}))      # metric nhiều series nhất
sum(scrape_samples_scraped) by (job)                  # job nào scrape nhiều mẫu nhất
prometheus_tsdb_head_series                           # tổng series đang giữ
```

#### 5c. Ước lượng dung lượng TSDB
Công thức (nguồn robustperception.io / groundcover):
```
disk ≈ retention_seconds × samples_per_second × bytes_per_sample × 1.2
```
- `bytes_per_sample` ~1.5–2 B (đo thực tế:
  `rate(prometheus_tsdb_compaction_chunk_size_bytes_sum[1h]) / rate(prometheus_tsdb_compaction_chunk_samples_sum[1h])`).
- Ví dụ: 100k series @ 15s @ 15 ngày @ 2B ≈ **17 GB**.
- Stack hiện tại (traefik+node+cadvisor, ít series) ở retention 30d ước tính **vài GB** — nhẹ. Thêm blackbox/exporter tăng không đáng kể. Loki dùng đĩa **riêng** (`./loki/data`), tính tách.

#### 5d. Retention
- Hiện tại: `--storage.tsdb.retention.time=30d` (hardcode trong `services/prometheus.md`). Hợp lý cho 1 host.
- Có thể đặt thêm `--storage.tsdb.retention.size=10GB` để chặn theo dung lượng (cái nào tới trước). Sửa trong `services/prometheus.md` `command`.
- Loki retention cấu hình **riêng** trong `loki-config.yml` (`limits_config.retention_period` + compactor `retention_enabled: true`). Mặc định giữ vô hạn → PHẢI set nếu không muốn đầy đĩa.

---

## Recommendations (xếp hạng)

| # | Hạng mục | Ưu tiên | Lý do / phù hợp kiến trúc |
|---|----------|---------|----------------------------|
| 1 | **Blackbox v0.28.0** | **Cao** | Giá trị cao nhất/đơn vị công sức: uptime + cảnh báo cert sắp hết hạn cho mọi domain Traefik. Đóng gói gọn, không state, không đụng RÀNG BUỘC volume. |
| 2 | **Loki 3.7 + Alloy** | **Cao** | Log cạnh metric là mảnh còn thiếu lớn. Promtail EOL → Alloy bắt buộc. Lưu ý bind-mount (né RÀNG BUỘC A) + set retention. |
| 3 | **postgres/redis/mysqld exporter** | **Trung bình (theo nhu cầu)** | Chỉ thêm cái nào stack thực sự chạy app đó. Mẫu rõ, secret từ `.env`. mysqld dùng `.my.cnf` (gitignore). |
| 4 | **Pushgateway** | **Thấp / hoãn** | Chưa có batch job. Nhiều anti-pattern. Thêm khi có cron/backup cần báo cáo thành-bại. |
| 5 | **Vận hành** | **Liên tục** | Giữ exporter trong `monitoring` (đã đúng). Canh cardinality. Set Loki retention. Cân nhắc `retention.size` cho Prometheus. |

**Nguyên tắc xuyên suốt (KISS/YAGNI):** bind-mount thay named volume cho service mới → khỏi sửa generator; chỉ thêm exporter app thực sự tồn tại; bỏ qua nginx-exporter (Traefik đã có metric RED); ICMP/NET_RAW chỉ khi cần.

---

## Unresolved questions

1. **Danh sách domain probe Blackbox:** lấy tự động từ Traefik (cần Traefik provider cho Prometheus / file_sd sinh từ `docker compose`) hay liệt kê tay trong `prometheus.yml`? Hiện đề xuất **liệt kê tay** (KISS). Tự động hoá cần thêm cơ chế (vd script đọc `Host()` từ services như `setup.sh` đang làm cho phần nhắc DNS) — hỏi team-lead có muốn mở rộng `setup.sh` sinh target blackbox không.
2. **Volume cho Loki:** xác nhận chọn **bind-mount** (`./loki/data`) hay muốn sửa header `setup.sh` để hỗ trợ named volume động? Bind-mount là KISS nhưng lệch khỏi pattern volume của 2 service monitoring hiện có.
3. **`prometheus.yml` không qua compose interpolation:** target blackbox phải ghi domain tường minh (không dùng `${DOMAIN}`). Cần thống nhất giá trị `DOMAIN` thực để điền — hay để placeholder `example.com` cho người dùng tự sửa?
4. **App DB có thật trong stack không?** Repo hiện chỉ có proxy+monitoring, chưa thấy service postgres/redis/mysql. Exporter app chỉ nên thêm khi có DB tương ứng (cùng compose hoặc host ngoài) — xác nhận để khỏi thêm thừa (YAGNI).
5. **Phiên bản Alloy:** đã chốt dòng v1.x mới nhất (đề xuất `v1.10.0`); nên `WebFetch` trang releases Alloy ngay trước khi triển khai để lấy tag patch chính xác (releases ra nhanh).
6. **Trùng lặp giữa các researcher:** PromQL site-down/cert-expiry ở đây có thể trùng phần alert rules của researcher-1 (Alertmanager). Cần team-lead hợp nhất để alert rule dùng đúng các biểu thức này, tránh viết 2 lần.
