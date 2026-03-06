#!/usr/bin/env bash
# scenarios/states.sh – Full product state lifecycle transitions
# Runnable standalone: ./scenarios/states.sh [--fast] [--no-cleanup]

_SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCENARIO_DIR/../lib/common.sh"

scenario_states() {
  log_section "6. Product State Lifecycle Transitions"

  local id
  id=$(create_product "Create product for state transitions" \
    "$(load_payload product-create-state-test.json)")
  pause

  if [[ -n "$id" ]]; then
    for state in active suspended terminated; do
      patch_product "State → $state" "$id" \
        "$(render_payload product-patch-status.tmpl.json STATUS "$state")"
      pause
    done
  else
    log_err "No product created, skipping state transitions"
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
  scenario_states
  [[ "$no_cleanup" -eq 0 ]] && cleanup
  echo -e "\n${BOLD}${GREEN}✓ Done.${NC}"
fi
