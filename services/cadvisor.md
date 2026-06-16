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
    command:
      - "-logtostderr"
      # Docker CE dùng containerd HỆ THỐNG ở /run/containerd/containerd.sock
      # (kiểm chứng: `dockerd --containerd=...`). Phải trỏ ĐÚNG socket này thì
      # docker factory mới đăng ký được -> metric container có nhãn 'name'
      # (nếu sai, cadvisor vẫn chạy nhưng metric thiếu 'name' -> Grafana No data).
      # Socket được mount tường minh bên dưới để đường dẫn trong container khớp.
      - "-containerd=/run/containerd/containerd.sock"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /run/containerd/containerd.sock:/run/containerd/containerd.sock:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    networks:
      - monitoring
```
