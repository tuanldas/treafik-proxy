# Service: loki

Log aggregation (single-binary, `-target=all` mặc định). Chỉ network `monitoring`,
không expose ra ngoài. Lưu trữ qua **bind-mount** `./loki/data` (KHÔNG named volume
— header `setup.sh` chỉ khai báo prometheus-data/grafana-data).

> Thuộc nhóm giám sát. **Phụ thuộc:** `loki/loki-config.yml`. Datasource Loki thêm
> ở `grafana/provisioning/datasources/loki.yml` (Grafana auto-load).
>
> Lưu ý Linux: container Loki chạy user 10001 — `./loki/data` cần ghi được
> (`chown -R 10001:10001 loki/data` nếu gặp lỗi permission). retention cấu hình
> trong `loki/loki-config.yml` (mặc định ở đây 744h ≈ 31 ngày).

```yaml
  loki:
    image: "grafana/loki:${LOKI_VERSION:-3.7.2}"
    container_name: loki
    restart: unless-stopped
    command: "-config.file=/etc/loki/loki-config.yml"
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - ./loki/data:/loki
    networks:
      - monitoring
```
