#!/usr/bin/env bash
# scenarios/notify.sh – POST to all notification listener endpoints
# Runnable standalone: ./scenarios/notify.sh [--fast]

_SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCENARIO_DIR/../lib/common.sh"

scenario_notify() {
  log_section "5. Notification Listener Endpoints"

  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  declare -a events=(
    "productCreateEvent|ProductCreateEvent"
    "productDeleteEvent|ProductDeleteEvent"
    "productStateChangeEvent|ProductStateChangeEvent"
    "productAttributeValueChangeEvent|ProductAttributeValueChangeEvent"
    "productProductBatchEvent|ProductProductBatchEvent"
  )

  for entry in "${events[@]}"; do
    local path="${entry%%|*}" etype="${entry##*|}"
    log_info "POST /listener/$path ($etype)"
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' \
      -X POST "$BASE_URL/listener/$path" -H "$CT" \
      -d "$(render_payload notification-event.tmpl.json \
            EVENT_TYPE "$etype" \
            EVENT_ID   "sim-evt-$(date +%s)" \
            EVENT_TIME "$now")")
    if [[ "$status" =~ ^2 ]]; then
      log_ok "POST /listener/$path → $status"
    else
      log_warn "POST /listener/$path → $status  (server may not require listener impl)"
    fi
    pause
  done
}

# ─── Standalone execution ──────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  for arg in "$@"; do
    case "$arg" in
      --fast) export FAST=1 ;;
      -h|--help) echo "Usage: $(basename "$0") [--fast]"; exit 0 ;;
    esac
  done
  IDS_FILE=$(mktemp); trap 'rm -f "$IDS_FILE"' EXIT
  scenario_notify
  echo -e "\n${BOLD}${GREEN}✓ Done.${NC}"
fi
