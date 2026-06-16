---
phase: 8
title: "P1 Discord Channel"
status: pending
priority: P1
effort: "1h"
dependencies: [2]
---

# Phase 8: P1 — Thêm kênh Discord cho Alertmanager

## Overview
Bổ sung Discord làm kênh notification thứ 4 (cùng Telegram/Slack/Email), **chọn bật/tắt qua `.env`** đúng pattern đã có. Mở rộng `generate_alertmanager()` của phase 2 — thêm 1 block `discord_configs`. DRY: cơ chế y hệt Slack.

> **Đã verify (docker amtool, 2026-06-16):** Alertmanager `v0.33.0` hỗ trợ `discord_configs` native (thêm từ v0.25.0). `check-config` PASS với webhook giả.

## Requirements
- Functional: bật `ALERT_DISCORD=true` → alert gửi sang Discord qua webhook; `false` → không sinh block.
- Functional: secret `DISCORD_WEBHOOK_URL` chỉ trong `.env`, ghi vào file generated (đã gitignore) — không hardcode.
- Non-functional: nhất quán cơ chế 3 kênh hiện có; không phá receiver/route hiện tại.

## Architecture
Discord nằm **cùng receiver `notify`** với các kênh khác → **broadcast**: khi bật, Discord nhận MỌI alert giống Telegram/Slack/Email (xem Risk — không phải failover, không phân loại). `discord_configs` chỉ cần `webhook_url` + `send_resolved`.

```yaml
receivers:
  - name: 'notify'
    telegram_configs: [...]   # nếu ALERT_TELEGRAM
    discord_configs:          # nếu ALERT_DISCORD  ← THÊM
      - webhook_url: '<DISCORD_WEBHOOK_URL>'
        send_resolved: true
```

## Related Code Files
- Modify: `setup.sh` — trong `generate_alertmanager()`, thêm nhánh `is_true "$dc"` ghi block `discord_configs` (đặt cạnh slack, cùng pattern)
- Modify: `.env` — thêm `ALERT_DISCORD=false` + `DISCORD_WEBHOOK_URL=`
- Modify: `README.md` (nếu có liệt kê kênh báo) — thêm Discord vào danh sách

## Test-First (TDD)
1. **Sinh đúng theo cờ:** `ALERT_DISCORD=true` + webhook giả → `./setup.sh` → `grep discord_configs alertmanager/alertmanager.generated.yml` thấy block; `ALERT_DISCORD=false` → KHÔNG có.
2. **Config hợp lệ:** `docker run --rm -v $PWD/alertmanager:/a --entrypoint amtool prom/alertmanager:v0.33.0 check-config /a/alertmanager.generated.yml` PASS (bản copy điền webhook giả nếu test khi secret trống).
3. **Không lộ secret:** `git check-ignore alertmanager/alertmanager.generated.yml` vẫn trả path; webhook không xuất hiện trong git/`docker inspect`.
4. **End-to-end (cần webhook thật):** tạo webhook ở Discord (Server Settings → Integrations → Webhooks), điền `.env` → `docker stop whoami` → tin nhắn xuất hiện ở kênh Discord; `docker start` → "resolved".

## Implementation Steps
1. **`setup.sh`** — trong `generate_alertmanager()`, sau nhánh `slack`, thêm:
   ```bash
   dc="$(get_flag ALERT_DISCORD)"
   if is_true "$dc"; then
     echo "    discord_configs:"
     echo "      - webhook_url: '$(get_raw DISCORD_WEBHOOK_URL)'"
     echo "        send_resolved: true"
   fi
   ```
   Cập nhật dòng log cuối hàm để gồm `discord=${dc:-off}` và điều kiện "cả 4 kênh tắt" (đổi `! is_true "$tg" && ... && ! is_true "$dc"`).
2. **`.env`** — thêm dưới khối Alertmanager:
   ```dotenv
   ALERT_DISCORD=false
   DISCORD_WEBHOOK_URL=
   ```
3. **`README.md`** — nếu có mục liệt kê kênh báo, thêm Discord.
4. Chạy TDD 1→3 (4 cần webhook thật).

## Success Criteria
- [ ] `ALERT_DISCORD=true/false` sinh/không sinh block `discord_configs` đúng (grep).
- [ ] `amtool check-config` PASS sau khi bật Discord.
- [ ] Secret webhook không bị track / không trong `docker inspect`.
- [ ] (Có webhook thật) alert + resolved xuất hiện ở kênh Discord.

## Risk Assessment
- **Broadcast, KHÔNG phải failover:** bật Discord cùng kênh khác = nhận TRÙNG ở mọi kênh (đã giải thích cho user). Nếu muốn Discord chỉ nhận `critical` (phân loại) → cần tách receiver + `route` matchers — **scope riêng**, không thuộc phase này (giữ KISS/DRY).
- **Escape webhook URL:** URL Discord chỉ gồm `https://discord.com/api/webhooks/<id>/<token>` (an toàn, không ký tự phá YAML) → single-quote là đủ.
- **Rate limit Discord:** webhook Discord giới hạn ~30 msg/phút; với grouping + inhibition hiện có thì không chạm. Nếu alert bão → group_wait/group_interval đã chặn.
- **Thấp tổng thể:** mở rộng pattern đã chạy, đã verify native support. Rollback: `ALERT_DISCORD=false` + `./setup.sh`.
