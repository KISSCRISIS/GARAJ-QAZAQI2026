# ALBASHIR Guard Specification v2.1 — APPROVED

## Objective

`index.html` is the Guard Operational Screen (Guard Verification Terminal).
It verifies employees at the gate. It is not an employee system, search tool,
permission editor, or database browser.

`guard.html` is NOT implemented. A separate path, if ever needed, requires a
clear migration study first — never a parallel copy.

## Security principle

The guard is a Verifier, not a Decision Maker. Decisions come from Backend +
Supabase Rules + Access Control Logic. Frontend displays results only.

Decision order: Employee Status → Trusted Device → QR / Manual Validation →
Specialty Rules → Daily Limits.

## Full flow

Guard Login → Device Verification → Heartbeat Started → Camera Ready →
Scan QR → Backend Validation → Result Display → Access Log.

## State 1 — GUARD_AUTHENTICATION (approved correction)

Approved: Access Code + Device Verification. Then a Guard Session is created
and Device Heartbeat starts.

REJECTED fields: Date of Birth, Age, Residence (privacy; device identity is
the trust anchor).

## State 2 — GUARD_READY

Approved device: green approved card (Gate id, heartbeat age, version,
[Open Camera]). Unregistered device: red card directing to administration.

## State 3 — CAMERA_READY

Camera ready prompt with permission handling, retry, and error state.

## State 4 — SCANNING

Reading QR → Verifying (backend). No decision in frontend.

## State 5 — ACCESS_ALLOWED (green medical)

Photo, name, profession, department + ALLOWED_PERMANENT (internal) or
name, specialty, organization + LIMITED_ALLOWED (external).

## State 6 — ACCESS_DENIED (red)

Denied + reason only (e.g. account not approved, permission expired).

## State 7 — LIMIT_EXCEEDED (amber)

Daily limit reached + specialty + limit/used counters.

## State 8 — OFFLINE MODE (approved wording)

Offline = Last Valid QR Handling + Pending Sync Queue + Event
Synchronization. There is NO ALLOWED from cache and NO locally stored
access decision. Access decisions stay Online Backend Validation.

## State 9 — Emergency Manual Verification (approved correction)

Employee ID only (National ID rejected). Backend RPC + Trusted Device Check
+ Audit Log with MANUAL_VERIFICATION, same decision order as QR.

## Data shown to guard (allowlist)

Photo, name, profession, specialty, department, access state.

## Forbidden to guard

National number, phone, home address, full employee file, data edits,
employee search, profiles, full logs, dashboard.

## Components

Header (Logo, Gate Name, Connection Status) — Guard variant of shared
Header. Result Card (SUCCESS / WARNING / DENIED). Camera Component.

## Backend integration (generic names — validate against production)

guard.js → Device Authentication → Heartbeat RPC → QR Validation RPC →
Access Decision → Insert Access Log. RPC names are NOT final until the
Supabase Production audit.

## Display-only state object

deviceCode, deviceToken (never logged or rendered), heartbeat, camera,
scanStatus READY, result. No authorization fields.

## Acceptance tests

New device: Register → Admin Approval → Heartbeat → Ready. Permanent
employee: Scan → Backend Check → Allowed → Log Saved. External: Scan →
Specialty Rules → Limited/Denied → Log Saved. Network loss: Offline →
Queue Logs → Sync Later (no offline approval).

## Status

Guard Spec v2.1 APPROVED with corrections 1–3 and structural decision (b).
Canonical screen: index.html. Next: Phase 7 admin_dashboard.html (after
Roles, RLS, Approval Flow, Classification, Device Management, Analytics).
