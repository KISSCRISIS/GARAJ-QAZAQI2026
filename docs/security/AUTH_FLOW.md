# AUTH_FLOW

- Employee: `employee_id + phone` → `employee_profile_login` → session; trusted-device fast login via `trusted_device_profile_login`.
- Guard: open screen + `Access Code + Device check`; QR issuance requires approved `gate_devices` + heartbeat.
- Admin: Supabase Auth `signInWithPassword` → `get_my_admin_profile` → role SUPER_ADMIN / ADMIN.
- Portal routes unauthorized users back to `portal.html`. Frontend never grants access; it only routes display.
