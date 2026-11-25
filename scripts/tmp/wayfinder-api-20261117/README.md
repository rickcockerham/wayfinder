# Historical API activation checks

These are the one-off verification scripts used for the November 17, 2026
deployment. They contain no usable credentials. They load the private local
client file or the existing service environment without printing its secrets.

Do not rerun them as a generic test suite: they reference the original request
prefix and the already deleted temporary item 246. `live-smoke.rb` would create
a new temporary item, while `cleanup-test-item.rb` deliberately accepts only
the exact original item ID/title/nonce. The cleanup checks are preserved so the
scope of the original production deletion can be reviewed.

- `live-smoke.rb`: bounded bearer reads, authentication/routing checks, one
  uniquely marked nonrecurring create/read/PATCH/PUT and validation probe.
- `cleanup-test-item.rb`: rechecks the exact temporary item before deletion,
  then verifies GET 404.
- `verify-deployment.sh`: run over the existing server SSH connection; privately
  reuses the service runtime for read-only DB checks, verifies request-log
  status/IP/date/user/fingerprint and preserved deployment-file hashes.

Use the maintained `bin/wayfinder-api` client for normal operations. See
[the API contract](../../../docs/items-api.md) and
[deployment receipt](../../../docs/reports/wayfinder-api-20261117.md).
