# Inventory lookup and capture API

Implemented locally for review; deployment and the migration require separate
approval. Existing tasks (`Item`), physical inventory (`InventoryItem`), shops,
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
are preserved. New captures require explicit quantity and unit (normally `each`);
measured units can be declared but are never converted. Aliases are optional
per-stock-row names for lookup; there is no separate master parts catalog.

## Authentication

Same signed `auth_v1` session and CSRF conventions as [items-api.md](items-api.md).
No bearer token, query-key authentication, CORS exemption, credentials or users
are added. Authenticate with an existing account over HTTPS, retain cookies,
GET a route for `X-CSRF-Token`, and send it on mutations with JSON Content-Type.
Responses are `Cache-Control: no-store`; revoked sessions fail closed with 401.
All IDs and queries are scoped to the current user; foreign-owned IDs return 404.
An external assistant needs an approved way to use the existing session and CSRF
flow. Enabling alternative server-to-server authentication remains a decision
for Rick; this change does not enable it.

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
and `include_choices=1` (adds visible owned `shops: [{id,name}]`). `name` is exact
under the database collation. A blank parent/location filter selects roots or
unlocated stock. Location filtering is exact, not recursive. Omitting filters
returns all owned rows, including hidden locations and recorded zero quantities.
A search can return multiple matches; the assistant must retain their distinct
locations and ask about ambiguity instead of merging or selecting the first.

Create a path relative to an existing root ID:

```http
POST /api/locations
Content-Type: application/json
X-CSRF-Token: <token from authenticated GET>

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
X-CSRF-Token: <token>

{"inventory_item":{"name":"DC-DC buck converters","aliases":["step down modules"],"location_id":12,"shop_id":4,"unit":"each","qty_have":"8"}}
```

Response is 201 for creation, 200 for reuse/recount:

```json
{"inventory_item":{"id":30,"name":"DC-DC buck converters","unit":"each","shop_id":4,"location_id":12,"aliases":["step down modules"],"qty_have":"8.0","location":{"id":12,"name":"third bin","parent_id":11,"hidden":false,"path":[{"id":10,"name":"Electronics bins"},{"id":11,"name":"second row"},{"id":12,"name":"third bin"}]}},"quantity_operation":"set"}
```

`qty_have` is an explicit decimal string from `0` to `99999999.99` with at most
two decimal places. Required: name, location_id (ID or explicit null), shop_id,
unit, qty_have. Unknown fields and malformed/coerced values return 422. Omitted
aliases preserve existing aliases; supplied aliases replace that row's alias list.
Existing shop/unit must match or the request returns 409 without changing stock.
No relocation, rename, deletion, increment, transfer or reservation changes are
performed. Legacy unlocated duplicate name rows return 409 unless an explicit
owned `id` disambiguates the matching name/location row.

To change an existing count, send the last observed count as `expected_qty_have`:

```json
{"inventory_item":{"id":30,"name":"DC-DC buck converters","location_id":12,"shop_id":4,"unit":"each","qty_have":"6","expected_qty_have":"8"}}
```

The row is locked and the comparison checked atomically. A changed count without
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
a matching inventory record," not physical absence. This existing schema cannot
represent unknown quantity (`qty_have` is NOT NULL, default zero); the API refuses
missing counts instead of silently recording unknown as zero. Historical zero
rows cannot be reinterpreted as verified physical absence. No illustrative example
has been inserted into live inventory.

## Migration and validation

Migration `20261027000000` adds parent_id and a generated non-null parent_key for
root-safe sibling uniqueness, a restrictive parent foreign key, and optional
serialized aliases on inventory. Existing rows remain roots; nothing is replaced
or backfilled into guessed paths. Rollback refuses populated hierarchies. MySQL 8
was used for validation; schema dump is generated from a disposable test database.
Approval is still required to deploy/run this migration on live Wayfinder.

From this checkout run `bin/test_items_api wayfinder_api_test_NAME` against a
separately provisioned disposable database only. The runner uses the existing
MySQL account and never selects development/production. Initial test setup:
`RAILS_ENV=test DATABASE_URL=mysql2://pixie@aidb/wayfinder_api_test_NAME bundle exec rails db:schema:load`.
The runner executes the complete ordinary Rails suite. Browser/Selenium system
scaffolding is separate. No live migrations or live API calls are needed to test.

Scope tradeoffs: no new immutable adjustment ledger, server-side natural-language
classifier, transfer endpoint, unit conversion, alias management UI, unknown-count
schema, location move API or new authentication transport. Existing shopping now
matches the selected location before updating stock, preserving separate quantities
instead of silently taking the first same-name row. Count consumption/reservations
continue to use the existing task completion services.

The dated, database-guarded migration preservation check is retained at
[scripts/tmp/verify_nested_inventory_migration_20261027.rb](../scripts/tmp/verify_nested_inventory_migration_20261027.rb).
It only runs against `wayfinder_api_test_nested_20261027`, refuses existing child
locations, exercises rollback/reapply with synthetic legacy rows, and removes only
those synthetic rows. It is a test tool, never a production migration command.
