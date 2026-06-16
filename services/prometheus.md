# Service: prometheus

Thu thập (scrape) metrics từ Traefik. Không expose ra ngoài — chỉ Grafana
truy cập nội bộ qua network `monitoring`.

> Thuộc nhóm giám sát. Bật cùng `grafana` để xem biểu đồ.

**Phụ thuộc:** `prometheus/prometheus.yml`.

```yaml
  prometheus:
    image: "prom/prometheus:${PROMETHEUS_VERSION:-v3.12.0}"
    container_name: prometheus
    restart: unless-stopped
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.retention.time=30d"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    networks:
      - proxy        # để Traefik định tuyến tới
      - monitoring
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(`prometheus.${DOMAIN}`)"
      - "traefik.http.routers.prometheus.entrypoints=websecure"
      - "traefik.http.routers.prometheus.tls.certresolver=le"
      - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
      # Prometheus không có đăng nhập -> bắt buộc bảo vệ bằng basic-auth
      - "traefik.http.routers.prometheus.middlewares=dashboard-auth@file"
```
