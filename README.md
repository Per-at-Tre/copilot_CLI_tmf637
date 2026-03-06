# TMF 637 Product Inventory – Traffic Simulator

Curl-based bash scripts for simulating various traffic patterns against a [TMF 637 Product Inventory Management API v5](https://www.tmforum.org/resources/how-to-guide/tmf637-product-inventory-management-api-user-guide-v5-0/).

Tested against `http://localhost:8637/tmf-api/productInventoryManagement/v5`.

---

## Structure

```
simulate_traffic.sh       # main entry point – runs all or selected scenarios
lib/
  common.sh               # shared helpers: logging, HTTP, payload loading, cleanup
scenarios/
  crud.sh                 # create / retrieve / patch / delete lifecycle
  queries.sh              # list, filter, sort, pagination
  errors.sh               # edge-case traffic (4xx / 5xx)
  events.sh               # hub event subscription register & unregister
  notify.sh               # notification listener endpoint calls
  states.sh               # full state lifecycle transitions
  burst.sh                # concurrent parallel request bursts
payloads/
  *.json                  # static request bodies
  *.tmpl.json             # template bodies with __PLACEHOLDER__ tokens
```

## Prerequisites

- `bash` 4+
- `curl`
- `python3` (used for JSON parsing)
- A running TMF 637 server (default: `http://localhost:8637`)

## Usage

### Run all scenarios

```bash
./simulate_traffic.sh
```

### Run specific scenarios

```bash
./simulate_traffic.sh crud queries
./simulate_traffic.sh burst --fast
```

### Run a scenario standalone

Each script in `scenarios/` is independently executable:

```bash
./scenarios/crud.sh
./scenarios/states.sh --fast
./scenarios/burst.sh --no-cleanup
```

### Options

| Flag | Description |
|---|---|
| `--fast` | Remove the 0.3 s pause between requests |
| `--no-cleanup` | Keep products created during the run (skip DELETE phase) |
| `-h`, `--help` | Show usage |

## Scenarios

| Name | Script | What it does |
|---|---|---|
| `crud` | `scenarios/crud.sh` | Creates a spec-based product, an offering+pricing product, and a bundle; retrieves by ID; patches status, a characteristic, and a relatedParty; deletes inline |
| `queries` | `scenarios/queries.sh` | 10 GET variations: list all, limit, pagination, field selection, status/isBundle/isCustomerVisible filters, ASC/DESC sorting |
| `errors` | `scenarios/errors.sh` | Non-existent resource GETs/PATCHes/DELETEs, missing `@type` POST, empty-body POST, unknown field name |
| `events` | `scenarios/events.sh` | Registers a hub subscription, deletes it, then attempts to delete a non-existent hub |
| `notify` | `scenarios/notify.sh` | POSTs to all five listener endpoints: `productCreateEvent`, `productDeleteEvent`, `productStateChangeEvent`, `productAttributeValueChangeEvent`, `productProductBatchEvent` |
| `states` | `scenarios/states.sh` | Creates a product and walks it through `created → active → suspended → terminated` |
| `burst` | `scenarios/burst.sh` | 10 concurrent paginated GETs, 8 concurrent point reads, then a mixed burst of 5 reads + 5 creates in parallel |

## Payloads

Request bodies live in `payloads/` and are kept separate from the scripts:

| File | Used by |
|---|---|
| `product-create-voip.json` | `crud` – spec-based VoIP product |
| `product-create-fiber.json` | `crud` – offering-based fiber product with pricing |
| `product-create-bundle.json` | `crud` – Triple Play bundle |
| `product-create-state-test.json` | `states` – product for state transitions |
| `product-patch-status-active.json` | `crud`, `errors` – set status to `active` |
| `product-patch-fiberspeed.json` | `crud` – update FiberSpeed characteristic |
| `product-patch-relatedparty.json` | `crud` – update relatedParty name |
| `hub-subscribe.json` | `events` – hub registration |
| `error-missing-type.json` | `errors` – missing `@type` field (triggers 400) |
| `error-empty-body.json` | `errors` – empty body (triggers 400) |
| `product-patch-status.tmpl.json` | `states` – template: `__STATUS__` |
| `product-create-burst.tmpl.json` | `burst` – template: `__NAME__` |
| `notification-event.tmpl.json` | `notify` – template: `__EVENT_TYPE__`, `__EVENT_ID__`, `__EVENT_TIME__` |

Template files (`.tmpl.json`) have `__PLACEHOLDER__` tokens substituted at runtime via the `render_payload` helper in `lib/common.sh`.

## Cleanup

Products created during a run are tracked in a temp file and deleted automatically at the end. Pass `--no-cleanup` to skip this, for example to inspect created resources manually:

```bash
./simulate_traffic.sh --no-cleanup crud states
```
