# Service: alertmanager

Nhận alert từ Prometheus, gom nhóm/ức chế/định tuyến rồi gửi thông báo. Kênh gửi
(Telegram/Slack/Email) bật/tắt bằng cờ `ALERT_TELEGRAM/ALERT_SLACK/ALERT_EMAIL`
trong `.env`. Chỉ nằm trong network `monitoring`, không expose ra ngoài.

> Thuộc nhóm giám sát. Bật cùng `prometheus`. File cấu hình
> `alertmanager/alertmanager.generated.yml` do `setup.sh` SINH từ `.env` (chứa
> secret thật → đã `.gitignore`, giống `auth.generated.yml`). Đừng sửa tay.

**Phụ thuộc:** `alertmanager/alertmanager.generated.yml` (setup.sh sinh khi `ALERTMANAGER=true`).

```yaml
  alertmanager:
    image: "prom/alertmanager:${ALERTMANAGER_VERSION:-v0.33.0}"
    container_name: alertmanager
    restart: unless-stopped
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"
    volumes:
      - ./alertmanager/alertmanager.generated.yml:/etc/alertmanager/alertmanager.yml:ro
      - ./alertmanager/data:/alertmanager
    networks:
      - monitoring
```
