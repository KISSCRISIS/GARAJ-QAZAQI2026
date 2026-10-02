# RLS_POLICY_GUIDE (review before any SQL run)

- Compare signature, grants, SECURITY DEFINER, and dependencies before running any `schema_patch_*.sql` on production.
- Patches run once in canonical order; never rerun `schema.sql` on live DB; reload Supabase schema after RPC changes.
- Violation/employee photos are private; use signed URLs. Never expose public object URLs.
- `register_employee_request` grant stays revoked in hardening; registration path follows canonical RPC map.
