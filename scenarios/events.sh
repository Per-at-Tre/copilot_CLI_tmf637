#!/usr/bin/env bash
# scenarios/events.sh – Event subscription (hub) register & unregister lifecycle
# Runnable standalone: ./scenarios/events.sh [--fast]

_SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCENARIO_DIR/../lib/common.sh"

scenario_events() {
  log_section "4. Event Subscription (Hub) Lifecycle"

  log_info "Register hub for ProductCreateEvent + ProductStateChangeEvent"
  local hub_resp hub_status hub_body hub_id
  hub_resp=$(curl -s -w '\n__STATUS__%{http_code}' \
    -X POST "$BASE_URL/hub" -H "$CT" \
    -d "$(load_payload hub-subscribe.json)")
  hub_status=$(printf '%s' "$hub_resp" | tail -1 | sed 's/__STATUS__//')
  hub_body=$(printf '%s' "$hub_resp" | sed '$d')
  hub_id=$(printf '%s' "$hub_body" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)

  if [[ "$hub_status" =~ ^2 && -n "$hub_id" ]]; then
    log_ok "Hub registered → id=$hub_id (status=$hub_status)"
  else
    log_warn "Hub registration → $hub_status"
    hub_id=""
  fi
  pause

  if [[ -n "$hub_id" ]]; then
    log_info "Delete hub subscription $hub_id"
    local del_status
    del_status=$(curl -s -o /dev/null -w '%{http_code}' \
      -X DELETE "$BASE_URL/hub/$hub_id")
    if [[ "$del_status" =~ ^2 ]]; then log_ok "Hub deleted → $del_status"
    else                               log_warn "Hub delete → $del_status"
    fi
    pause
  fi

  log_info "Delete non-existent hub (expect 4xx/5xx)"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' \
    -X DELETE "$BASE_URL/hub/no-such-hub-xyz")
  log_warn "DELETE /hub/no-such-hub-xyz → $status"
  pause
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
  scenario_events
  echo -e "\n${BOLD}${GREEN}✓ Done.${NC}"
fi
