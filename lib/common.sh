# lib/common.sh – shared variables, helpers, and utilities
# Source-guarded: safe to source multiple times.
[[ -n "${_TMF637_COMMON_SH:-}" ]] && return
_TMF637_COMMON_SH=1

# Resolve project root relative to this file
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$_LIB_DIR/.." && pwd)"

BASE_URL="http://localhost:8637/tmf-api/productInventoryManagement/v5"
CT="Content-Type: application/json"
PAYLOADS_DIR="$PROJECT_ROOT/payloads"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# IDS_FILE must be set by the caller (main script or standalone scenario).
# Declaring it here so shellcheck knows it exists.
IDS_FILE="${IDS_FILE:-}"

# ─── Logging ───────────────────────────────────────────────────────────────────

log_section() { echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${NC}" >&2; }
log_ok()      { echo -e "  ${GREEN}✓${NC}  $1" >&2; }
log_err()     { echo -e "  ${RED}✗${NC}  $1" >&2; }
log_warn()    { echo -e "  ${YELLOW}⚠${NC}  $1" >&2; }
log_info()    { echo -e "  ${YELLOW}→${NC}  $1" >&2; }

pause() { [[ "${FAST:-0}" == "1" ]] && return; sleep "${1:-0.3}"; }

# ─── Payload helpers ───────────────────────────────────────────────────────────

load_payload() { cat "$PAYLOADS_DIR/$1"; }

# render_payload FILE KEY1 VALUE1 [KEY2 VALUE2 ...]
render_payload() {
  local content
  content=$(cat "$PAYLOADS_DIR/$1"); shift
  while [[ $# -ge 2 ]]; do
    content="${content//__${1}__/$2}"
    shift 2
  done
  printf '%s' "$content"
}

# ─── HTTP helpers ──────────────────────────────────────────────────────────────

# Make a request, log status, return body on stdout.
# Usage: body=$(req LABEL METHOD URL [extra curl args...])
req() {
  local label="$1" method="$2" url="$3"; shift 3
  local resp status body

  resp=$(curl -s -w '\n__STATUS__%{http_code}' -X "$method" "$url" "$@")
  status=$(printf '%s' "$resp" | tail -1 | sed 's/__STATUS__//')
  body=$(printf '%s' "$resp" | sed '$d')

  if [[ "$status" =~ ^2 ]]; then
    log_ok "${label} ${BOLD}$method${NC}${GREEN} $url${NC} → ${GREEN}$status${NC}"
  else
    log_warn "${label} ${BOLD}$method${NC} $url → ${YELLOW}$status${NC}"
    [[ -n "$body" ]] && printf '%s' "$body" | python3 -m json.tool 2>/dev/null >&2 || true
  fi

  printf '%s' "$body"
}

# POST a product; records created ID in IDS_FILE; echoes ID to stdout.
create_product() {
  local label="$1" payload="$2"
  local resp status body id

  resp=$(curl -s -w '\n__STATUS__%{http_code}' -X POST "$BASE_URL/product" \
    -H "$CT" -d "$payload")
  status=$(printf '%s' "$resp" | tail -1 | sed 's/__STATUS__//')
  body=$(printf '%s' "$resp" | sed '$d')
  id=$(printf '%s' "$body" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)

  if [[ "$status" =~ ^2 && -n "$id" ]]; then
    log_ok "${label} → created ${BOLD}id=$id${NC}"
    echo "$id" >> "$IDS_FILE"
    printf '%s' "$id"
  else
    log_err "${label} → $status"
    printf '%s' "$body" | python3 -m json.tool 2>/dev/null >&2 || true
    printf ''
  fi
}

# PATCH a product and log the result.
patch_product() {
  local label="$1" id="$2" payload="$3"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    "$BASE_URL/product/$id" -H "$CT" -d "$payload")
  if [[ "$status" =~ ^2 ]]; then log_ok "${label} → $status"
  else                           log_warn "${label} → $status"
  fi
}

# ─── Cleanup ───────────────────────────────────────────────────────────────────

cleanup() {
  log_section "Cleanup – Deleting products created during this run"
  if [[ ! -s "$IDS_FILE" ]]; then
    log_info "No products to clean up"
    return
  fi
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE_URL/product/$id")
    if [[ "$status" =~ ^2 ]]; then log_ok "Deleted $id → $status"
    else                           log_warn "Could not delete $id → $status"
    fi
  done < "$IDS_FILE"
}
