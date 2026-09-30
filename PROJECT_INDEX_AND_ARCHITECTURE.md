# ALBASHIR Gate - Project Index & Architecture

## 1. Overview
Unified access control system for administration, guard devices, and employees.

Main flows:
- Employee registration and approval.
- Guard QR generation and validation.
- Trusted device automatic verification.
- Admin approval and auditing.
- Offline gate support.

## 2. Main Components

```
Employee Portal
    |
    v
employee_registrations
    |
    +--> trusted_device
    |
    +--> gate_access_logs

Guard Device
    |
    v
gate_devices
    |
    +--> qr_sessions
    |
    +--> offline_device_tokens

Admin Dashboard
    |
    +--> approvals
    +--> permissions
    +--> audit logs
```

## 3. SQL Patch Execution Order

1. schema.sql
2. schema_patch_pgcrypto_schema_fix.sql
3. schema_patch_permanent_specialty.sql
4. schema_patch_auto_verify.sql
5. schema_patch_offline_gate_mode.sql
6. schema_patch_verify_employee_profile.sql
7. schema_patch_employee_profiles.sql
8. schema_patch_trusted_device_registration_flow.sql
9. schema_patch_trusted_device_metadata.sql
10. schema_patch_production_hardening.sql
11. schema_patch_gate_qr_device_auth.sql

Migration dependencies:

- Run `schema_patch_pgcrypto_schema_fix.sql` before patches that depend on the trusted-device and offline-device hashing functions.
- Include `schema_patch_trusted_device_registration_flow.sql` because it provides the employee trusted-device registration, approval, and pending-to-trusted promotion flow.
- Run `schema_patch_gate_qr_device_auth.sql` last because it overrides the QR runtime with `create_qr_session(device_code, device_token)` and replaces the unsecured QR-generation flow with trusted guard-device authentication.

## 4. Critical Tables

### employee_registrations
Stores employee identity, approval status, profile, and trusted device data.

### gate_devices
Stores guard terminals and activation state.

Important fields:
- device_code
- is_active
- last_seen_at
- last_qr_at

### qr_sessions
Controls QR lifetime and usage.

### gate_access_logs
Complete access history.

### admin_audit_logs
Administrative tracking.

## 5. Trusted Device Flow

```
Employee registers
        |
Device token saved as pending
        |
Admin approves employee
        |
Trusted device activated automatically
        |
Future QR scans use device verification
```

## 6. Guard Device Flow

```
Guard opens screen
        |
Heartbeat sent
        |
gate_devices checked
        |
Device approved?
        |
QR session created
```

If inactive:

```
جهاز الحارس بانتظار اعتماد الإدارة
```

## 7. Access Decision Logic

Priority:

1. Employee status
2. Trusted device validity
3. QR validity
4. Permanent specialties
5. Daily specialty limits

## 8. Troubleshooting

### QR cannot generate
Check:
- gate_devices.is_active
- offline_device_tokens
- device token validity

### Employee cannot auto login
Check:
- trusted_device_enabled
- trusted_device_token_hash
- employee status APPROVED

### Device pending approval
Activate the device from admin workflow.

## 9. Production Notes

- Do not rerun schema.sql on a live database.
- Apply patches in order.
- Keep audit logs enabled.
- Reload Supabase schema after RPC changes.

## 10. Current Architecture Status

Database layer: Ready
Trusted device layer: Ready
Offline gate layer: Ready
Employee profile layer: Ready
Production hardening: Applied
