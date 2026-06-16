# Service: grafana

Giao diện biểu đồ giám sát tại `grafana.${DOMAIN}`. Đã nạp sẵn datasource
Prometheus và dashboard "Traefik" (request/s, lỗi 5xx, latency p50/p95/p99).

> Thuộc nhóm giám sát. Cần bật `prometheus` đi kèm mới có dữ liệu.

**Phụ thuộc:** `grafana/provisioning/`, `grafana/dashboards/`. Đặt mật khẩu qua
`GRAFANA_USER` / `GRAFANA_PASSWORD` trong `.env`.

```yaml
  grafana:
    image: "grafana/grafana:${GRAFANA_VERSION:-13.0.2}"
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-changeme}
      - GF_USERS_ALLOW_SIGN_UP=false
      - TZ=${TZ:-Asia/Ho_Chi_Minh}
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    networks:
      - proxy
      - monitoring
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.${DOMAIN}`)"
      - "traefik.http.routers.grafana.entrypoints=websecure"
      - "traefik.http.routers.grafana.tls.certresolver=le"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"
```
