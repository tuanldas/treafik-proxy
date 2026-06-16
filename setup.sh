#!/usr/bin/env bash
# ============================================================
# setup.sh — Ghép service thành docker-compose.yml hoàn chỉnh.
#
#   - Nguồn service:  services/<ten>.md  (mỗi file 1 block ```yaml)
#   - traefik:        LUÔN bắt buộc (không cần cờ)
#   - service khác:   bật/tắt bằng cờ <TÊN>=true/false trong .env
#                     (tên cờ = tên file viết HOA, vd grafana -> GRAFANA)
#
#   Dùng:  ./setup.sh           # sinh docker-compose.yml
#          ./setup.sh --up      # sinh xong chạy luôn docker compose up -d
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=".env"
SERVICES_DIR="services"
OUT="docker-compose.yml"

[ -f "$ENV_FILE" ] || { echo "❌ Không thấy $ENV_FILE"; exit 1; }
[ -f "${SERVICES_DIR}/traefik.md" ] || { echo "❌ Thiếu ${SERVICES_DIR}/traefik.md (bắt buộc)"; exit 1; }

# --- Lấy giá trị 1 biến trong .env (cho cờ true/false) ------
get_flag() {
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$ENV_FILE" \
    | tail -n1 | cut -d= -f2- | tr -d '"' | tr -d "'" | sed 's/#.*//' | xargs
}

