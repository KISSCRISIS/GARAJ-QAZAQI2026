# 02 register.html — Registration Request (NOT login)

## Flow

Type [Permanent | Temporary] → Identity → Employment → Device → Review → Pending Approval.

Status lifecycle (display only): Draft → Submitted → Pending Approval → Approved / Rejected.

## Type selection

Two cards: Permanent Employee / Temporary Employee.

## Permanent form

- Identity: photo, full_name, employee_id, phone
- Employment: job_category, department, position (Emergency Physician, Nurse, Paramedic, Radiology Technician, Laboratory Technician, Accountant, Maintenance, Security, Administration)
- Security: checkbox accuracy declaration + checkbox register trusted device

Split groups required: Employee Identity Data / Employment Data / Security Registration.

## Temporary form

Adds: national_id + medical_specialty (General Surgery, Internal Medicine, Pediatrics, ENT, Urology, Ophthalmology, Neurosurgery, Anesthesia, Radiology, Laboratory).

## Review + Pending

Review screen shows photo, name, type, department, device + Submit Registration. Pending shows large card: Registration Submitted / Pending Approval.

## Rules

No permission decision here. Registration is immutable after submit; changes via admin-approved requests only.
