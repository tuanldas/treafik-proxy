# Service: cadvisor

Thu thập metric của TỪNG CONTAINER: CPU, RAM, network theo container.
Không có giao diện cần expose — dữ liệu hiển thị trong Grafana (dashboard
"Containers / cAdvisor"). Prometheus scrape tại `cadvisor:8080`.

> Thuộc nhóm giám sát. Cần quyền đọc Docker socket + /sys để đo container.

```yaml
  cadvisor:
    image: "gcr.io/cadvisor/cadvisor:${CADVISOR_VERSION:-v0.55.1}"
    container_name: cadvisor
    restart: unless-stopped
    privileged: true
    devices:
      - /dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    networks:
      - monitoring
```
