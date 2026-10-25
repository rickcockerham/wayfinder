# Items API

Local implementation for Rick to review and deploy. No migration or credential
provisioning is required. Routes cover items only; no catalog, planner, shopping,
inventory, blocker-management, settings or authentication API is added.

## Authentication

Use an existing Wayfinder login session over HTTPS. The API accepts the existing
signed `auth_v1` cookie only for a currently existing user whose access key still
matches. It fails closed even when web authentication is disabled. It does not
accept keys in URLs or Authorization headers and does not create users or keys.
There is no CORS or CSRF exemption. Use the existing web login flow; no new
persistent access has been enabled.

An authenticated GET returns `X-CSRF-Token`. Send this token with POST/PATCH/PUT/
DELETE and retain the session cookies. All responses use `Cache-Control: no-store`.
A browser console example on the already authenticated Wayfinder origin:

```javascript
const listing = await fetch('/api/items', { credentials: 'same-origin' });
const csrf = listing.headers.get('X-CSRF-Token');
const page = await listing.json();
// Use your own existing category and mood IDs from an item or the web forms.
const result = await fetch('/api/items', {
  method: 'POST', credentials: 'same-origin',
  headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
  body: JSON.stringify({ item: { title: 'Call supplier', category_id: 12, mood_id: 3 } })
});
console.log(await result.json());
```

The IDs above are illustrative. Do not execute examples against user data just
to test this implementation. An assistant client needs an existing authenticated
session and CSRF support. No bearer-token access mechanism was introduced.

## Contract

| Method | Path | Response |
| --- | --- | --- |
| GET | `/api/items?limit=50&after_id=0` | `{items:[...],next_after_id:null}` |
| GET | `/api/items/:id` | `{item:{...}}` |
| POST | `/api/items` | 201 `{item:{...}}` |
| PATCH / PUT | `/api/items/:id` | 200 `{item:{...}}` |
| DELETE | `/api/items/:id` | 200 `{deleted:123}` |

Writes require JSON `{ "item": { ... } }`. PATCH and PUT both update supplied
fields only. Unknown fields are rejected. Missing/foreign item IDs return the
same 404. All reads and writes are scoped to the signed-in owner.

List includes active and completed items, ordered by ascending ID, with a maximum
of 100 rows per page (default 50). Pass `next_after_id` back as `after_id` until it
is null. This stable traversal deliberately does not reproduce the web's filtered,
dependency-aware importance ordering. Existing ranking and web behavior are
unchanged. The list returns ID, title, category/mood IDs, all three impacts,
deadline, time scale and done. Read/create/update return all writable fields plus
ID, completion time and created/updated timestamps; no ownership or auth secrets.

| Field | Accepted value / default on create |
| --- | --- |
| `title` | Required nonblank string, max 255 characters |
| `notes` | String or null |
| `category_id`, `mood_id` | Required existing owned IDs |
| `parent_id` | Existing owned item ID or null; self-parent rejected |
| `personal_impact`, `emotional_impact`, `family_impact` | JSON integer 0..5; each omitted field defaults to **0** |
| `deadline` | ISO `YYYY-MM-DD`, null or empty string; omitted defaults to **null** (blank) |
| `time_scale` | JSON integer 0..7, default 0; Quick, Minutes, Hours, Days, Weeks, Months, Years, Forever |
| `hide_days` | Nonnegative JSON integer, default 0 |
| `done` | JSON boolean, default false |
| `recurrence_kind` | `no_recurrence` (default), `fixed_schedule`, `after_completion` |
| `recurrence_unit` | `day` (default), `week`, `month`, `year` |
| `recurrence_interval` | JSON integer >=1, default 1 |
| `recurrence_day_of_month` | JSON integer 1..31 or null |
| `recurrence_month_of_year` | JSON integer 1..12 or null |

"Individual priority" maps to the actual `personal_impact` column. Explicit
values are preserved; omitted update fields are unchanged. A yearly specific
date requires both month and day. Category/mood defaults are **not configured**
in the application or seeds. Title-only creation therefore returns 422 until
Rick chooses meaningful category/mood defaults; this API does not guess, create
catalog entries or alter live settings.

Completion reuses `ItemCompletion` and `RecurrenceAdvancer`: reserved inventory
is consumed once on false-to-true, recurring dates advance on the same item and
clear done/completed_at, and reactivation clears completion and reactivates
blockers. API updates lock the item and perform these effects in one transaction;
a failure rolls back the API operation. The web controller remains unchanged.

**DELETE is a hard delete with no restore endpoint or recovery guarantee.** It
uses the same model destruction as the web: children lose their parent; blocking
edges, material requirements and item reservations are destroyed. Inventory
records themselves are not destroyed. No deletion was tested on user data.

Errors are JSON `{error:"code",details:{field:["message"]}}` (details for
validation errors). Statuses: 400 malformed JSON/payload/pagination; 401 missing
or stale login; 404 inaccessible/missing item; 415 non-JSON write; 422 validation,
association or CSRF failure; 409 deletion foreign-key conflict; 500 unexpected
mutation failure (transaction rolled back, no internal exception details exposed).

## Validation and activation

`bin/test_items_api DATABASE_NAME` runs the complete ordinary Rails suite against
an already prepared, disposable MySQL database whose name begins
`wayfinder_api_test_`, using the checkout's existing aidb/pixie test connection.
It refuses other names. Do not point tests at development or production data.
The dedicated database used for this task is
`wayfinder_api_test_20261025_0925`; it has intentionally been left in place.

```sh
bin/test_items_api wayfinder_api_test_20261025_0925
```

API tests cover unauthorized and cross-user access, revocation, CSRF, defaults,
explicit values, pagination, validation, lifecycle and fixture-only hard deletion.
The ordinary Rails suite includes existing web and model regressions. Selenium
system scaffolds have not been run: they assume unauthenticated access and do not
supply required item fields. No browser dependency was installed.

Rick: review and deploy this branch through the usual process, then use an
existing authenticated session. Decide which category and mood should be used
for title-only capture before promising that workflow. Any future new access
mechanism needs separate approval before provisioning credentials or enabling it.
