# Service: node-exporter

Thu thập metric của MÁY CHỦ (host): CPU, RAM, disk, network, load.
Không có giao diện riêng — dữ liệu hiển thị trong Grafana (dashboard "Node /
Host"). Chỉ nằm trong network `monitoring`, không expose ra ngoài.

> Thuộc nhóm giám sát. Prometheus tự scrape tại `node-exporter:9100`.

```yaml
  node-exporter:
    image: "prom/node-exporter:${NODE_EXPORTER_VERSION:-v1.11.1}"
    container_name: node-exporter
    restart: unless-stopped
    command:
      - "--path.rootfs=/host"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
    pid: host
    volumes:
      # Lưu ý: KHÔNG dùng "ro,rslave" vì Docker Desktop (macOS/Windows) không hỗ
      # trợ mount propagation -> lỗi "not a shared or slave mount". Chỉ "ro" chạy
      # được trên cả Docker Desktop lẫn Linux.
      - /:/host:ro
    networks:
      - monitoring
```
