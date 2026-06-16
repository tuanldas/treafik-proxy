# Project Overview & PDR

> Quick-start, cấu hình `.env`, vận hành cơ bản: xem [`README.md`](../README.md). Tài liệu này tập trung **mục tiêu, phạm vi, và quyết định kiến trúc cốt lõi**.

## Là gì

Stack **reverse proxy Traefik + giám sát Prometheus/Grafana** chạy bằng Docker Compose, với điểm đặc biệt: `docker-compose.yml` **không viết tay** mà **sinh tự động** từ các file mô tả service (`services/*.md`) dựa trên cờ bật/tắt trong `.env`, qua `setup.sh`.

## Vấn đề giải quyết

- **Quản lý compose thủ công dễ sai** khi nhiều service → tách mỗi service thành 1 file mô tả độc lập, bật/tắt bằng 1 cờ.
- **Thiếu quan sát hệ thống** → tích hợp sẵn bộ giám sát (metrics) + cảnh báo (alerting) + uptime + log tập trung, bám chuẩn ngành (USE / RED / 4 Golden Signals).
- **Rò rỉ bí mật** → mọi secret nằm trong `.env` (gitignored); file sinh chứa secret cũng gitignored.

## Đối tượng

DevOps / sysadmin tự vận hành 1 server (hoặc vài server) cần reverse proxy + observability mà không muốn dựng Kubernetes. Triển khai đích: **Linux production (Ubuntu / CentOS)**; phát triển trên macOS/Docker Desktop.

## Phạm vi

**Trong phạm vi:**
- Sinh `docker-compose.yml` từ `services/*.md` + `.env`.
- Reverse proxy Traefik (auto-discovery qua label, Let's Encrypt / Cloudflare SSL).
- Observability: Prometheus, Grafana, node-exporter, cAdvisor, Alertmanager (4 kênh báo), Blackbox (uptime/SSL), Loki + Alloy (logs).

**Ngoài phạm vi (non-goals):**
- Không orchestration đa-node (Swarm/K8s) — single-host.
- Không CI/CD pipeline.
- Không quản lý DB/app — chỉ proxy + giám sát chúng (exporter DB là optional, chờ backend thật).

## Quyết định kiến trúc cốt lõi

| Quyết định | Lý do |
|-----------|-------|
| **Codegen compose** từ `services/*.md` + `.env` | Mỗi service độc lập, bật/tắt 1 cờ; không sửa file sinh |
| **1 service = 1 file `.md`** (đúng 1 block ```yaml) | Tự-tài-liệu-hoá; mô tả + fragment compose cùng chỗ |
| **Prometheus Alertmanager** (không Grafana Unified Alerting) | Rule là code version-control được; alert độc lập Grafana |
| **Kênh báo chọn qua `.env`** (Telegram/Slack/Email/Discord) | `setup.sh` sinh receiver theo cờ — như pattern `auth.generated.yml` |
| **Secret ghi vào file generated + gitignore** | Nhất quán pattern repo; `docker inspect` không lộ (không qua `environment:`) |
| **Exporter chỉ ở network `monitoring`** | `/metrics` không expose internet |
| **Bind-mount cho service mới** (Loki) | Header volume `setup.sh` cố định 2 volume; bind-mount né sửa generator |

## Trạng thái hiện tại

Observability stack đã triển khai đầy đủ (xem [project-roadmap.md](project-roadmap.md)): **10 service**, **15 alert rules**, **4 kênh báo**, **5 dashboard**, **log tập trung**. Còn lại: exporter DB (optional, chờ backend), test runtime với secret thật, test SELinux trên CentOS.

## Tài liệu liên quan

- [system-architecture.md](system-architecture.md) — kiến trúc & luồng dữ liệu
- [deployment-guide.md](deployment-guide.md) — triển khai & vận hành
- [notification-channels-setup.md](notification-channels-setup.md) — setup kênh báo (Telegram/Discord/Slack/Email)
- [code-standards.md](code-standards.md) — quy ước repo
- [codebase-summary.md](codebase-summary.md) — cấu trúc mã nguồn
- [project-roadmap.md](project-roadmap.md) — lộ trình & trạng thái
