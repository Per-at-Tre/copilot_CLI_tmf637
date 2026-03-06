#!/usr/bin/env bash
# scenarios/burst.sh – Concurrent parallel request bursts
# Runnable standalone: ./scenarios/burst.sh [--fast]

_SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCENARIO_DIR/../lib/common.sh"

scenario_burst() {
  log_section "7. Burst / Concurrent Traffic"

  log_info "10 concurrent GET /product?limit=5 (different offsets)"
  local pids=()
  for i in $(seq 0 9); do
    { curl -s -o /dev/null -w "  req-$((i+1)) offset=$i → %{http_code}\n" \
        "$BASE_URL/product?limit=5&offset=$i"; } &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
  log_ok "Concurrent GET burst complete"
  pause

  local first_id
  first_id=$(curl -s "$BASE_URL/product?limit=1" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" \
    2>/dev/null || true)

  if [[ -n "$first_id" ]]; then
    log_info "8 concurrent GET /product/$first_id"
    pids=()
    for i in $(seq 1 8); do
      { curl -s -o /dev/null -w "  req-$i → %{http_code}\n" \
          "$BASE_URL/product/$first_id"; } &
      pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    log_ok "Concurrent point-read burst complete"
  fi
  pause

  log_info "Mixed burst: reads + creates (5 each, concurrent)"
  pids=()
  for i in $(seq 1 5); do
    { curl -s -o /dev/null -w "  read-$i → %{http_code}\n" \
        "$BASE_URL/product?limit=3&offset=$i"; } &
    pids+=($!)
  done
  for i in $(seq 1 5); do
    { curl -s -o /dev/null -w "  create-$i → %{http_code}\n" \
        -X POST "$BASE_URL/product" -H "$CT" \
        -d "$(render_payload product-create-burst.tmpl.json NAME "Burst Product $i")"; } &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
  log_ok "Mixed burst complete"
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
  scenario_burst
  echo -e "\n${BOLD}${GREEN}✓ Done.${NC}"
fi
