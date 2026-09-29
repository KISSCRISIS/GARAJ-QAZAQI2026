# Auto Device Activation Flow

## Goal

When an employee is approved by administration, the trusted device state must become active automatically. No manual activation button is required.

## Final Flow

```
Employee Registration
        |
        v
Pending Approval
        |
        v
Admin Approves Employee
        |
        +--> Employee status = APPROVED
        |
        +--> Create or activate trusted device
        |
        +--> Save device metadata
        |
        +--> Create audit record
        |
        v
Employee can use QR access
```

## Required Conditions

Before allowing access:

- Employee status must be APPROVED.
- Guard device must be active.
- QR session must be valid.
- Access rules must pass.

## Trusted Device State

Before approval:

```
Employee: PENDING
Device: WAITING
```

After approval:

```
Employee: APPROVED
Device: ACTIVE
```

## QR Access Result

Successful scan should return:

- Employee photo
- Name
- Employee number
- Department
- Specialty
- Status
- Access time
- Daily visit count

## Audit

The approval action should be recorded for traceability.

## Implementation Note

The implementation should modify the existing approval RPC/function instead of adding a separate manual activation workflow.
