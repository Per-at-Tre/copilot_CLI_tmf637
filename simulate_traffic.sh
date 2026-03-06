#!/usr/bin/env bash
# TMF 637 Product Inventory Management – Traffic Simulator
# Simulates various API traffic patterns against a local TMF 637 server.
#
# Usage:
#   ./simulate_traffic.sh [OPTIONS] [SCENARIO...]
#   ./simulate_traffic.sh --help

set -euo pipefail

BASE_URL="http://localhost:8637/tmf-api/productInventoryManagement/v5"
CT="Content-Type: application/json"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# Temp file to persist created product IDs across subshells
IDS_FILE=$(mktemp)
trap 'rm -f "$IDS_FILE"' EXIT

# ─── Helpers ───────────────────────────────────────────────────────────────────

log_section() { echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${NC}" >&2; }
log_ok()      { echo -e "  ${GREEN}✓${NC}  $1" >&2; }
log_err()     { echo -e "  ${RED}✗${NC}  $1" >&2; }
log_warn()    { echo -e "  ${YELLOW}⚠${NC}  $1" >&2; }
log_info()    { echo -e "  ${YELLOW}→${NC}  $1" >&2; }

pause() { [[ "${FAST:-0}" == "1" ]] && return; sleep "${1:-0.3}"; }

# Make a request, print status, return the response body on stdout.
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
    # print error body to stderr so it doesn't pollute callers
    [[ -n "$body" ]] && echo "$body" | python3 -m json.tool 2>/dev/null >&2 || true
  fi

  printf '%s' "$body"   # caller can capture
  return 0
}

# POST a product, print nice status, store ID in IDS_FILE, echo ID to stdout.
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

# PATCH a product (silent status, no body capture needed in callers)
patch_product() {
  local label="$1" id="$2" payload="$3"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    "$BASE_URL/product/$id" -H "$CT" -d "$payload")
  if [[ "$status" =~ ^2 ]]; then
    log_ok "${label} → $status"
  else
    log_warn "${label} → $status"
  fi
}

# ─── Scenarios ─────────────────────────────────────────────────────────────────

