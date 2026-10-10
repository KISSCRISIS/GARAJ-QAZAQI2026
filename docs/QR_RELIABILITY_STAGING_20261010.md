# QR Reliability — Staging verification record (2026-10-10)

## Baseline and environments
- Supabase **Staging**: `adwvokwucotohwayorgx`
- Vercel project **Staging**: `prj_JjO406dgtk3GIjxqWGkhZL16M5mO`
- Current main Staging aliases are still assigned to original deployment `dpl_81Vbtu3ao56qA9gRYDx2fhBVQHc2`.
- **FINAL READY Preview**: `dpl_8k7TAzrDiPpAjr3XTbEJr28VfEFg`; `https://albashir-staging-cnw8xqlv2-kisscrisis-projects.vercel.app/guard.html`.
- **No changes to Supabase Production** (`qinsfvlspdticposbvst`).
- Vercel uses 61 byte-for-byte retained assets from original Staging except `index.html` and `guard.html` source changes.
- The branch's pre-existing root HTML does not match the deployed source; do **not** deploy that branch wholesale.
- Public guard QR is the actual deployed `guard.html`. The device-authenticated QR screen is the deployed `index.html`.

## Applied server migrations in Supabase Staging
1. `qr_generation_sharded_admission_metrics` — 16 sharded, bounded issuance buckets instead of the global issuance lock; `RATE_LIMITED` replies; server expiry; aggregate 15-minute diagnostics for authorized admins only.
2. `qr_device_issuance_authoritative_expiry_metrics` — token and device authorization before generation; server `expires_at`, `server_now`, and TTL; per-device successful creation telemetry.
3. `gate_heartbeat_auth_before_telemetry` — validates device secrets before throttling and mutating status, ignores browser-provided `p_last_qr_at`.
4. `qr_expired_result_bounded_cleanup_tuning` — bounded, opportunistic cleanup of result sessions expired for at least ten minutes.

Migrations are tracked as SQL files under `staging_migrations/`. Server QR TTL stays **30 seconds**; guard-result read windows remain independent, about **6 minutes**.

## Preview frontend changes (not yet promoted to main Staging alias)
- `staging_reconciliation/qr_preexpiry_resilience.patch`: modifies the exact live Staging `index.html` to renew at 10 seconds before server expiry, suppress overlapping refreshes, retain prior QR on failures until expiry, backoff 2/5/15/30 seconds, and restore conservatively on reload or reconnect.
- `staging_reconciliation/guard_qr_preexpiry_resilience.patch`: modifies the exact live Staging `guard.html`, prewarms at **12 seconds** before expiry, switches as soon as a valid replacement is ready, uses server duration, retains still-valid old QR on failures, serializes requests, retries with 2/5/15/30s backoff, restores valid QR + up to 24 recent result read keys in per-tab `sessionStorage`. Recalculated and verified inline-script CSP hash. Does not change manual guard-entry UX or ten-second result privacy.

The patches apply to the **deployed Staging source snapshot**. The GitHub branch's older HTML should not be used as the patch base.

## Tests completed
- Transaction-rolled-back SQL fixtures: public issuance OK with separate 64-hex `read_key`, ~30-second server TTL; authorized synthetic device issuance allowed, unauthorized rejected; heartbeat valid token admitted but client-supplied QR timestamp ignored; all 16 rate-limit buckets filled → `RATE_LIMITED`.
- PostgreSQL grants verified: admin metrics RPC denies `anon`; `create_public_guard_qr` still usable as intended by anonymous public guard QR screen.
- Real Staging guard and index source patches applied with `git apply --check` / `git apply`; patched files verified byte-identical to tested outputs.
- Isolated Node VM tests for both UIs: early renewal, previous QR retention on failure, 2s/5s backoff, session persistence/restoration, old-vs-new QR rotation, single-flight and expiry; HTML script parse and CSP digest verified.
- Vercel Preview build READY. Deployment file tree SHA: `guard.html` `97f31f9b817096f1d22ab9a9d2a311f00523fe77`, `index.html` `e2ada43b688d88a993fc10d05b4811d6ce8ee595`; unchanged `guard-manual.js` `d5fbe6d043b36a37ba019c98aa6d3ab6bd26475f`.

## Release blockers / untested
- Preview is Vercel SSO-protected; direct unauthenticated HTTP checks show login content rather than real page responses. Connector protection-bypass request returned 403 (`kisscrisis-projects` authorization). **No verified live browser → API → database → result end-to-end check in that Preview yet.**
- No 300–400 screen concurrency load run; sharded allowance is structurally improved but throughput capacity is not field-proven.
- Admin metrics currently aggregate **server-side failed generation / rate-limited issues**, not all disconnected clients; client-local errors still need explicit diagnosis.
- CSP, scripts, and photo display cannot be certified from Vercel Preview without authenticated browser access.
- `app-version.json` retained from the original Staging deployment; version identity must be updated before main alias promotion.
- Do not claim main Staging alias or Production is updated; original alias remains unchanged.

## Promotion and rollback
1. Reauthorize Vercel connection/scope to access protected Preview, or open it through Work mode with a permitted browser account.
2. Run complete browser smoke tests of public guard QR, manual emergency rules, shared guard account/profile, employee verification, photo, quota, ten-second result reset, reconnection/expiry, and 300-400 load target.
3. Inspect failure metrics and logs before switching the Vercel **Staging** alias.
4. Rollback candidate = `dpl_81Vbtu3ao56qA9gRYDx2fhBVQHc2` for frontend; SQL changes require separate reviewed down migrations before reverting. Production stays untouched.
