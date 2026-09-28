# Offline Sync 10-Minute Acceptance Check

Use this checklist after applying `schema_patch_offline_gate_mode.sql` and `schema_patch_production_hardening.sql`.

## Purpose

Confirm that a 10-minute network outage does not duplicate offline logs when the gate device reconnects.

## Expected Result

- First sync returns `synced_count` equal to the number of new local logs.
- Repeating the same sync payload returns `synced_count: 0`.
- `offline_access_logs.client_log_id` remains unique.
- `gate_sync_status.pending_count` returns to `0`.
- `gate_sync_status.last_sync_status` becomes `SYNCED`.

## Manual Test Steps

1. Open the gate screen on the guard device.
2. Confirm the device appears in Admin Dashboard > Devices.
3. Disconnect the network for 10 minutes.
4. Perform several local/offline access attempts.
5. Reconnect the network.
6. Wait for sync to finish.
7. Check Admin Dashboard > Offline Sync.
8. Repeat the same local sync payload if testing through RPC.

## SQL Verification

```sql
select
  gate_device_code,
  pending_count,
  last_sync_status,
  last_sync_started_at,
  last_sync_finished_at,
  last_error
from public.gate_sync_status
order by updated_at desc
limit 10;

select
  client_log_id,
  count(*) as duplicate_count
from public.offline_access_logs
group by client_log_id
having count(*) > 1;
```

The duplicate query must return no rows.
