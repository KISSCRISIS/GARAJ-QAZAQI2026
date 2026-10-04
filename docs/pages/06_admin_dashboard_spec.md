# 06 admin_dashboard.html — Security Operation Center (independent)

## Layout

Header (admin user) + Sidebar + Main. Separate from Portal. Portal = institution face; Admin = control center.

## Sidebar

Dashboard, Registration Requests, Employees, Devices, Offline, Permissions, Access Logs, Security, Settings.

## Dashboard cards (example numbers only — real data from DB)

Pending Requests, Active Employees, Today's Access, Denied Attempts, Gate Devices.

## Analytics (required, not generic events)

- Chart 1 Emergency Permanent Staff: Physicians, Nurses, Paramedics, Radiology, Laboratory, Administration, Accounting, Maintenance, Security.
- Chart 2 Other/Temporary/External: Temporary Doctors, External Specialists, Consultants, Visitors With Permission.

## Requests table

Photo, name, type, department, device, status, actions + Employee Drawer (identity, employment, permission, device, history).

## Devices / Offline / Security

- Devices: gate_id, online status, heartbeat, version, token.
- Offline: pending sync, last sync, device status.
- Security: failed QR, invalid device, denied access, admin actions.

## Rules

Build after Authentication + Roles + RLS. Admin is the highest-risk surface.
