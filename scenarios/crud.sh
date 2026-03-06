#!/usr/bin/env bash
# scenarios/crud.sh – Basic CRUD lifecycle: create / retrieve / patch / delete
# Runnable standalone: ./scenarios/crud.sh [--fast] [--no-cleanup]

_SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCENARIO_DIR/../lib/common.sh"

scenario_crud() {
  log_section "1. Basic CRUD Lifecycle"

  # --- CREATE ---
  local id1
  id1=$(create_product "Create spec-based product (VoIP)" \
    "$(load_payload product-create-voip.json)")
  pause

  local id2
  id2=$(create_product "Create offering-based product (Fiber + pricing)" \
    "$(load_payload product-create-fiber.json)")
  pause

  local id3
  id3=$(create_product "Create bundle product (Triple Play)" \
    "$(load_payload product-create-bundle.json)")
  pause

  # --- RETRIEVE ---
  if [[ -n "$id1" ]]; then
    log_info "Retrieve by ID: $id1"
    req "Retrieve" GET "$BASE_URL/product/$id1" > /dev/null
    pause

    log_info "Retrieve with field selection: $id1"
    req "Retrieve (fields=id,name,status)" GET \
      "$BASE_URL/product/$id1?fields=id,name,status" > /dev/null
    pause
  fi

  # --- PATCH ---
  if [[ -n "$id1" ]]; then
    patch_product "Patch status → active" "$id1" \
      "$(load_payload product-patch-status-active.json)"
    pause

    patch_product "Patch FiberSpeed → 200 Mbps" "$id1" \
      "$(load_payload product-patch-fiberspeed.json)"
    pause

    patch_product "Patch relatedParty name" "$id1" \
      "$(load_payload product-patch-relatedparty.json)"
    pause
  fi

  # --- DELETE (immediately, not deferred to cleanup) ---
  if [[ -n "$id3" ]]; then
    log_info "Delete bundle product $id3"
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE_URL/product/$id3")
    if [[ "$status" =~ ^2 ]]; then
      log_ok "DELETE $id3 → $status"
      sed -i.bak "/$id3/d" "$IDS_FILE" && rm -f "${IDS_FILE}.bak"
    else
      log_warn "DELETE $id3 → $status"
    fi
    pause
  fi
}

# ─── Standalone execution ──────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  no_cleanup=0
  for arg in "$@"; do
    case "$arg" in
      --fast)       export FAST=1 ;;
      --no-cleanup) no_cleanup=1 ;;
      -h|--help) echo "Usage: $(basename "$0") [--fast] [--no-cleanup]"; exit 0 ;;
    esac
  done
  IDS_FILE=$(mktemp); trap 'rm -f "$IDS_FILE"' EXIT
  scenario_crud
  [[ "$no_cleanup" -eq 0 ]] && cleanup
  echo -e "\n${BOLD}${GREEN}✓ Done.${NC}"
fi
