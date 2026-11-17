# Wayfinder bearer access and request diagnostics

Activated November 17, 2026, at approximately 09:16 CST. Code release:
`4406f33` (`Add revocable bearer API access and request audit logs`).

## Authentication and local operation

The assistant's fixed random token is stored in the private local file
`~/.config/wayfinder/api.json` (0600; parent directory 0700), outside Git. It maps
to existing user 1, Default. The server stores only the token's SHA-256 digest
and owner ID in `/etc/wayfinder/api.env` (root-owned, 0600), loaded by
`wayfinder.service.d/api.conf`. No browser session or manual sign-in is required.
Website cookie authentication and its CSRF checks remain available.

```sh
/code/wayfinder/bin/wayfinder-api get '/api/items?include_choices=1'
```

The full request/credential maintenance contract is in [items-api.md](../items-api.md).
No token or client IP is copied into this receipt or Git history.

## Verification

- Complete isolated ordinary suite: 72 runs, 841 assertions, zero failures,
  errors or skips, on `wayfinder_api_test_bearer_20261117`.
- Rails eager loading and diff whitespace checks passed.
- Live bearer listing/choices and item reads returned 200; creation returned
  201; PATCH and PUT returned 200; invalid dates returned 422.
- Missing/wrong credentials returned 401. An unknown API route returned 404.
  Bearer access alone did not create a website login (302 to login).
- Bearer responses used `Cache-Control: no-store` without issuing CSRF or
  browser-session cookies.
- Created exactly one uniquely labeled nonrecurring verification item (246),
  checked its identity before deleting it, received DELETE 200, then GET 404.
  Default's item count was 224 before testing and 224 after cleanup.
- Queried the production `api_request_logs` table and matched all 12 expected
  API test request IDs/statuses. Verified dates, IPs, durations, token
  fingerprints and authenticated owner. The website request was excluded.
- Compared hashes for all 13 pre-existing modified/untracked deployment files;
  all were preserved. The running checkout remains `/var/www/wayfinder`.

The production migration created only `api_request_logs`. Entries contain UTC
time, proxy-aware client and peer IP, user, authentication method, token
fingerprint, request ID, method, path, status, duration, user agent and available
exception classes. Raw credentials, query strings and bodies are excluded.

Private operational evidence remains under `/var/backups/wayfinder-api-20261117/`
on the server and `/tmp/wayfinder-live-bearer-20261117/` locally. The deployment
uses the existing SSH access and service credentials without exposing them.