scenario_crud_lifecycle() {
  log_section "1. Basic CRUD Lifecycle"

  # --- CREATE ---
  local id1
  id1=$(create_product "Create spec-based product (VoIP)" \
    '{
      "@type": "Product",
      "name": "Voice Over IP Basic – Louise",
      "description": "Spec-based VoIP product instance",
      "isBundle": false,
      "isCustomerVisible": false,
      "status": "created",
      "productSpecification": {
        "@type": "ProductSpecificationRef",
        "@referredType": "ProductSpecification",
        "id": "PS-101",
        "href": "http://host/productCatalogManagement/v5/productSpecification/PS-101",
        "version": "1"
      },
      "productCharacteristic": [
        { "@type": "BooleanCharacteristic", "id": "Char1", "name": "FixedIP",
          "valueType": "boolean", "value": false },
        { "@type": "ObjectCharacteristic", "id": "Char5", "name": "FiberSpeed",
          "valueType": "object", "value": { "@type": "Speed", "volume": 90, "unit": "Mbps" } }
      ],
      "relatedParty": [{
        "@type": "RelatedPartyOrPartyRole", "role": "User",
        "partyOrPartyRole": {
          "@type": "PartyRef", "@referredType": "Individual",
          "id": "45hj-999", "name": "Louise",
          "href": "http://host/partyManagement/v5/individual/45hj-999"
        }
      }]
    }')
  pause

  local id2
  id2=$(create_product "Create offering-based product (Fiber + pricing)" \
    '{
      "@type": "Product",
      "name": "Fiber 1Gbps – Jean",
      "description": "Offering-based fiber product with recurring price",
      "isBundle": false,
      "isCustomerVisible": true,
      "status": "created",
      "productOffering": {
        "@type": "ProductOfferingRef", "@referredType": "ProductOffering",
        "id": "PO-101-1", "name": "Voice Over IP Basic",
        "href": "http://host/productCatalogManagement/v5/productOffering/PO-101-1"
      },
      "productPrice": [{
        "@type": "ProductPrice", "priceType": "recurring",
        "recurringChargePeriod": "month",
        "price": {
          "@type": "Price",
          "taxIncludedAmount": { "unit": "EUR", "value": 29.99 },
          "taxRate": 15
        },
        "productOfferingPrice": {
          "@type": "ProductOfferingPriceRef", "@referredType": "ProductOfferingPrice",
          "id": "POP1", "name": "Fiber recurring fee",
          "href": "http://host/productCatalogManagement/v5/productOfferingPrice/POP1"
        }
      }],
      "productTerm": [{
        "@type": "ProductTerm", "name": "12 month commitment",
        "description": "Fiber standard commitment",
        "duration": { "amount": 12, "units": "month" },
        "validFor": {
          "startDateTime": "2024-01-01T00:00:00.000Z",
          "endDateTime":   "2025-01-01T00:00:00.000Z"
        }
      }],
      "relatedParty": [{
        "@type": "RelatedPartyOrPartyRole", "role": "owner",
        "partyOrPartyRole": {
          "@type": "PartyRef", "@referredType": "Individual",
          "id": "45hj-8888", "name": "Jean",
          "href": "http://host/partyManagement/v5/individual/45hj-8888"
        }
      }]
    }')
  pause

  local id3
  id3=$(create_product "Create bundle product (Triple Play)" \
    '{
      "@type": "Product",
      "name": "Triple Play Bundle",
      "description": "Internet + TV + Phone bundle",
      "isBundle": true,
      "isCustomerVisible": true,
      "status": "active",
      "productCharacteristic": [
        { "@type": "StringCharacteristic", "name": "BundleTier", "valueType": "string", "value": "Premium" }
      ]
    }')
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
      '{"@type": "Product", "status": "active"}'
    pause

    patch_product "Patch FiberSpeed → 200 Mbps" "$id1" \
      '{
        "@type": "Product",
        "productCharacteristic": [
          { "@type": "ObjectCharacteristic", "id": "Char5", "name": "FiberSpeed",
            "valueType": "object", "value": { "@type": "Speed", "volume": 200, "unit": "Mbps" } }
        ]
      }'
    pause

    patch_product "Patch relatedParty name" "$id1" \
      '{
        "@type": "Product",
        "relatedParty": [{
          "@type": "RelatedPartyOrPartyRole", "role": "User",
          "partyOrPartyRole": {
            "@type": "PartyRef", "@referredType": "Individual",
            "id": "45hj-999", "name": "Louise M.",
            "href": "http://host/partyManagement/v5/individual/45hj-999"
          }
        }]
      }'
    pause
  fi

  # --- DELETE (immediately, not during cleanup) ---
  if [[ -n "$id3" ]]; then
    log_info "Delete bundle product $id3"
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE_URL/product/$id3")
    if [[ "$status" =~ ^2 ]]; then
      log_ok "DELETE $id3 → $status"
      # Remove from IDS_FILE so cleanup skips it
      sed -i.bak "/$id3/d" "$IDS_FILE" && rm -f "${IDS_FILE}.bak"
    else
      log_warn "DELETE $id3 → $status"
    fi
    pause
  fi
}

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
    local count
    count=$(curl -s "$url" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(f'{len(d)} item(s)')" 2>/dev/null || echo "?")
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' "$url")
    if [[ "$status" =~ ^2 ]]; then
      log_ok "GET → $status  ($count)"
    else
      log_warn "GET → $status"
    fi
    pause
  done
}

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
        -H "$CT" -d '{"@type":"Product","status":"active"}')
    else
      status=$(curl -s -o /dev/null -w '%{http_code}' -X "$method" "$url")
    fi
    log_warn "$method $url → $status"
    pause
  done

  # Bad payloads (expect 400)
  log_info "400 – POST missing @type field"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/product" \
    -H "$CT" -d '{"name": "Missing type"}')
  log_warn "POST (missing @type) → $status"
  pause

  log_info "400 – POST empty body"
  status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/product" \
    -H "$CT" -d '{}')
  log_warn "POST (empty body) → $status"
  pause

  log_info "200 – GET with unknown field name (server tolerance)"
  status=$(curl -s -o /dev/null -w '%{http_code}' \
    "$BASE_URL/product?fields=nonExistentField")
  log_warn "GET fields=nonExistentField → $status"
  pause
}

