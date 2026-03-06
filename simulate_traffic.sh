#!/usr/bin/env bash
# simulate_traffic.sh – TMF 637 Product Inventory traffic simulator
# Orchestrates scenario scripts from scenarios/ against a local TMF 637 server.
#
# Usage:
#   ./simulate_traffic.sh [OPTIONS] [SCENARIO...]
#   ./simulate_traffic.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/scenarios/crud.sh"
source "$SCRIPT_DIR/scenarios/queries.sh"
source "$SCRIPT_DIR/scenarios/errors.sh"
source "$SCRIPT_DIR/scenarios/events.sh"
source "$SCRIPT_DIR/scenarios/notify.sh"
source "$SCRIPT_DIR/scenarios/states.sh"
source "$SCRIPT_DIR/scenarios/burst.sh"

# Shared temp file for tracking created product IDs across all scenarios
IDS_FILE=$(mktemp)
trap 'rm -f "$IDS_FILE"' EXIT

# ─── CLI ───────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
TMF 637 Product Inventory – Traffic Simulator

Usage: $(basename "$0") [OPTIONS] [SCENARIO...]

Scenarios (default: all in order):
  crud      Create / retrieve / patch / delete lifecycle
  queries   List & query patterns (filters, sorting, field selection)
  errors    Error and edge-case traffic (4xx/5xx)
  events    Event subscription (hub) register & unregister
  notify    Notification listener endpoint calls
  states    State transition lifecycle (created→active→suspended→terminated)
  burst     Concurrent parallel request bursts

Options:
  --no-cleanup  Keep products created during this run (skip DELETE phase)
  --fast        Remove pauses between requests
  -h, --help    Show this help

Individual scenarios can also be run standalone, e.g.:
  ./scenarios/crud.sh --fast
  ./scenarios/burst.sh

EOF
}

main() {
  local no_cleanup=0
  local scenarios=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-cleanup) no_cleanup=1 ;;
      --fast)       export FAST=1 ;;
      -h|--help)    usage; exit 0 ;;
      crud|queries|errors|events|notify|states|burst) scenarios+=("$1") ;;
      *) echo "Unknown argument: $1"; usage; exit 1 ;;
    esac
    shift
  done

  [[ ${#scenarios[@]} -eq 0 ]] && scenarios=(crud queries errors events notify states burst)

  echo -e "${BOLD}TMF 637 Product Inventory – Traffic Simulator${NC}"
  echo -e "  Base URL : ${CYAN}$BASE_URL${NC}"
  echo -e "  Scenarios: ${YELLOW}${scenarios[*]}${NC}"
  echo -e "  Fast mode: ${FAST:-0}"

  for s in "${scenarios[@]}"; do
    case "$s" in
      crud)    scenario_crud ;;
      queries) scenario_queries ;;
      errors)  scenario_errors ;;
      events)  scenario_events ;;
      notify)  scenario_notify ;;
      states)  scenario_states ;;
      burst)   scenario_burst ;;
    esac
  done

  [[ "$no_cleanup" -eq 0 ]] && cleanup

  echo -e "\n${BOLD}${GREEN}✓ Done.${NC}"
}

main "$@"
