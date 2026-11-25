# Morgana inventory lookup and capture API

Recovered from `feature/nested-inventory-api` and integrated with the current
bearer API locally; deployment and live migrations remain pending. Existing
tasks (`Item`), physical inventory (`InventoryItem`), shops,
locations and reservations retain their IDs. No example below is actual stock.

## Minimal structure

A location has a name, owner and optional parent location. A node can hold stock
and children at the same time. There is no fixed row/bin taxonomy or schema depth
limit. Examples: Electronics bins → second row → third bin; Electronics Drawers
→ bottom left → top tray → right side. Sibling names are unique, including roots;
comparison follows existing MySQL case/accent-insensitive collation. Names can
repeat under different parents. Supply exact names or IDs, never guess that
"electronic bins" and "Electronics bins" are the same location. API names must
be nonblank, unpadded strings up to 255 characters. Paths are derived from stable
IDs, not stored strings; rename through the existing location form retains IDs.
Reparenting/owner changes are deliberately rejected after creation. Location
and descendant stock cannot be cascaded away: children and stock restrict deletion.

Existing physical inventory is one name/location quantity row, not the task table.
The same material can have rows at multiple locations. Counts apply to the actual
location only, not also its ancestors. Existing required shop and unit semantics
are preserved. New captures require an explicit unit (normally `each`); omitted
quantity records presence with an unknown count. Existing zeroes are not reclassified.
The legacy web/model default stays zero for backward compatibility. Measured units
can be declared but are never converted. Aliases are optional
per-stock-row names for lookup; there is no separate master parts catalog.

## Authentication

Morgana calls `https://mywayfinder.app` over HTTP with the existing
`Authorization: Bearer TOKEN` credential described in [items-api.md](items-api.md).
Tasks, locations and inventory inherit the same authentication implementation.
Only a verified bearer credential bypasses CSRF; no cookie or browser login is
needed, and bearer responses do not issue a session or CSRF token. The server
continues to store only the token digest and its existing owner's ID. No token
is generated or rotated for this integration. Do not put credentials in URLs,
request bodies, prompts, or this repository.

Existing signed `auth_v1` browser sessions still work with their existing CSRF
rules: retain cookies, GET an API route for `X-CSRF-Token`, and send that header
on mutations. An invalid explicit Authorization header fails with 401 even if
a valid cookie is present. All IDs and queries are scoped to the authenticated
owner; foreign-owned IDs return 404. Responses use `Cache-Control: no-store`.
The existing API audit middleware records these routes, including failed access,
without recording raw tokens, query strings, request bodies, or cookies.

The private local client also supports these routes:

```sh
bin/wayfinder-api get '/api/inventory_items?q=timers&include_totals=1'
bin/wayfinder-api get '/api/inventory_items?include_choices=1'
bin/wayfinder-api post /api/locations location.json
bin/wayfinder-api put /api/inventory_items inventory.json
```

The JSON file examples below are the bodies for `location.json` and
`inventory.json`. An HTTP client can send the same requests directly; no local
LLM is needed. Morgana must paginate results, retain full location paths, and
reconcile a 409 stale-count response before making a new recount.

## Routes

| Method | Route | Behavior |
| --- | --- | --- |
| GET | `/api/locations` | List locations with full ancestry |
| GET | `/api/locations/:id` | Read one location and ancestry |
| POST | `/api/locations` | Atomically create/reuse a path |
| GET | `/api/inventory_items` | List/search stock with counts and paths |
| GET | `/api/inventory_items/:id` | Read one stock row |
| PUT | `/api/inventory_items` | Create stock or explicitly set a row's count |

Lists return `next_after_id`; use `limit=1..100` (default 50) and `after_id`
(default 0) until the cursor is null. Locations accept `name` and `parent_id`;
stock accepts `name`, `q` (literal substring of name or aliases), `location_id`
and `include_choices=1` (adds visible owned `shops: [{id,name}]`).
Use `include_totals=1` for totals across all filtered matches, independent of the
current page, grouped by canonical name and declared unit. `known_quantity` is
only the sum of known counts (null if no counts are known); `known_rows`,
`unknown_rows` and `complete` disclose unknown portions. Never treat a partial
known sum as an exhaustive total, and never add different units together. `name` is exact
under the database collation. A blank parent/location filter selects roots or
unlocated stock. Location filtering is exact, not recursive. Omitting filters
returns all owned rows, including hidden locations and recorded zero quantities.
A search can return multiple matches; the assistant must retain their distinct
locations and ask about ambiguity instead of merging or selecting the first.