scenario_event_subscriptions() {
  log_section "4. Event Subscription (Hub) Lifecycle"

  log_info "Register hub for ProductCreateEvent + ProductStateChangeEvent"
  local hub_body hub_status hub_id
  local hub_resp
  hub_resp=$(curl -s -w '\n__STATUS__%{http_code}' \
    -X POST "$BASE_URL/hub" -H "$CT" \
    -d '{
      "@type": "Hub",
      "callback": "http://localhost:9000/listener",
      "query": "eventType=ProductCreateEvent,ProductStateChangeEvent"
    }')
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
    if [[ "$del_status" =~ ^2 ]]; then
      log_ok "Hub deleted → $del_status"
    else
      log_warn "Hub delete → $del_status"
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

scenario_notifications() {
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
      -d "{
        \"@type\": \"$etype\",
        \"eventId\": \"sim-evt-$(date +%s)\",
        \"eventTime\": \"$now\",
        \"eventType\": \"$etype\",
        \"event\": {
          \"product\": {
            \"@type\": \"Product\",
            \"id\": \"sim-product-001\",
            \"name\": \"Simulated Product\",
            \"status\": \"active\"
          }
        }
      }")
    if [[ "$status" =~ ^2 ]]; then
      log_ok "POST /listener/$path → $status"
    else
      log_warn "POST /listener/$path → $status  (server may not require listener impl)"
    fi
    pause
  done
}

scenario_state_transitions() {
  log_section "6. Product State Lifecycle Transitions"

  local id
  id=$(create_product "Create product for state transitions" \
    '{
      "@type": "Product",
      "name": "State Transition Test Product",
      "status": "created",
      "isBundle": false,
      "isCustomerVisible": true
    }')
  pause

  if [[ -n "$id" ]]; then
    for state in active suspended terminated; do
      patch_product "State → $state" "$id" \
        "{\"@type\": \"Product\", \"status\": \"$state\"}"
      pause
    done
  else
    log_err "No product created, skipping state transitions"
  fi
}

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

  # Use the first available product ID for point reads
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

  log_info "Mixed burst: reads + patches + creates (5 each, concurrent)"
  pids=()
  # reads
  for i in $(seq 1 5); do
    { curl -s -o /dev/null -w "  read-$i → %{http_code}\n" \
        "$BASE_URL/product?limit=3&offset=$i"; } &
    pids+=($!)
  done
  # creates
  for i in $(seq 1 5); do
    { curl -s -o /dev/null -w "  create-$i → %{http_code}\n" \
        -X POST "$BASE_URL/product" -H "$CT" \
        -d "{\"@type\":\"Product\",\"name\":\"Burst Product $i\",\"status\":\"created\",\"isBundle\":false,\"isCustomerVisible\":false}"; } &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
  log_ok "Mixed burst complete"
  pause
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
    if [[ "$status" =~ ^2 ]]; then
      log_ok "Deleted $id → $status"
    else
      log_warn "Could not delete $id → $status"
    fi
  done < "$IDS_FILE"
}

# ─── Entry point ───────────────────────────────────────────────────────────────

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

Examples:
  $(basename "$0")                   # run all scenarios
  $(basename "$0") crud queries      # run only crud and queries
  $(basename "$0") burst --fast      # burst with no delays
  $(basename "$0") --no-cleanup crud # create products, keep them
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
      crud)    scenario_crud_lifecycle ;;
      queries) scenario_queries ;;
      errors)  scenario_errors ;;
      events)  scenario_event_subscriptions ;;
      notify)  scenario_notifications ;;
      states)  scenario_state_transitions ;;
      burst)   scenario_burst ;;
    esac
  done

  [[ "$no_cleanup" -eq 0 ]] && cleanup

  echo -e "\n${BOLD}${GREEN}✓ Done.${NC}"
}

main "$@"
