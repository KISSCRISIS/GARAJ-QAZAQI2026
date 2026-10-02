# ALBASHIR Emergency Hospital Gate — UI Implementation Specification v1.0

Master reference for developers and coding agents. Read before any code change.

## Authority order

Master Specification v5 → Design System → Image Assets Rules → Frontend Specification → Repository Audit → Implementation.

## Page order (approved)

Shared UI System → portal.html → register.html → profile.html → verify.html → guard.html → admin_dashboard.html → Authentication → Supabase Integration → Production Testing.

## Design principle (approved correction)

Same identity only — different personality per page. Do NOT copy Portal into other pages.

| Page | Personality |
|---|---|
| portal.html | Corporate Hospital Portal |
| register.html | Guided Registration Workflow |
| profile.html | Employee Personal Portal |
| verify.html | Security Scanner |
| guard.html | Guard Operation Screen |
| admin_dashboard.html | Control Center |

Shared: identity, colors, Arabic RTL First fonts, base components.

## Tokens (canonical — align `global-theme.css` on next UI pass, no change now)

- Primary `#061B38`, Medical Dark Blue, Hospital Cyan `#16b8d9`, Medical Blue `#007BFF`
- Security Green `#00D084`, Warning `#FFB020` / Amber, Danger `#FF4545`, Gold Accent `#C9A227`
- States (unified): Success / Warning / Pending / Error / Offline
- System pill mandatory on every page: SYSTEM ONLINE / OFFLINE

## Leadership (original photos only)

Dr. Salah Al-Qazqi (Director) / Dr. Suleiman Abu Awad (Assistant) / Dr. Hassan Shehadeh (Head). Crop/resize/alignment only. No AI replacement, no face edits.

## Security (binding)

- Frontend displays only. All decisions in Backend (Supabase RPC).
- Access order: Employee Status → Trusted Device → QR Validation + Consume → Specialty Rules → Daily Limits.
- No QR without Supabase validation of an approved `gate_devices` record. No public fallback QR. `activeQrToken` flow only.
- Forbidden: permissions in JS, duplicate auth, SQL/migration without production review, RLS bypass, sensitive data in local storage.

## Guard login (approved correction)

Guard entry is `Access Code + Device check` only. Fields `Date Of Birth / Age / Residence` are REJECTED (privacy + open-screen principle).

## Agent instruction

Read the specification documents first. Do not modify architecture. Implement only according to approved UI and security flows.
