# Production RPC Canonical Map

## Purpose

This document defines the production-canonical RPC signatures for ALBASHIR Gate and the legacy signatures that must remain frozen.

The map exists to prevent future patch execution from reintroducing insecure overloads or allowing the final function body to depend on arbitrary file order.

> **Repository documentation only:** this file does not execute SQL, delete functions, or change Supabase Production.

## Canonical RPCs

| Capability | Canonical RPC | Canonical source of definition | Notes |
|---|---|---|---|
| Secure QR creation | `create_qr_session(text, text)` | `schema_patch_gate_qr_device_auth.sql` | Requires an active gate device and a valid non-revoked device token before creating a QR session. |
| Employee registration | `register_employee_request(13 args)` | `schema_patch_trusted_device_registration_flow.sql` | Includes Trusted Device registration metadata and pending-request ownership validation. |
| Trusted Device fast login | `trusted_device_profile_login(text)` | `schema_patch_trusted_device_metadata.sql` | The only repository owner of this function definition. Requires an approved, enabled Trusted Device. |
| Guard device approval | `admin_approve_gate_device(text, boolean)` | Production canonical API from the offline gate flow | Use this API for guard-device approval and status changes. |

### Canonical ownership rules

1. `trusted_device_profile_login(text)` must be defined only in `schema_patch_trusted_device_metadata.sql`.
2. `schema_patch_trusted_device_registration_flow.sql` must not redefine or grant the Trusted Device fast-login function.
3. `schema_patch_production_hardening.sql` must not redefine the legacy no-argument QR creator or the 8-argument registration function.
4. Guard-device administration must use `admin_approve_gate_device(text, boolean)`.
5. Do not infer production state from a repository filename alone; verify the final signature, body, and grants in the controlled migration history.

## Legacy frozen RPCs

These signatures are retained for compatibility and historical reference. They must not receive new runtime callers.

| Legacy RPC | Status | Required treatment |
|---|---|---|
| `create_qr_session()` | Frozen legacy | Do not use for QR creation. The old body must not be reintroduced by production hardening. Freeze its grants in a separately reviewed migration. |
| `create_qr_session(text)` | Frozen legacy | Production metadata previously reported this overload. Do not add callers. Freeze its grants after confirming external consumers. |
| `register_employee_request(8 args)` | Frozen legacy | Use the 13-argument Trusted Device registration flow instead. Do not redefine or re-grant this overload from production hardening. |
| `admin_set_guard_device_status(text, boolean)` | Deprecated, non-canonical | Do not apply `schema_patch_guard_device_admin_control.sql` to Production. Use `admin_approve_gate_device(text, boolean)`. |

> **No functions are deleted by this map.** Removal, if ever approved, requires a separate consumer inventory and migration decision.

## Recommended migration order

For a new controlled environment, use an explicit dependency order rather than executing repository patches alphabetically:

1. `schema.sql`
2. `schema_patch_pgcrypto_schema_fix.sql`
3. `schema_patch_offline_gate_mode.sql`
4. `schema_patch_auto_verify.sql`
5. A cleaned production-hardening migration that keeps `manual_employee_check`, `claim_qr_session`, `validate_and_use_qr_token`, cleanup functions, and administrative permission wrappers, but does not define legacy QR or registration overloads.
6. `schema_patch_trusted_device_registration_flow.sql` without a duplicate `trusted_device_profile_login(text)` definition.
7. `schema_patch_trusted_device_metadata.sql` as the sole owner of `trusted_device_profile_login(text)`.
8. `schema_patch_gate_qr_device_auth.sql` as the final QR-device-auth definition layer.
9. A separately reviewed legacy-freeze migration for legacy grants.
10. A post-migration signature and grant verification step.

## Production rules

The existing Production database must not be rebuilt by rerunning all repository patches. Use a narrowly scoped, reviewed delta migration that:

- preserves `create_qr_session(text, text)` as the canonical QR entry point;
- prevents the old no-argument QR implementation from being reintroduced;
- preserves `register_employee_request(13 args)` as the canonical registration entry point;
- leaves the 8-argument registration overload frozen until consumer inventory is complete;
- installs exactly one body for `trusted_device_profile_login(text)`;
- uses `admin_approve_gate_device(text, boolean)` for guard-device administration;
- freezes legacy grants only after confirming external callers;
- never drops a function as part of this canonicalization map.

## Pre-Production checklist

- [ ] Confirm the final body for every canonical signature.
- [ ] Confirm `trusted_device_profile_login(text)` has one definition source.
- [ ] Confirm `schema_patch_production_hardening.sql` contains no legacy QR creator definition.
- [ ] Confirm `schema_patch_production_hardening.sql` contains no 8-argument registration definition or grant.
- [ ] Confirm no production runtime caller uses a frozen overload.
- [ ] Confirm `admin_approve_gate_device(text, boolean)` is the only guard approval API used by production runtime.
- [ ] Review legacy grants before applying a separate freeze migration.
- [ ] Record the applied migration order and final RPC signatures in Production mapping.
