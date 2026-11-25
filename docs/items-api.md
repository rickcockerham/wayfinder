# Items API

Routes cover items only; no catalog management, planner, shopping,
inventory, blocker-management, settings or new login endpoint is added.

## Morning priorities

```sh
bin/wayfinder-api get /api/items/priorities
bin/wayfinder-api get '/api/items/priorities?limit=20'
bin/wayfinder-api get '/api/items/priorities?category_id=12&mood_ids[]=3&time_i=2'
```

`GET /api/items/priorities` uses the existing bearer key and defaults to at most five
items in the same order as the home view for the **reported effective filters**.
The browser and API share `HomeItemSelection`; no ranking formula is duplicated.
Response: `{observed_at,filter_source,filters,items:[{id,title,url,deadline,
hide_days,importance_score}]}`. `observed_at` is UTC. An empty eligible set returns
an empty array. Set `limit` to a decimal integer from **1 to 100**; omitted means
**5**. `limit=20` returns the first twenty eligible items, or fewer if fewer qualify.
Blank, non-integer, structured, zero, negative or over-100 limits return HTTP 400
`{error:"invalid_limit"}`. Returned `filters.per` reports the effective limit.
This route creates no items, settings or browser-filter state;
existing API request diagnostics still record the request.

Non-browser defaults are a **fresh home view**, not another browser's saved state:

- Empty search: exclude completed items, items outside Hide Until, and items with
  unfinished blockers. Hide Until keeps the existing strict boundary:
  `days_until_deadline < hide_days`; blank deadline or nonpositive hide_days is
  always visible. A completed blocker no longer excludes its dependent item.
- All visible moods, all time scales (7), importance descending and five results.
  The shared home normalizer applies its existing behavior if no moods are visible.
- Category from the current planner entry for the owner's local date/day part,
  using saved planner timezone/start times. The most recently updated matching
  planner entry wins. If none applies, no category restriction is used.
- Actual owner importance settings determine scores. Missing settings use the
  existing in-memory defaults without creating a settings record. Ranking and
  Hide Until use the application's existing `Date.current` semantics.

Explicit `mood_ids[]`, `category_id`, `time_i` and `sort` query parameters use the
same normalization as the home view. `category_id=` clears the planner category;
blank mood selection normalizes to all visible moods. `sort=time` requests the
home's time-scale/deadline ordering; default `sort=importance` ranks by score.
Invalid sort falls back to importance, out-of-range time to 7, unavailable mood
IDs are removed and unavailable category IDs clear that restriction, as at home.
Malformed filter structures return 400. Nonempty `q` returns 400 so search cannot
bypass morning eligibility. `per` does not control API result count; use `limit`. The morning brief default remains five.

Even cookie-authenticated calls use fresh defaults plus explicit overrides;
the API neither reads nor overwrites the browser's one-hour saved filters. Send
known active filters explicitly when matching a particular browser view. Returned
`filters` makes the effective selection inspectable. Ties preserve the existing
home behavior: equal importance keeps database retrieval order; time sorting uses
time scale then deadline. No new ID tie-break or cross-request tie guarantee is
introduced. Generic `/api/items` remains ID-ordered and includes completed items.

## Authentication

The assistant uses one fixed, random 256-bit bearer token over HTTPS. Send
`Authorization: Bearer TOKEN`. The server stores only its SHA-256 digest in
`WAYFINDER_API_TOKEN_SHA256` and the existing owner's ID in
`WAYFINDER_API_USER_ID`; the token never doubles as a website login key.
Missing/invalid configuration, a wrong token or a deleted owner returns 401.
An explicitly supplied invalid Authorization header never falls back to cookies.

The private local client file is `~/.config/wayfinder/api.json`, owned by the
local user with mode 0600 inside a mode-0700 directory. It contains the `token`
plus nonsecret origin, user ID, creation date and fingerprint metadata. The file
stays outside Git. Requests use the token in-process, keeping it out of command
arguments and shell history. `WAYFINDER_API_CONFIG` can select another private
client file. The client always contacts `https://mywayfinder.app` and never follows
redirects or sends credentials to another origin.

```sh
bin/wayfinder-api get '/api/items?include_choices=1'
bin/wayfinder-api get /api/items/123
# Writes accept a JSON file, or - to read JSON from stdin.
bin/wayfinder-api post /api/items payload.json
```

Only a fully verified bearer token bypasses browser CSRF protection. Bearer
requests do not establish a website login or return a CSRF/session token.
The normal signed `auth_v1` cookie still works for website/browser clients, but
its current user ID and access key must match an existing user. Cookie writes
retain CSRF protection. Tokens in query/body parameters are not accepted.

An authenticated cookie GET returns `X-CSRF-Token`. Send this token with POST/PATCH/PUT/
DELETE and retain the session cookies. Controller responses use `Cache-Control: no-store`.
A browser console example on the already authenticated Wayfinder origin:

