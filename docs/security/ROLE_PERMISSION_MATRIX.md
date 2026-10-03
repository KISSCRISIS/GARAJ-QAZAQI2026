# ROLE_PERMISSION_MATRIX

- SUPER_ADMIN: approve/reject, manage admins, limits, violations, logs, CSV export, audit.
- ADMIN (SUB_ADMIN normalized in UI): approve/reject, violations, logs view. No admin management, no limits change, no self-promotion by default.
- GUARD: camera + QR result only. No search, no edit, no profiles, no full logs.
- EMPLOYEE: own profile + QR verify. Permission badge read-only.
- Enforcement is Backend (RLS + RPC). UI hiding is not security.
