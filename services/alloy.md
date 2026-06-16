# Service: alloy

Grafana Alloy — thu log mọi container Docker qua socket rồi đẩy sang Loki.
THAY Promtail (đã EOL 2026-03-02). Chỉ network `monitoring`, không expose.
Đọc Docker socket ở chế độ chỉ-đọc.

> Thuộc nhóm giám sát. **Phụ thuộc:** `alloy/config.alloy`. Cần `loki` bật trước.
>
> Lưu ý CentOS/RHEL (SELinux): SELinux enforcing có thể CHẶN container đọc
> `/var/run/docker.sock`. Nếu Alloy không thu được log, thêm `:z` vào bind-mount
> hoặc `--security-opt label=disable` (cân nhắc bảo mật). PHẢI test trên CentOS.

```yaml
  alloy:
    image: "grafana/alloy:${ALLOY_VERSION:-v1.17.0}"
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
