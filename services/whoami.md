# Service: whoami

Service ví dụ (traefik/whoami) để kiểm tra proxy + SSL hoạt động.
Truy cập `https://whoami.${DOMAIN}` sẽ thấy thông tin request.

> Dùng để test. Có thể tắt sau khi đã chạy ổn.

```yaml
  whoami:
    image: traefik/whoami
    container_name: whoami
    restart: unless-stopped
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`whoami.${DOMAIN}`)"
      - "traefik.http.routers.whoami.entrypoints=websecure"
      - "traefik.http.routers.whoami.tls.certresolver=le"
      - "traefik.http.services.whoami.loadbalancer.server.port=80"
      - "traefik.http.routers.whoami.middlewares=default-chain@file"
```
