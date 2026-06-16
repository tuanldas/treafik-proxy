# Service: blackbox-exporter

Probe uptime/SSL/HTTP từ góc nhìn người dùng cho từng domain Traefik route.
Không expose ra ngoài — chỉ network `monitoring`. Prometheus gọi qua `/probe`.
Danh sách domain do `setup.sh` SINH từ `Host()` trong các service đang bật
(`prometheus/targets/blackbox.generated.yml`), scheme/module chọn theo cờ `SSL`.

> Thuộc nhóm giám sát. **Phụ thuộc:** `blackbox/blackbox.yml` (module config).
>
> Lưu ý dev: ở `DOMAIN=localhost`, `*.localhost` trong container thường trỏ về
> chính container nên probe có thể không tới Traefik — đây là giới hạn dev. Trên
> production (domain thật, DNS công khai) probe đi đúng tới server. ICMP cần
> `cap_add: [NET_RAW]` — chỉ thêm khi thật sự probe ICMP.

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