# --- Lấy giá trị thô (giữ nguyên, dùng cho mật khẩu) --------
get_raw() {
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$ENV_FILE" \
    | tail -n1 | sed -E "s/^[[:space:]]*$1[[:space:]]*=//" \
    | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

# --- Hash mật khẩu -> "user:hash" (định dạng htpasswd) ------
# Thử lần lượt: openssl(apr1) -> htpasswd -> docker httpd
hash_cred() {
  local user="$1" pass="$2"
  if command -v openssl >/dev/null 2>&1 && echo | openssl passwd -apr1 -stdin >/dev/null 2>&1; then
    printf '%s:%s' "$user" "$(printf '%s' "$pass" | openssl passwd -apr1 -stdin)"
  elif command -v htpasswd >/dev/null 2>&1; then
    htpasswd -nbB "$user" "$pass"
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm httpd:alpine htpasswd -nbB "$user" "$pass" 2>/dev/null
  else
    return 1
  fi
}

# --- True? (true/1/yes/on, không phân biệt hoa thường) ------
is_true() {
  case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# --- tên service -> tên biến cờ (HOA, ký tự lạ -> _) --------
to_var() { echo "$1" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g'; }

# --- Trích block ```yaml đầu tiên trong 1 file md ----------
extract_yaml() {
  awk '
    /^```ya?ml[[:space:]]*$/ { inblock=1; next }
    inblock && /^```/        { exit }
    inblock                  { print }
  ' "$1"
}

# --- Áp cờ SSL lên 1 block service --------------------------
# SSL=false: chuyển router sang HTTP (entrypoint web), bỏ certresolver.
apply_ssl() {
  if is_true "$SSL_FLAG"; then
    cat
  else
    sed -e 's/entrypoints=websecure/entrypoints=web/g' \
        -e '/tls\.certresolver=/d'
  fi
}

# --- Bật/tắt khối redirect HTTP->HTTPS trong traefik.yml ----
toggle_redirect() {
  local f="traefik/traefik.yml" on="0"
  is_true "$SSL_FLAG" && on="1"
  [ -f "$f" ] || return 0
  awk -v on="$on" '
    /# >>> SSL_REDIRECT/ { print; ins=1; next }
    /# <<< SSL_REDIRECT/ { print; ins=0; next }
    ins==1 {
      match($0, /^[[:space:]]*/); ind=substr($0,1,RLENGTH); rest=substr($0,RLENGTH+1)
      if (on=="1") { sub(/^# ?/, "", rest); print ind rest }
      else        { if (rest !~ /^#/) rest="# " rest; print ind rest }
      next
    }
    { print }
  ' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

# --- Cập nhật tên network proxy trong traefik.yml -----------
set_traefik_network() {
  local f="traefik/traefik.yml" name="$1"
  [ -f "$f" ] || return 0
  awk -v n="$name" '
    /# PROXY_NET/ {
      match($0, /^[[:space:]]*/); ind=substr($0,1,RLENGTH)
      print ind "network: " n "  # PROXY_NET (setup.sh tự cập nhật theo PROXY_NETWORK trong .env)"
      next
    }
    { print }
  ' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

# --- Ghi 1 service vào output -------------------------------
append_service() {
  local name="$1" file="${SERVICES_DIR}/$1.md"
  local block; block="$(extract_yaml "$file" | apply_ssl)"
  if [ -z "${block// /}" ]; then
    echo "⚠️  '${name}': không có block \`\`\`yaml trong ${file}" >&2
    return 1
  fi
  {
    echo "  # ----- ${name} (services/${name}.md) -----"
    echo "$block"
    echo
  } >> "$OUT"
}

# --- Cờ SSL (true = Let's Encrypt, false = SSL ngoài/Cloudflare) ---
SSL_FLAG="$(get_flag SSL)"; [ -z "$SSL_FLAG" ] && SSL_FLAG="true"

# Bật/tắt redirect HTTP->HTTPS trong traefik.yml theo cờ SSL
toggle_redirect
if is_true "$SSL_FLAG"; then
  echo "  🔐 SSL=on  — Traefik tự xin Let's Encrypt, có redirect HTTPS"
else
  echo "  🔓 SSL=off — dùng SSL ngoài (Cloudflare): origin HTTP, không cert, không redirect"
fi

# --- Tạo nơi lưu chứng chỉ (chỉ tạo ban đầu; acme.json đã .gitignore) ---
if [ ! -f acme/acme.json ]; then
  mkdir -p acme && touch acme/acme.json && chmod 600 acme/acme.json
  echo "  📁 Đã tạo acme/acme.json (quyền 600)"
else
  chmod 600 acme/acme.json 2>/dev/null || true
fi

# --- Sinh basic-auth dashboard từ mật khẩu thường trong .env ---
AUTH_FILE="traefik/dynamic/auth.generated.yml"
DUSER="$(get_raw TRAEFIK_DASHBOARD_USER)"; DUSER="${DUSER:-admin}"
DPASS="$(get_raw TRAEFIK_DASHBOARD_PASSWORD)"
if [ -z "$DPASS" ]; then
  echo "⚠️  TRAEFIK_DASHBOARD_PASSWORD trống — bỏ qua tạo basic-auth dashboard." >&2
else
  CRED="$(hash_cred "$DUSER" "$DPASS")" || {
    echo "❌ Không hash được mật khẩu (cần openssl, htpasswd hoặc docker)."; exit 1; }
  {
    echo "# SINH TỰ ĐỘNG bởi setup.sh — ĐỪNG SỬA TAY (chứa hash mật khẩu dashboard)."
    echo "# Đổi mật khẩu: sửa TRAEFIK_DASHBOARD_PASSWORD trong .env rồi chạy ./setup.sh"
    echo "http:"
    echo "  middlewares:"
    echo "    dashboard-auth:"
    echo "      basicAuth:"
    echo "        users:"
    echo "          - \"${CRED}\""
  } > "$AUTH_FILE"
  echo "  🔒 dashboard-auth: user='${DUSER}' -> ${AUTH_FILE}"
fi

# --- Tên network/volume (đổi được trong .env) ---------------
PROXY_NET="$(get_flag PROXY_NETWORK)";        PROXY_NET="${PROXY_NET:-proxy}"
MONITORING_NET="$(get_flag MONITORING_NETWORK)"; MONITORING_NET="${MONITORING_NET:-monitoring}"
PROM_VOL="$(get_flag PROMETHEUS_VOLUME)";     PROM_VOL="${PROM_VOL:-prometheus-data}"
GRAFANA_VOL="$(get_flag GRAFANA_VOLUME)";     GRAFANA_VOL="${GRAFANA_VOL:-grafana-data}"

# Đồng bộ tên network proxy vào traefik.yml (static config không đọc được .env)
set_traefik_network "$PROXY_NET"

# --- Header (networks + volumes) ----------------------------
{
  echo "# ============================================================"
  echo "# FILE NÀY ĐƯỢC SINH TỰ ĐỘNG bởi setup.sh — ĐỪNG SỬA TAY."
  echo "# Sửa service trong services/*.md, bật/tắt bằng cờ trong .env, rồi ./setup.sh"
  echo "# Tạo lúc: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "# ============================================================"
  echo
  echo "networks:"
  echo "  proxy:"
  echo "    name: \${PROXY_NETWORK:-proxy}"
  echo "  monitoring:"
  echo "    name: \${MONITORING_NETWORK:-monitoring}"
  echo
  echo "volumes:"
  echo "  prometheus-data:"
  echo "    name: \${PROMETHEUS_VOLUME:-prometheus-data}"
  echo "  grafana-data:"
  echo "    name: \${GRAFANA_VOLUME:-grafana-data}"
  echo
  echo "services:"
} > "$OUT"

# --- traefik: luôn có ---------------------------------------
append_service "traefik"
echo "  ✓ traefik (bắt buộc)"
enabled=("traefik")

# --- Các service tuỳ chọn: duyệt services/*.md, đọc cờ ------
for file in "$SERVICES_DIR"/*.md; do
  base="$(basename "$file" .md)"
  [ "$base" = "traefik" ] && continue          # đã thêm
  case "$base" in _*) continue ;; esac          # bỏ _template, file _*
  var="$(to_var "$base")"
  val="$(get_flag "$var" || true)"
  if is_true "$val"; then
    if append_service "$base"; then
      echo "  ✓ ${base}  (${var}=${val})"
      enabled+=("$base")
    fi
  else
    echo "  ·  ${base}  (${var}=${val:-unset}) — tắt"
  fi
done

echo
echo "✅ Đã sinh ${OUT} với ${#enabled[@]} service: ${enabled[*]}"

# --- Nhắc trỏ DNS -------------------------------------------
DOMAIN_VAL="$(get_raw DOMAIN)"; DOMAIN_VAL="${DOMAIN_VAL:-example.com}"
HOSTS="$(grep -oE 'Host\(`[^`]+`\)' "$OUT" | sed -E 's/Host\(`(.*)`\)/\1/' \
  | sed "s/\${DOMAIN[^}]*}/${DOMAIN_VAL}/g" | sort -u)"
if [ -n "$HOSTS" ]; then
  SCHEME="https"; is_true "$SSL_FLAG" || SCHEME="http (origin) — public https do Cloudflare"
  echo
  echo "🌐 Nhớ trỏ DNS (bản ghi A về IP server) cho các tên sau, mở cổng 80/443:"
  echo "$HOSTS" | sed "s#^#     - ${SCHEME%% *}://#"
  echo "   (Hoặc 1 bản ghi wildcard *.${DOMAIN_VAL}. Local: xem mục DOMAIN trong README.)"
fi

# --- Tuỳ chọn: chạy luôn ------------------------------------
if [ "${1:-}" = "--up" ]; then
  echo
  echo "▶️  docker compose up -d ..."
  docker compose up -d
fi
