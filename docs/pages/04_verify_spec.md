# 04 verify.html — QR Result Display Only

## Flow

Camera → QR Token → Backend Validation → Audit Log → Result. Decision happens in Backend only.

## States

1. Camera Start: Scan QR Code, Open Camera.
2. Scanning: Reading QR..., Verifying...
3. Allowed (green): ALLOWED_PERMANENT + photo, name, department, position.
4. Limited (yellow): LIMITED_ALLOWED + daily limit, used, remaining.
5. Denied (red): DENIED + reason (Not Approved, Expired Permission, Invalid Account).

## Rules

Minimal info before successful verification. No limit calculation in JS. No Supabase bypass. QR single-use with claim flow.