```javascript
const listing = await fetch('/api/items?include_choices=1', { credentials: 'same-origin' });
const csrf = listing.headers.get('X-CSRF-Token');
const page = await listing.json();
// Choose the closest category and mood by task meaning from page.choices.
// Preserve explicit user choices; the illustrative IDs below must be replaced.
const result = await fetch('/api/items', {
  method: 'POST', credentials: 'same-origin',
  headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
  body: JSON.stringify({ item: { title: 'Call supplier', category_id: 12, mood_id: 3 } })
});
console.log(await result.json());
```

The IDs above are illustrative. Use the owner's existing category/mood choices.
Create a clearly labeled disposable item when verifying live mutations, and
delete only that item after checking its returned ID and unique title.

## Credential maintenance

No scheduled rotation or expiry is required. The assistant can retain the fixed
token locally and use SSH to maintain the service without browser login.
Production owner is user 1 (Default). Server settings live in
`/etc/wayfinder/api.env`, loaded by the `wayfinder.service` drop-in
`/etc/systemd/system/wayfinder.service.d/api.conf`; the application directory is
`/var/www/wayfinder`. Existing service settings and credentials remain separate.
Use existing SSH access to `root@mywayfinder.app` for maintenance.

To rotate, generate `SecureRandom.hex(32)`, replace the server's digest and the
private client's token/fingerprint, and restart `wayfinder.service`. Replace the
client file atomically with mode 0600; never print the new token. To revoke
bearer access, remove the digest from the server environment and restart the
service. Keep the existing local token until deliberately rotating it. Changing
a website login key does not rotate this independent API credential.

## Request diagnostics

The `api_request_logs` server database table records every `/api` and `/api/*`
request, including authentication/CSRF failures and routing errors. It stores
UTC request date, proxy-aware client IP, peer IP, request ID, method, path,
status, duration, user agent, resolved user ID, authentication method, token
SHA-256 fingerprint and exception class. An IP-spoof resolution failure retains
the peer address and its own exception class. Raw tokens, Authorization values,
cookies, query strings and request bodies are excluded.

Token fingerprints identify the exact credential used, including failed bearer
attempts. User IDs are recorded only after credential verification; routing
errors may have a token fingerprint without a resolved user. No automatic log
deletion is enabled. If inserting a diagnostic row fails, Rails logs a sanitized
exception class and preserves the original API response.

## Contract

| Method | Path | Response |
| --- | --- | --- |
| GET | `/api/items?limit=50&after_id=0` | `{items:[...],next_after_id:null}` |
| GET | `/api/items?include_choices=1` | List plus `{choices:{categories:[{id,name}],moods:[{id,name}]}}` |
| GET | `/api/items/priorities` | Fresh-home selection, limit 1..100 (default 5), effective filters and UTC observation time |
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
date requires both month and day. For title-only user requests, Rick authorizes
the assistant to infer the closest existing category and mood from task meaning.
Fetch `GET /api/items?include_choices=1` and choose from `choices.categories` and
`choices.moods`, then submit the chosen IDs along with the title. This metadata
contains only the owner's visible choices, including choices unused by any item,
ordered by name then ID. It is available even when the item list is empty and is
omitted unless requested, keeping normal reads compact. It adds no catalog CRUD
routes. If either list is empty, report the missing prerequisite; do not invent
IDs or create catalog records. Refresh choices if a concurrent change yields 422.

Inference belongs to the assistant: the server does not classify text or select
arbitrary defaults. Explicitly supplied category/mood values take precedence.
Raw POST with a title alone still returns 422 because both associations are
required. Priorities remain zero and deadline blank when omitted.

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

API tests cover unauthorized and cross-user access, bearer rotation/revocation,
verified bearer CSRF exemption, retained cookie CSRF, request diagnostics, defaults,
explicit values, pagination, validation, lifecycle and fixture-only hard deletion.
Choice tests cover unused visible options, hidden/cross-user exclusion, empty item
lists, anonymous denial and enriched capture with zero priorities/blank deadline.
The ordinary Rails suite includes existing web and model regressions. Selenium
system scaffolds have not been run: they assume unauthenticated access and do not
supply required item fields. No browser dependency was installed.

The ordinary suite also covers priorities eligibility, Hide Until boundaries, owner-specific ranking, planner defaults, explicit filters, ties, cookie-state separation and the real CLI-to-controller entry point with synthetic credentials.

The ordinary suite includes the standalone client tests. Run them directly with
`bundle exec ruby test/scripts/wayfinder_api_client_test.rb` when validating only
the client. Apply the `CreateApiRequestLogs` migration before restarting the
updated production service. The assistant can enrich title-only requests from
the opt-in choices metadata as Rick authorized.