Create a path relative to an existing root ID:

```http
POST /api/locations
Content-Type: application/json
Authorization: Bearer <existing private token>

{"location":{"root_id":10,"path":["second row","third bin"]}}
```

Without `root_id`, `path` begins at the root, for example
`["Electronics Drawers","bottom left","top tray","right side"]`. All segments
are validated before any write; the operation is transactional and serializes
same-owner path creation. A sibling unique database index protects other writers.
Retries reuse IDs. New paths return 201; fully reused paths return 200:

```json
{"location":{"id":12,"name":"third bin","parent_id":11,"hidden":false,"path":[{"id":10,"name":"Electronics bins"},{"id":11,"name":"second row"},{"id":12,"name":"third bin"}]},"created_ids":[11,12]}
```

Capture stock at that leaf (all IDs illustrative):

```http
PUT /api/inventory_items
Content-Type: application/json
Authorization: Bearer <existing private token>

{"inventory_item":{"name":"DC-DC buck converters","aliases":["step down modules"],"location_id":12,"shop_id":4,"unit":"each","qty_have":"8"}}
```

Response is 201 for creation, 200 for reuse/recount:

```json
{"inventory_item":{"id":30,"name":"DC-DC buck converters","unit":"each","shop_id":4,"location_id":12,"aliases":["step down modules"],"qty_have":"8.0","quantity_status":"positive","location":{"id":12,"name":"third bin","parent_id":11,"hidden":false,"path":[{"id":10,"name":"Electronics bins"},{"id":11,"name":"second row"},{"id":12,"name":"third bin"}]}},"quantity_operation":"set"}
```

`qty_have` is an explicit decimal string from `0` to `99999999.99` with at most
two decimal places. Required: name, location_id (ID or explicit null), shop_id and unit.
`qty_have` is optional and may be a decimal string or explicit null. Unknown fields and malformed/coerced values return 422. Omitted
aliases preserve existing aliases; supplied aliases replace that row's alias list.
Existing shop/unit must match or the request returns 409 without changing stock.
No relocation, rename, deletion, increment, transfer or reservation changes are
performed. Legacy unlocated duplicate name rows return 409 unless an explicit
owned `id` disambiguates the matching name/location row.

To change an existing count, send the last observed count as `expected_qty_have`:

```json
{"inventory_item":{"id":30,"name":"DC-DC buck converters","location_id":12,"shop_id":4,"unit":"each","qty_have":"6","expected_qty_have":"8"}}
```

The row is locked and the comparison checked atomically. A changed count or known/unknown transition without
a matching expectation returns 409 `stale_count` plus the current row; read again
and reconcile. A repeat of the desired count is a safe no-op even if the old
expectation is stale. This is a count comparison, not an event ledger: intervening
changes that return to the same count are indistinguishable. `qty_delta` is
rejected. "I found three more" requires a fresh read, explicit addition by the
assistant, and a set with the observed expectation; retry conflicts require
reconciliation. Do not retry an old recount blindly after subsequent activity.

## Simple assistant answers

`GET /api/inventory_items?q=buck` or `?q=step%20down%20modules` retrieves canonical
names, aliases, quantities and full paths. Build a short answer from these fields:
"Electronics bins, second row, third bin — 8 recorded." Use full paths to separate
multiple matches and paginate to completion before making an exhaustive claim.
A zero count means "recorded count is zero." An empty result means "I don't have
a matching inventory record," not physical absence. Responses include
`quantity_status: "positive"`, `"zero"` or `"unknown"` and `qty_have` is a decimal
string or JSON null. Legacy negative rows, if any, are labeled `"negative"` rather
than positive; this API does not accept negative writes.

Presence and count operations are deliberately distinct:

| Request quantity | New record | Existing record |
| --- | --- | --- |
| Omitted | Store null, `quantity_operation: "record_presence"` | Preserve current count, `"preserve"` |
| Decimal string, including `"0"` | Store known count, `"set"` | Set known count, `"set"`; compare expectation for changes |
| Explicit JSON null | Store unknown count | Clear known count to unknown, `"clear_to_unknown"`; compare expectation for changes |

For example, record an item's location without claiming a quantity:

