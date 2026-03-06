#!/usr/bin/env bash
# scenarios/queries.sh – List & query patterns (filters, pagination, sorting)
# Runnable standalone: ./scenarios/queries.sh [--fast]

_SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCENARIO_DIR/../lib/common.sh"

scenario_queries() {
  log_section "2. List & Query Patterns"

  declare -a queries=(
    "List all products|$BASE_URL/product"
    "Limit to 2 results|$BASE_URL/product?limit=2"
    "Pagination (offset=1,limit=2)|$BASE_URL/product?offset=1&limit=2"
    "Field selection (id,name,status)|$BASE_URL/product?fields=id,name,status"
    "Filter status=active|$BASE_URL/product?status=active"
    "Filter status=created|$BASE_URL/product?status=created"
    "Filter isBundle=true|$BASE_URL/product?isBundle=true"
    "Filter isCustomerVisible=true|$BASE_URL/product?isCustomerVisible=true"
    "Sort by name ASC|$BASE_URL/product?sort=name"
    "Sort by creationDate DESC|$BASE_URL/product?sort=-creationDate"
  )

  for entry in "${queries[@]}"; do
    local label="${entry%%|*}" url="${entry##*|}"
    log_info "$label"
    local count status
    count=$(curl -s "$url" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(f'{len(d)} item(s)')" 2>/dev/null || echo "?")
    status=$(curl -s -o /dev/null -w '%{http_code}' "$url")
    if [[ "$status" =~ ^2 ]]; then log_ok "GET → $status  ($count)"
    else                           log_warn "GET → $status"
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
  scenario_queries
  echo -e "\n${BOLD}${GREEN}✓ Done.${NC}"
fi
