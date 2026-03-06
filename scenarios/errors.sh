#!/usr/bin/env bash
# scenarios/errors.sh – Error and edge-case traffic (4xx / 5xx responses)
# Runnable standalone: ./scenarios/errors.sh [--fast]

_SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCENARIO_DIR/../lib/common.sh"

scenario_errors() {
  log_section "3. Error & Edge-Case Traffic"

  local cases=(
    "404 – GET non-existent product|GET|$BASE_URL/product/does-not-exist-xyz"
    "404 – PATCH non-existent product|PATCH|$BASE_URL/product/ghost-no-such-id"
    "404 – DELETE non-existent product|DELETE|$BASE_URL/product/ghost-no-such-id"
    "404 – DELETE non-existent hub|DELETE|$BASE_URL/hub/hub-no-such-id"
  )

  for entry in "${cases[@]}"; do
    local label="${entry%%|*}" rest="${entry#*|}"
    local method="${rest%%|*}" url="${rest##*|}"
    log_info "$label"
    local status
    if [[ "$method" == "PATCH" ]]; then
      status=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "$url" \
        -H "$CT" -d "$(load_payload product-patch-status-active.json)")
    else
      status=$(curl -s -o /dev/null -w '%{http_code}' -X "$method" "$url")
    fi
    log_warn "$method $url → $status"
    pause
  done

  log_info "400 – POST missing @type field"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/product" \
    -H "$CT" -d "$(load_payload error-missing-type.json)")
  log_warn "POST (missing @type) → $status"
  pause

  log_info "400 – POST empty body"
  status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/product" \
    -H "$CT" -d "$(load_payload error-empty-body.json)")
  log_warn "POST (empty body) → $status"
  pause

  log_info "200 – GET with unknown field name (server tolerance)"
  status=$(curl -s -o /dev/null -w '%{http_code}' \
    "$BASE_URL/product?fields=nonExistentField")
  log_warn "GET fields=nonExistentField → $status"
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
  scenario_errors
  echo -e "\n${BOLD}${GREEN}✓ Done.${NC}"
fi
