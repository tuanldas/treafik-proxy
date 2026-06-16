# Service: traefik

Reverse proxy lõi. Tự phát hiện các service khác qua label, expose Traefik
dashboard tại `traefik.${DOMAIN}` (có basic-auth).

> Nên luôn bật service này. Tắt nó đồng nghĩa không có proxy.

**Phụ thuộc:** `traefik/traefik.yml`, `traefik/dynamic/`, thư mục `acme/`.

```yaml
  traefik:
    image: "traefik:${TRAEFIK_VERSION:-v3.7.5}"
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "80:80"
      - "443:443"
    environment:
      - TZ=${TZ:-Asia/Ho_Chi_Minh}
    volumes:
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/dynamic:/etc/traefik/dynamic:ro
      - ./acme:/acme
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - proxy
      - monitoring
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.tls.certresolver=le"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=dashboard-auth@file"
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 5s
      retries: 3
```
