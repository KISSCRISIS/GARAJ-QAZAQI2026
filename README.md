# ALBASHIR Emergency Hospital Gate

# README Final Production Version v2.3

## Master Reference Document

This document defines the approved reference for:

-   System architecture.
-   Application pages.
-   UI implementation direction.
-   Design rules.
-   Image asset rules.
-   Security principles.

------------------------------------------------------------------------

# 1. Reference Architecture

    ALBASHIR Unified Design System

            ↓

    Portal Official Visual Reference

            ↓

    Operational Pages

    index

    login

    register

    verify

    profile

    guard

    admin_dashboard

Portal is the official visual reference only.

The implementation source is:

    Design Tokens

    ↓

    Shared Components

    ↓

    Application Pages

------------------------------------------------------------------------

# 2. Technology Direction

Approved:

-   HTML5
-   CSS3
-   Vanilla JavaScript
-   Supabase Client
-   RTL Arabic First
-   Mobile First

No framework migration.

------------------------------------------------------------------------

# 3. Application Pages Specification

## portal.html

### Role

Official visual identity reference and public gateway.

### Responsibilities

-   Hospital identity presentation.
-   ALBASHIR Gate introduction.
-   Login entry points.
-   Official branding.
-   Leadership presentation.
-   System features overview.

### Contains

-   Hospital logo.
-   System title.
-   Entry options.
-   Dedication section.
-   Executive Leadership section.
-   Feature cards.

------------------------------------------------------------------------

## index.html

### Role

Guard operational screen.

### Features

-   Guard authentication/device validation.
-   QR generation.
-   Gate device heartbeat.
-   Device approval status.
-   QR lifecycle management.

### States

-   Ready.
-   Generating QR.
-   Device pending approval.
-   System unavailable.
-   Connection error.

------------------------------------------------------------------------

## login.html

### Role

Unified authentication entry.

### Features

-   Employee login.
-   Guard login.
-   Admin login.
-   Session handling.
-   Secure routing.

------------------------------------------------------------------------

## register.html

### Role

Employee registration page.

### Features

-   Employee information entry.
-   Identity data.
-   Specialty/job information.
-   Employee photo upload.
-   Trusted device registration.
-   Required confirmations.

### Confirmations

-   Device documentation confirmation.
-   Information accuracy declaration.

------------------------------------------------------------------------

## verify.html

### Role

QR verification only.

### Responsibilities

-   Camera access.
-   QR scanning.
-   Verification request.
-   Access result display.

Does not contain:

-   Employee registration.
-   Profile management.

------------------------------------------------------------------------

## profile.html

### Role

Employee personal portal.

### Features

-   Employee profile.
-   Permissions/status.
-   Trusted device information.
-   Access history.
-   Data change requests.
-   QR scanning option.

------------------------------------------------------------------------

## guard.html

### Role

Guard-focused verification interface.

### Features

-   Guard workflow.
-   Camera verification.
-   Employee result display.
-   Access decision information.

Guard does not:

-   Search employees.
-   Modify records.
-   Access employee profiles.

------------------------------------------------------------------------

## admin_dashboard.html

### Role

Administration and control center.

### Features

-   Employee management.
-   Device approvals.
-   Audit logs.
-   Security monitoring.
-   Reports.
-   System settings.

Design:

-   ALBASHIR identity.
-   Dashboard components.
-   Tables.
-   Charts.
-   Security modules.

------------------------------------------------------------------------

# 4. Shared Design Rules

All pages use:

-   Dark Medical Blue theme.
-   Premium healthcare technology style.
-   RTL Arabic First.
-   Mobile First.

Shared components:

-   Header.
-   Cards.
-   Buttons.
-   Alerts.
-   Status indicators.
-   Navigation elements.

------------------------------------------------------------------------

# 5. Portal Visual Reference

Layout:

    Header

    ↓

    Login Panel

    ↓

    Dedication Section

    ↓

    Feature Cards

    ↓

    Executive Leadership

## Dedication

Approved:

-   Independent full-width section.
-   Larger visual area.
-   Premium design.
-   Above leadership images.
-   Blue and gold identity.

## Leadership Images

Approved cards:

1.  Dr. Salah Al-Qazqi

2.  Dr. Suleiman Mohammad Abu Awad

3.  Dr. Hassan Shehadeh

Desktop:

-   Three horizontal cards.

Mobile:

-   Vertical stacked cards.

------------------------------------------------------------------------

# 6. Image Assets Specification

Separate document:

ALBASHIR_Image_Assets_Specification.md

This document is separate from:

ALBASHIR_Design_Tokens.md

Design Tokens contains:

-   Colors.
-   Fonts.
-   Spacing.
-   Components.
-   UI rules.

------------------------------------------------------------------------

## Executive Leadership Images

Source:

-   Original approved management portraits only.

Rules:

-   Use original photographs.
-   Do not modify faces.
-   Do not replace images with AI-generated faces.
-   Do not reconstruct identities.
-   Do not alter facial characteristics.

Allowed:

-   Crop.
-   Resize.
-   Alignment.
-   Placement.

Usage:

-   Executive cards.
-   Portal leadership area.
-   Official presentations.

------------------------------------------------------------------------

## Logo and Identity Images

Assets:

-   Main Logo.
-   Favicon.
-   Apple Touch Icon.
-   PWA Icons.

Rules:

-   Maintain official proportions.
-   Do not redraw logo.
-   Do not alter identity colors.
-   Use correct formats.

------------------------------------------------------------------------

## Portal Images

Includes:

-   Background images.
-   Hospital images.
-   Decorative graphics.
-   Feature illustrations.

Rules:

-   Preserve hospital identity.
-   Maintain quality.
-   Optimize file size without visible degradation.

------------------------------------------------------------------------

## Employee Images

Usage:

-   Registration photo.
-   Employee profile photo.
-   Verification display.

Rules:

-   Protect privacy.
-   Avoid public exposure.
-   Use secure storage.
-   Use signed URLs where required.

------------------------------------------------------------------------

# 7. Security Principles

Decision order:

    Employee Status

    ↓

    Trusted Device

    ↓

    QR Validation + Consume

    ↓

    Specialty Rules

    ↓

    Daily Limits

The system decides access.

The guard receives the result only.

------------------------------------------------------------------------

# 8. QR Security Model

QR is not a public fallback.

Requirements:

-   Approved gate device.
-   Heartbeat validation.
-   Approved status.

Failure:

-   Keep last valid QR while valid.
-   Retry safely.
-   Show unavailable state.
-   Never generate unverified QR.

------------------------------------------------------------------------

# 9. Trusted Device Model

Includes:

-   Secure token handling.
-   Device metadata.
-   Approval lifecycle.
-   Revocation capability.

------------------------------------------------------------------------

# 10. Documentation Structure

Recommended repository documentation:

    README.md

    ALBASHIR_Master_Final_Specification_v5.md

    ALBASHIR_Design_Tokens.md

    ALBASHIR_Image_Assets_Specification.md

    ALBASHIR_Frontend_Security_Audit.md

    Supabase_Production_Database_Audit.md

------------------------------------------------------------------------

# 11. Final Status

Confirmed:

-   Architecture.
-   UI direction.
-   Visual references.
-   Image rules.
-   Security principles.
-   Decision model.

Pending Verification:

-   Only items explicitly marked during audits.
