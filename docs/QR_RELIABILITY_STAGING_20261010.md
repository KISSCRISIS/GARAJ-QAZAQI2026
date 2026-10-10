# QR Reliability | Staging | 2026-10-10

Backend migrations have been applied to Staging for sharded QR admission, server-authoritative expiry, monitoring, and credential verification before heartbeat telemetry. The live Staging frontend must be reconciled with source control before its main alias is switched. QR screen updates are being reviewed against the deployed index, not the outdated index on this branch.
