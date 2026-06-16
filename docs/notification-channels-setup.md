# Setup thông báo cảnh báo qua các kênh

Hướng dẫn lấy secret + cấu hình từng kênh cho Alertmanager. Áp dụng cho bộ cảnh báo đã triển khai (xem [system-architecture.md](system-architecture.md)).

## Cơ chế

`setup.sh` đọc cờ `ALERT_*` trong `.env` → hàm `generate_alertmanager()` sinh `alertmanager/alertmanager.generated.yml` (chỉ gồm kênh đang bật). Mọi secret nằm trong `.env` (gitignored); file generated cũng gitignored. **Sửa `.env` xong luôn chạy lại `./setup.sh`.**

> ⚠️ **Broadcast, không phải failover.** Bật nhiều kênh = mỗi alert gửi qua **TẤT CẢ** kênh đang bật (nhận trùng), không phải "kênh chính lỗi mới chuyển kênh phụ". Bật nhiều để **redundancy** (không bỏ lỡ), chấp nhận trùng.

## Bước 0 — bật Alertmanager

```dotenv
ALERTMANAGER=true
ALERTMANAGER_VERSION=v0.33.0
```

## Bảng cờ tổng quan

| Kênh | Cờ bật | Secret cần (trong `.env`) |
|------|--------|---------------------------|
| Telegram | `ALERT_TELEGRAM=true` | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` |
| Discord | `ALERT_DISCORD=true` | `DISCORD_WEBHOOK_URL` |
| Slack | `ALERT_SLACK=true` | `SLACK_WEBHOOK_URL` |
| Email | `ALERT_EMAIL=true` | `SMTP_SMARTHOST`, `SMTP_FROM`, `SMTP_TO`, `SMTP_AUTH_USERNAME`, `SMTP_AUTH_PASSWORD` |

---

## 1. Telegram (khuyến nghị — push nhanh, free)

1. **Tạo bot:** chat với [@BotFather](https://t.me/BotFather) → `/newbot` → đặt tên → nhận **bot token** (dạng `123456:ABC-DEF...`).
2. **Lấy chat_id:**
   - Nhắn 1 tin bất kỳ cho bot vừa tạo (hoặc add bot vào group).
   - Mở: `https://api.telegram.org/bot<BOT_TOKEN>/getUpdates` → tìm `"chat":{"id":...}`.
   - Cá nhân: id dương. Group: id **âm** (vd `-1001234567890`).
3. **Điền `.env`:**
   ```dotenv
   ALERT_TELEGRAM=true
   TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
   TELEGRAM_CHAT_ID=987654321
   ```

## 2. Discord

1. **Tạo webhook:** Server → **Server Settings** → **Integrations** → **Webhooks** → **New Webhook** → chọn kênh → **Copy Webhook URL** (dạng `https://discord.com/api/webhooks/<id>/<token>`).
2. **Điền `.env`:**
   ```dotenv
   ALERT_DISCORD=true
   DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/123/abcdef
   ```

## 3. Slack

1. **Tạo incoming webhook:** [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **Incoming Webhooks** → bật **On** → **Add New Webhook to Workspace** → chọn kênh → **Copy Webhook URL** (dạng `https://hooks.slack.com/services/T.../B.../...`).
2. **Điền `.env`:**
   ```dotenv
   ALERT_SLACK=true
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T00/B00/XXXX
   ```

## 4. Email (SMTP)

Ví dụ Gmail (cần bật 2FA → tạo **App Password**, KHÔNG dùng mật khẩu thường):

1. Google Account → **Security** → **2-Step Verification** (bật) → **App passwords** → tạo cho "Mail" → nhận 16 ký tự.
2. **Điền `.env`:**
   ```dotenv
   ALERT_EMAIL=true
   SMTP_SMARTHOST=smtp.gmail.com:587
   SMTP_FROM=alert@yourdomain.com
   SMTP_TO=you@yourdomain.com
   SMTP_AUTH_USERNAME=your-gmail@gmail.com
   SMTP_AUTH_PASSWORD=<app-password 16 ký tự>
   ```
   (Amazon SES / SMTP nội bộ: thay `SMTP_SMARTHOST` + credential tương ứng.)

---

## Áp dụng & kiểm thử

```bash
./setup.sh                 # sinh lại receiver theo cờ
docker compose up -d alertmanager prometheus
# Kiểm config (override entrypoint amtool):
docker run --rm -v "$PWD/alertmanager:/a" --entrypoint amtool \
  prom/alertmanager:v0.33.0 check-config /a/alertmanager.generated.yml
# Test gửi thật:
docker stop whoami         # chờ ~30s → nhận cảnh báo ở (các) kênh bật
docker start whoami        # → nhận "resolved"
```

Dòng log khi `setup.sh` chạy xác nhận kênh nào bật:
```
🔔 alertmanager -> ... (telegram=true slack=false email=false discord=true)
```

## Chống spam (đã cấu hình sẵn)

`generate_alertmanager()` đặt sẵn: `group_by [alertname, instance]`, `group_wait 30s`, `repeat_interval 4h` (critical 1h), và `inhibit_rules` (host `InstanceDown` nuốt mọi warning cùng host). Không cần chỉnh thêm cho dùng cơ bản.

## Xử lý sự cố

| Triệu chứng | Nguyên nhân / cách xử lý |
|-------------|--------------------------|
| Không nhận gì | `ALERTMANAGER=true`? Đúng (các) cờ `ALERT_*`? Đã `./setup.sh` lại chưa? |
| `setup.sh` cảnh báo "cả 4 kênh tắt" | Bật `ALERTMANAGER` mà chưa bật kênh nào — set ít nhất 1 `ALERT_*=true` |
| Telegram im | Sai `chat_id` (group phải số âm), hoặc chưa nhắn cho bot lần đầu |
| Email lỗi auth | Gmail phải dùng **App Password**, không phải mật khẩu thường; đúng port `:587` |
| `amtool` báo lỗi field | Secret để trống → điền giá trị thật rồi `./setup.sh` |
| Nhận TRÙNG nhiều kênh | Đúng thiết kế (broadcast). Muốn 1 kênh: tắt các `ALERT_*` còn lại |

## Mở rộng (chưa làm — YAGNI)

Phân kênh theo severity (vd Discord chỉ `critical`) cần route tree đa-receiver trong `generate_alertmanager()` — xem [project-roadmap.md](project-roadmap.md).