```json
{"inventory_item":{"name":"555 timers","location_id":12,"shop_id":4,"unit":"each"}}
```

Then set a known count only if the previous count is still unknown:

```json
{"inventory_item":{"name":"555 timers","location_id":12,"shop_id":4,"unit":"each","qty_have":"8","expected_qty_have":null}}
```

Explicitly clear a known count only if it is still the last observed count:

```json
{"inventory_item":{"name":"555 timers","location_id":12,"shop_id":4,"unit":"each","qty_have":null,"expected_qty_have":"8"}}
```

An omitted expectation differs from `expected_qty_have: null`. Unknown-to-known
changes require the explicit null expectation; known-to-unknown changes require
the observed numeric expectation. Repeating the resulting state is a no-op.
Omitting `qty_have` on an existing row preserves positive, zero and unknown counts,
including when aliases are updated. Missing quantity does not increment stock.

For unknown presence, answer "555 timers are recorded in Electronics Shelves,
5th shelf down, middle bin; quantity unknown." For known zero, say "the recorded
count is zero," without asserting physical absence. Historical zeroes remain zero.
No illustrative example has been inserted into live inventory.

The normal inventory UI shows unknown quantities and retains its zero filter.
Blank edit fields preserve the count; an explicit "Quantity unknown" checkbox
clears it. Shopping purchases and reservation consumption retain an unknown
starting balance instead of fabricating one. Task readiness and shopping advice
sum same-name, same-unit stock across actual locations; any unknown portion is
shown as needing a recount, not a numeric shortage or a confirmed ready state.

## Existing shop prerequisite

Every stock row still requires an owned shop because existing inventory validation
and shopping/reservation workflows depend on it. `GET /api/inventory_items?include_choices=1`
returns existing visible owned shop IDs/names, even if inventory is empty. Select
the owner-approved existing shop and send its ID with every capture/recount; the
API does not choose the first vendor or invent one. A mismatched existing shop
returns 409 and a foreign-owned shop returns 404. If none is suitable, Rick must
choose/create a shop using the existing Shops UI before capture. No default
vendor, credentials or extra access has been configured as part of this change.

## Migration and validation

Migration `20261027000000` adds parent_id and a generated non-null parent_key for
root-safe sibling uniqueness, a restrictive parent foreign key, and optional
serialized aliases on inventory. Existing rows remain roots; nothing is replaced
or backfilled into guessed paths. Rollback refuses populated hierarchies.
Migration `20261027010000` makes qty_have
nullable without updating existing values or changing the legacy zero default.
Its rollback refuses unknown counts rather than converting them to zero. MySQL 8
was used for validation; schema dump is generated from a disposable test database.
These migrations have not been run on live Wayfinder by this change.

After merging the PR, run `RAILS_ENV=production bundle exec rails db:migrate`
from the existing production checkout before restarting Wayfinder. The existing
`update.sh` rebuilds assets and restarts the service but does not run migrations.
Both pending `20261027...` migrations must run even though the latest previously
applied migration is dated November 17. Keep the existing bearer configuration.
Rick will merge and deploy this change for live testing.

From this checkout run `bin/test_items_api wayfinder_api_test_NAME` against a
separately provisioned disposable database only. The runner uses the existing
MySQL account and never selects development/production. Initial test setup:
`RAILS_ENV=test DATABASE_URL=mysql2://pixie@aidb/wayfinder_api_test_NAME bundle exec rails db:schema:load`.
The runner executes the complete ordinary Rails suite. Browser/Selenium system
scaffolding is separate. No live migrations or live API calls are needed to test.

Scope tradeoffs: no new immutable adjustment ledger, server-side natural-language
classifier, transfer endpoint, unit conversion, alias management UI, location move
API or new credential. Existing shopping now
matches the selected location before updating stock, preserving separate quantities
instead of silently taking the first same-name row. Count consumption/reservations
continue to use the existing task completion services.

The dated, database-guarded migration preservation check is retained at
[scripts/tmp/verify_nested_inventory_migration_20261027.rb](../scripts/tmp/verify_nested_inventory_migration_20261027.rb).
It only runs against `wayfinder_api_test_nested_20261027`, refuses existing child
locations and unknown stock, exercises both migrations with synthetic legacy
positive/zero rows, verifies both rollback guards, and removes only
those synthetic rows. It is a test tool, never a production migration command.
