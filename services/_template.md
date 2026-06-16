# Service: <TÊN> (TEMPLATE — copy file này để tạo service mới)

Cách thêm 1 service mới cho hệ thống ~20 service của bạn:

1. Copy file này thành `services/<ten>.md` (vd: `services/api.md`).
2. Sửa block YAML bên dưới: đổi `myapp` thành tên service, `Host(...)`,
   và `server.port` = cổng NỘI BỘ mà container lắng nghe.
3. Thêm cờ `<TÊN>=true` vào `.env` (tên cờ = tên file viết HOA, vd api -> API).
4. Chạy `./setup.sh` rồi `docker compose up -d`.

QUY TẮC block YAML:
- Mỗi file md có ĐÚNG 1 block ```yaml.
- Nội dung là 1 service, thụt lề 2 dấu cách (để nằm dưới `services:`).
- Có thể dùng biến `${DOMAIN}`, `${TZ}`... (lấy từ `.env`).
- Network `proxy` là bắt buộc để Traefik thấy service.

```yaml
  myapp:
    image: nginxdemos/hello
    container_name: myapp
    restart: unless-stopped
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=le"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"
      - "traefik.http.routers.myapp.middlewares=default-chain@file"
```

> Dùng sau Cloudflare (đã có SSL): đổi `entrypoints=websecure` → `entrypoints=web`
> và bỏ dòng `tls.certresolver=le`.
