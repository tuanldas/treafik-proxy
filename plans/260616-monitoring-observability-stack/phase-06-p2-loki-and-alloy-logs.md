---
phase: 6
title: "P2 Loki and Alloy Logs"
status: pending
priority: P2
effort: "1d"
dependencies: []
---

# Phase 6: P2 — Log tập trung (Loki + Grafana Alloy)

## Overview
Thu log mọi container Docker về Loki, xem cạnh metric trong Grafana. Dùng **Grafana Alloy** (KHÔNG Promtail — đã EOL 2026-03-02). Độc lập các phase khác.

## Requirements
- Functional: Alloy thu log container qua docker.sock → đẩy Loki; datasource Loki trong Grafana; query LogQL được.
- Non-functional: nhãn `container` khớp `name` của cAdvisor (xem log+metric cùng container); **phải set retention** (Loki mặc định giữ vô hạn).

## Architecture
`alloy` (đọc `/var/run/docker.sock:ro`, River config) → `loki:3100/loki/api/v1/push`. Loki single-binary `-target=all`, lưu **bind-mount** `./loki/data` (né header volume `setup.sh`). Grafana thêm datasource Loki qua provisioning (file mới, auto-load).

## Related Code Files
- Create: `services/loki.md` (bind-mount `./loki/data`)
- Create: `services/alloy.md` (mount docker.sock ro)
- Create: `loki/loki-config.yml` (có `limits_config.retention_period` + compactor `retention_enabled: true`)
- Create: `alloy/config.alloy` (River: discovery.docker → relabel → loki.source.docker → loki.write)
- Create: `grafana/provisioning/datasources/loki.yml` (datasource Loki, isDefault:false)
- Modify: `.env` (cờ `LOKI`, `ALLOY`, version)
- Modify: `.gitignore` (thêm `loki/data/`)

## Test-First (TDD)
1. `docker compose config >/dev/null` hợp lệ sau khi bật cờ.
2. Sau up: `curl -s http://localhost:3100/ready` (trong network) trả `ready`.
3. Grafana → Explore → datasource Loki → `{job="docker"}` trả log container.
4. `{container="traefik"}` trả đúng log Traefik (nhãn khớp cAdvisor).
5. Kiểm `loki-config.yml` có `retention_period` ≠ vô hạn (vd `744h`).

## Implementation Steps
1. **`services/loki.md`** — `grafana/loki:${LOKI_VERSION:-<verify>}`, command `-config.file=/etc/loki/loki-config.yml`, mount config + `./loki/data:/loki`, network `monitoring`.
2. **`services/alloy.md`** — `grafana/alloy:${ALLOY_VERSION:-<verify>}`, command `run --server.http.listen-addr=0.0.0.0:12345 --storage.path=/var/lib/alloy/data /etc/alloy/config.alloy`, mount `./alloy/config.alloy:...:ro` + `/var/run/docker.sock:/var/run/docker.sock:ro`, network `monitoring`. **Phụ thuộc loki bật trước.**
3. **`alloy/config.alloy`** (River) — `discovery.docker` (host socket) → `discovery.relabel` (`__meta_docker_container_name` regex `/(.*)` → label `container`) → `loki.source.docker` (labels `{job="docker"}`, forward) → `loki.write` (`http://loki:3100/...`).
4. **`loki/loki-config.yml`** — single-binary, filesystem store, **`limits_config.retention_period: 744h`** (31 ngày, khớp Prometheus 30d) + `compactor.retention_enabled: true` + `delete_request_store: filesystem`.
5. **`grafana/provisioning/datasources/loki.yml`** — `type: loki`, `url: http://loki:3100`, `isDefault: false`.
6. **`.env`** — `LOKI=true`, `ALLOY=true`, versions (verify).
7. **`.gitignore`** — `loki/data/`.
8. Chạy TDD.

## Success Criteria
- [ ] Loki `/ready` OK; Alloy chạy không lỗi.
- [ ] Query `{job="docker"}` và `{container="<ten>"}` trả log trong Grafana.
- [ ] Retention đã set (không vô hạn).
- [ ] Loki/Alloy không expose ra ngoài (chỉ `monitoring`).

## Risk Assessment
- **CentOS/RHEL + SELinux (rủi ro cao nhất phase này):** SELinux enforcing **chặn container đọc `/var/run/docker.sock`** và bind-mount → Alloy không thu được log. Khắc phục: thêm `:z`/`:Z` cho bind-mount hoặc `--security-opt label=disable` cho alloy (cân nhắc bảo mật), hoặc chỉnh policy. **Phải test riêng trên CentOS**, không suy ra từ Ubuntu/macOS.
- **cgroup v1 vs v2:** Ubuntu mới + CentOS 9 dùng cgroup v2; không ảnh hưởng Alloy nhưng liên quan cAdvisor (ngoài phase này).
- **docker.sock = quyền lớn:** Alloy đọc socket ro nhưng vẫn nhạy cảm; giữ alloy trong `monitoring`, không expose.
- **Bind-mount quyền:** `./loki/data` cần Loki (user 10001) ghi được — chú ý ownership trên Linux (`chown` hoặc `user:` trong compose).
- **Tài nguyên:** single-binary đủ ~20GB log/ngày/host; vượt thì tách. Giữ nhãn thấp (chỉ `container`/`job`) tránh cardinality bomb.
- **Version Loki/Alloy:** verify tag patch bằng `docker pull` trước khi pin (releases ra nhanh).
