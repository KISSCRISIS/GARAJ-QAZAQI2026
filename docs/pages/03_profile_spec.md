# 03 profile.html — Employee Personal Portal (read-only)

## Structure

Profile Header → Employee Identity Card (photo, QR) → Permission Card → Trusted Device Card → History Table (date, action, result, gate).

## Permission Card (display only)

- ALLOWED_PERMANENT (green)
- LIMITED_ALLOWED (yellow)
- DENIED (red)

No editing from employee UI. Changes by administration only.

## Trusted Device Card (display only)

Device name, status, registered date, last used.

## Rules

Employee photos via private storage / signed URLs. No permission logic in JS.
