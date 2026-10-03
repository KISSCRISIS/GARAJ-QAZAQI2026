# QR_VALIDATION_FLOW

1. Guard heartbeat validates `gate_devices.is_active`.
2. `create_qr_session(device_code, device_token)` issues 30s single-use token; render locally.
3. Employee scans → `claim_qr_session` (5-min claim) → `validate_and_use_qr_token` (atomic consume).
4. Decision order: Employee Status → Trusted Device → QR → Specialty → Daily Limits.
5. Every outcome writes `gate_access_logs` + `guard_screen_status`. No public fallback QR. Offline only queues; never ALLOWED offline.
