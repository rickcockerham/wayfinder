# Native task blockers API

Local implementation on `feature/native-blockers-api`; deployment and any live
Dusty backfill are separate actions. No live tasks or relationships were changed.

Wayfinder has one `Item` model for tasks/projects and optional parent/child groups;
there is no separate Project resource. A parent is not a prerequisite. Native
`ItemBlock` relationships use `blocker_id → blocked_id`: **A must finish before B**.
An unfinished blocker makes that edge `active: true`. For an unfinished task, any
active incoming edge blocks readiness and home/priorities eligibility. Completing
A retains its links but makes them inactive; reactivation restores normal native
blocking behavior. This API reuses those rules without changing importance scores,
notes, completion state, deadlines or parent grouping.

## Commands and direction

The existing protected client uses the same fixed HTTPS origin, private bearer
file and token. No new credential or browser session is needed. IDs below are
illustrative, not live Dusty IDs:

```sh
# Prerequisite 123 blocks task 456 (not the reverse).
bin/wayfinder-api block 123 456
# Incoming prerequisites of task 456.
bin/wayfinder-api blockers 456
# Tasks that prerequisite 123 blocks.
bin/wayfinder-api blocks 123
# Remove only the relationship with the returned edge ID, not either task.
bin/wayfinder-api unblock 789
```

The generic client commands remain supported:

```sh
bin/wayfinder-api get '/api/item_blocks?blocked_id=456&limit=100'
bin/wayfinder-api get '/api/item_blocks?blocker_id=123&limit=100&after_id=789'
bin/wayfinder-api get /api/item_blocks/789
bin/wayfinder-api post /api/item_blocks edge.json
bin/wayfinder-api delete /api/item_blocks/789
```

`edge.json` contains `{"item_block":{"blocker_id":123,"blocked_id":456}}`.
No user ID, other writable fields or endpoint creation is accepted. Filters are
positive integer query strings, scoped to existing owned items. Both filters can
be combined for an exact pair. Follow `next_after_id` with the same filters until
null; shortcuts show the first page only. Default limit 50, allowed range 1–100.

## HTTP contract

| Method | Path | Result |
| --- | --- | --- |
| GET | `/api/item_blocks?blocked_id=456` | Incoming prerequisite edges, paginated |
| GET | `/api/item_blocks?blocker_id=123` | Outgoing dependency edges, paginated |
| GET | `/api/item_blocks/:id` | One owned link |
| POST | `/api/item_blocks` | Create one directed link, or reuse the exact existing pair |
| DELETE | `/api/item_blocks/:id` | Delete that link only |

Creation returns 201 for a new link or 200 with the same ID on a duplicate retry:

```json
{"item_block":{"id":789,"blocker_id":123,"blocked_id":456,"blocker":{"id":123,"title":"Prerequisite","done":false},"blocked":{"id":456,"title":"Dependent task","done":false},"active":true}}
```

Read-one has the same shape. List is
`{"item_blocks":[...],"next_after_id":null}`. Deletion returns
`{"deleted":789}`. The `id` is the edge ID; `blocker_id` and `blocked_id` are
stable item IDs. No owner secrets are returned. To determine all prerequisites,
read incoming edges and complete pagination rather than treating one edge as the
whole blocked state.

Self-links and new cycles return 422 with validation details. The model checks
all directed edges, including completed prerequisites, iteratively; editing an
edge excludes its old connection from the check. Existing legacy cycles are not
automatically rewritten/deleted, and traversal cannot loop forever on them.
API creation and the existing web create/update paths lock the owner before
validation/persistence, so opposing concurrent requests cannot introduce a cycle.
Duplicate links are reused by the API and remain constrained by the existing
unique index. Native web edits retain their existing uniqueness validation.

Missing/deleted/foreign endpoint or edge IDs return 404 without creating items,
revealing foreign titles or restoring stale records. A repeated delete after
successful removal returns 404. Malformed IDs/extra create fields return 422;
malformed filters/pagination/JSON or missing objects return 400; non-JSON creation
returns 415. A foreign-owned or corrupt cross-owner legacy link is unavailable
through index/show/delete.

Existing bearer validation, invalid-header precedence, `Cache-Control: no-store`
and request auditing are inherited. Invalid bearer requests return 401. Browser
sessions retain CSRF; an anonymous write without a CSRF token can be rejected
with 422 before the ordinary authentication callback. There is no CSRF bypass
except the existing verified-bearer mechanism.

## Destroying a task/project

Both supported item destroy paths use `Item#destroy`:

- Bearer API: `DELETE /api/items/:id`.
- Ordinary item/project detail-page **Destroy** form, after confirmation.

The existing model destroys incoming `blocking_edges` and outgoing
`blocking_out_edges`. Existing foreign keys cascade both endpoint IDs as a second
layer. Removing A therefore removes A→B links; removing B removes A→B links too.
It does not delete the surviving item or unrelated edges. Parent deletion retains
child items, nullifies their parent IDs, and retains edges between surviving items.
This adds no subtree/project cascade and does not change existing inventory,
material/reservation destruction policies. The detail form now uses explicit
native confirmation and a native DELETE submission, consistent with Inventory.

No migration is needed: the unique pair index, both cascade foreign keys and both
model-dependent relationships already exist in the current repository schema.
Production database constraints were not queried. No production endpoint or
Dusty relationship was exercised as part of development.

## Validation

Use an explicitly disposable `wayfinder_api_test_NAME` database with
`bin/test_items_api wayfinder_api_test_NAME`. Tests cover API/CLI direction and
read-back, duplicate retries, self-links/cycles, malformed/stale references,
completed-blocker eligibility, both owner boundaries, corrupt legacy edges,
concurrent API/web writes, and cleanup through both item destroy paths. The
local browser regression is `test/system/item_block_deletion_test.rb`; it clicks
Cancel and Confirm against fixture-only tasks and checks both edge directions,
retained children and unrelated survivors.

CLI integration runs the actual executable and real Rails router/controllers/test
DB while replacing only the network hop. It does not claim external TLS or live
production validation. Use a separate disposable browser database, as described
in [inventory-api.md](inventory-api.md).
