# Code Standards & Conventions

Quy ước cho repo này. Tuân YAGNI / KISS / DRY.

## Quy tắc vàng

1. **KHÔNG sửa file sinh tự động.** `docker-compose.yml`, `auth.generated.yml`, `alertmanager.generated.yml`, `blackbox.generated.yml` là output — sửa sẽ bị ghi đè. Sửa nguồn (`services/*.md`, `.env`, `setup.sh`) rồi chạy `./setup.sh`.
2. **KHÔNG hardcode secret.** Mật khẩu/token/webhook/DSN lấy từ `.env`. File sinh chứa secret phải `.gitignore`.
3. **Mỗi `services/*.md` chỉ 1 block ```yaml**, thụt lề **2 space** (nằm dưới `services:`). File bắt đầu bằng `_` bị bỏ qua.

## Service descriptor (`services/<ten>.md`)

- Tên file kebab-case; cờ bật = tên HOA, ký tự không alphanumeric → `_` (vd `node-exporter.md` → `NODE_EXPORTER`).
- Cấu trúc: tiêu đề + mô tả ngắn (mục đích, network, expose hay không) + ghi chú phụ thuộc + đúng 1 block ```yaml.
- Service muốn Traefik route: network `proxy` + label `traefik.enable=true` + router rule/entrypoint/service.
- Service giám sát (exporter): chỉ network `monitoring`, KHÔNG label Traefik (không expose `/metrics`).
- Pin version qua biến `.env` với default: `image: "repo/img:${X_VERSION:-vN.N.N}"`. **Verify tag thật bằng `docker pull` trước khi pin** — không dùng `latest`.

## `.env`

- **⚠️ Đồng bộ `.env.example` (BẮT BUỘC):** mỗi khi thêm/sửa/xoá biến trong `.env`, cập nhật `.env.example` NGAY. `.env` đã gitignored → `.env.example` là tài liệu biến duy nhất commit được; quên đồng bộ = người clone repo thiếu biến, `setup.sh` chạy sai. Secret để **TRỐNG** trong example; tính năng nâng cao cần secret để default `false`. Kiểm nhanh: không biến nào trong `setup.sh` (`get_flag`/`get_raw`) hay `services/*.md` (`${...}`) bị thiếu khỏi `.env.example`.
- Cờ bật/tắt: `<TÊN>=true|false` (chấp nhận true/1/yes/on).
- Khai báo **tên biến** secret kèm giá trị rỗng; điền giá trị thật khi deploy. Không commit giá trị.
- Mỗi khối service nhóm lại, có comment tiêu đề.

## `setup.sh` (bash)

- `set -euo pipefail`; helper tái dùng: `get_flag`, `get_raw`, `is_true`, `to_var`, `extract_yaml`, `apply_ssl`.
- Sinh config theo cờ → đặt hàm `generate_<x>()`, gọi có điều kiện `is_true "$(get_flag <FLAG>)"`.
- File generated chứa secret: header cảnh báo "ĐỪNG SỬA TAY" + thêm vào `.gitignore`.
- Pattern mới phải **DRY** với pattern có sẵn (vd thêm kênh báo = sao chép nhánh Slack trong `generate_alertmanager`).

## Config observability

- **PromQL/alert:** validate bằng `promtool check rules` trước khi commit. Comment mô tả hành vi, **không** ghi số phase/plan ID.
- **Alertmanager:** validate bằng `amtool check-config` (override `--entrypoint amtool`).
- **Dashboard JSON:** validate `jq empty`; dùng biến `${datasource}` (không uid cứng); prefix số để sắp thứ tự (`00-` lên đầu).
- **Alloy River:** validate `alloy fmt`. **Loki:** `loki -verify-config`.

## Git

- Conventional commits **tiếng Việt**, có scope: `feat(monitoring): ...`, `fix(grafana): ...`, `docs: ...`.
- KHÔNG ghi số phase/plan ID/AI references trong commit message — mô tả hành vi trực tiếp.
- KHÔNG commit `.env`, `acme/`, file `*.generated.yml`, `*/data/`.

## Modularization

- File markdown/config/bash/env: KHÔNG cần tách theo ngưỡng dòng.
- `setup.sh`: nếu phình lớn, tách hàm theo concern (sinh compose / sinh config / áp SSL) — hiện vẫn trong 1 file, chấp nhận được.
