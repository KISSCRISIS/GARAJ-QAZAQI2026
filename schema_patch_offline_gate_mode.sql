-- =========================================================
-- Emergency Room Parking - Offline Gate Mode
-- Run after schema.sql and the existing patches.
-- Production hardening rev: batch caps, heartbeat throttle,
-- device quarantine + admin approval, retention cleanup.
-- =========================================================

create table if not exists public.gate_devices (
  id uuid primary key default gen_random_uuid(),
  device_code text not null unique,
  gate_name text,
  gate_location text,
  cache_version text,
  app_version text,
  user_agent text,
  is_active boolean not null default true,
  last_qr_at timestamptz,
  last_scan_at timestamptz,
  last_seen_at timestamptz,
  last_online_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.gate_devices
add column if not exists app_version text;

alter table public.gate_devices
add column if not exists last_qr_at timestamptz;

alter table public.gate_devices
add column if not exists last_scan_at timestamptz;

alter table public.gate_devices enable row level security;

create index if not exists idx_gate_devices_device_code
on public.gate_devices(device_code);

create index if not exists idx_gate_devices_last_seen_at
on public.gate_devices(last_seen_at desc);

-- PROD-3: admin dashboard filters active gates by recency.
create index if not exists idx_gate_devices_active
on public.gate_devices(is_active, last_seen_at desc);

create table if not exists public.offline_device_tokens (
  id uuid primary key default gen_random_uuid(),
  gate_device_id uuid not null references public.gate_devices(id) on delete cascade,
  device_code text not null,
  token_hash text not null unique,
  is_active boolean not null default true,
  last_used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.offline_device_tokens enable row level security;

create index if not exists idx_offline_device_tokens_device_code
on public.offline_device_tokens(device_code);

create table if not exists public.gate_sync_status (
  id uuid primary key default gen_random_uuid(),
  gate_device_id uuid references public.gate_devices(id) on delete cascade,
  gate_device_code text not null unique,
  pending_count integer not null default 0 check (pending_count >= 0),
  last_sync_started_at timestamptz,
  last_sync_finished_at timestamptz,
  last_sync_status text not null default 'IDLE'
    check (last_sync_status in ('IDLE', 'ONLINE', 'OFFLINE', 'SYNCING', 'SYNCED', 'FAILED')),
  last_error text,
  last_seen_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.gate_sync_status enable row level security;

create index if not exists idx_gate_sync_status_updated_at
on public.gate_sync_status(updated_at desc);

create table if not exists public.offline_access_logs (
  id uuid primary key default gen_random_uuid(),
  client_log_id text not null unique,
  gate_device_id uuid references public.gate_devices(id) on delete set null,
  gate_device_code text,
  gate_name text,
  employee_id text,
  mobile_number text,
  full_name text,
  specialty text,
  result text not null default 'DENIED'
    check (result in ('ALLOWED', 'DENIED', 'LIMITED', 'PENDING_FIRST_ENTRY', 'PENDING', 'NOT_FOUND')),
  reason text,
  qr_token text,
  offline_created_at timestamptz not null,
  synced_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.offline_access_logs enable row level security;

create index if not exists idx_offline_access_logs_synced_at
on public.offline_access_logs(synced_at desc);

create index if not exists idx_offline_access_logs_offline_created_at
on public.offline_access_logs(offline_created_at desc);

create index if not exists idx_offline_access_logs_gate_device_code
on public.offline_access_logs(gate_device_code);

create index if not exists idx_offline_access_logs_device_client
on public.offline_access_logs(gate_device_code, client_log_id);

drop policy if exists "Admins can read gate devices" on public.gate_devices;
create policy "Admins can read gate devices"
on public.gate_devices
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_view_logs'));

drop policy if exists "Admins can read offline device tokens" on public.offline_device_tokens;
create policy "Admins can read offline device tokens"
on public.offline_device_tokens
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_view_logs'));

drop policy if exists "Admins can read gate sync status" on public.gate_sync_status;
create policy "Admins can read gate sync status"
on public.gate_sync_status
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_view_logs'));

drop policy if exists "Admins can read offline access logs" on public.offline_access_logs;
create policy "Admins can read offline access logs"
on public.offline_access_logs
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_view_logs'));

grant select on public.gate_devices to authenticated;
grant select on public.offline_device_tokens to authenticated;
grant select on public.gate_sync_status to authenticated;
grant select on public.offline_access_logs to authenticated;

create or replace function public.hash_offline_device_token(p_token text)
returns text
language sql
immutable
as $$
  select encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

drop function if exists public.upsert_gate_device_heartbeat(text, text, text, text);
drop function if exists public.upsert_gate_device_heartbeat(text, text, text, text, integer);
drop function if exists public.upsert_gate_device_heartbeat(text, text, text, text, integer, text);

create or replace function public.upsert_gate_device_heartbeat(
  p_device_code text,
  p_gate_name text default null,
  p_cache_version text default null,
  p_user_agent text default null,
  p_pending_count integer default 0,
  p_device_token text default null,
  p_app_version text default null,
  p_last_qr_at timestamptz default null,
  p_last_scan_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_device_code text := trim(coalesce(p_device_code, ''));
  clean_token text := trim(coalesce(p_device_token, ''));
  clean_token_hash text;
  device_row public.gate_devices%rowtype;
  existing_row public.gate_devices%rowtype;
  has_existing_token boolean := false;
  token_is_valid boolean := false;
  total_devices integer := 0;
  recent_creations integer := 0;
  bootstrap_active boolean := false;
begin
  if clean_device_code = '' then
    return jsonb_build_object('ok', false, 'message', 'device_code is required');
  end if;

  -- PROD-1/PROD-5: load the existing row first for throttle + quarantine.
  select * into existing_row
  from public.gate_devices
  where device_code = clean_device_code
  limit 1;

  if existing_row.id is not null then
    -- Heartbeat throttle: the guard screen calls every 60s, anything
    -- faster is spam. Answer from the cached row without extra writes.
    if existing_row.last_seen_at is not null
      and existing_row.last_seen_at > now() - interval '5 seconds' then
      return jsonb_build_object(
        'ok', true,
        'device_id', existing_row.id,
        'device_code', existing_row.device_code,
        'throttled', true,
        'pending_approval', coalesce(existing_row.is_active, true) = false
      );
    end if;

    -- Quarantine: admin-disabled devices stay visible but get nothing else.
    if coalesce(existing_row.is_active, true) = false then
      update public.gate_devices
      set last_seen_at = now(),
          updated_at = now()
      where id = existing_row.id;
      return jsonb_build_object(
        'ok', false,
        'pending_approval', true,
        'message', 'الجهاز بانتظار اعتماد الإدارة'
      );
    end if;
  else
    -- PROD-5: caps against rogue auto-registration with a stolen anon key.
    select count(*) into total_devices from public.gate_devices;
    if total_devices >= 10 then
      return jsonb_build_object('ok', false, 'message', 'device limit reached, contact admin');
    end if;

    select count(*) into recent_creations
    from public.gate_devices
    where created_at > now() - interval '1 hour';
    if recent_creations >= 3 then
      return jsonb_build_object('ok', false, 'message', 'too many new devices, try later');
    end if;

    -- New gate devices remain inactive until an administrator approves them.
    bootstrap_active := false;
  end if;

  insert into public.gate_devices (
    device_code,
    gate_name,
    cache_version,
    app_version,
    user_agent,
    is_active,
    last_qr_at,
    last_scan_at,
    last_seen_at,
    last_online_at,
    updated_at
  )
  values (
    clean_device_code,
    nullif(trim(coalesce(p_gate_name, '')), ''),
    nullif(trim(coalesce(p_cache_version, '')), ''),
    nullif(trim(coalesce(p_app_version, '')), ''),
    nullif(trim(coalesce(p_user_agent, '')), ''),
    case when existing_row.id is null then bootstrap_active else true end,
    p_last_qr_at,
    p_last_scan_at,
    now(),
    now(),
    now()
  )
  on conflict (device_code)
  do update set
    gate_name = coalesce(excluded.gate_name, public.gate_devices.gate_name),
    cache_version = coalesce(excluded.cache_version, public.gate_devices.cache_version),
    app_version = coalesce(excluded.app_version, public.gate_devices.app_version),
    user_agent = coalesce(excluded.user_agent, public.gate_devices.user_agent),
    last_qr_at = coalesce(excluded.last_qr_at, public.gate_devices.last_qr_at),
    last_scan_at = coalesce(excluded.last_scan_at, public.gate_devices.last_scan_at),
    last_seen_at = now(),
    last_online_at = now(),
    updated_at = now()
  returning * into device_row;

  -- PROD-5: newly auto-registered devices are reported; quarantined ones
  -- stop here so the admin sees them before they can sync anything.
  if existing_row.id is null then
    insert into public.admin_audit_logs (
      admin_auth_user_id, action, target_table, target_id, details
    ) values (
      null, 'GATE_DEVICE_AUTO_REGISTERED', 'gate_devices', clean_device_code,
      jsonb_build_object('active', device_row.is_active)
    );

    if coalesce(device_row.is_active, true) = false then
      insert into public.gate_sync_status (
        gate_device_id, gate_device_code, pending_count,
        last_sync_status, last_error, last_seen_at, updated_at
      ) values (
        device_row.id, device_row.device_code, 0,
        'OFFLINE', 'pending admin approval', now(), now()
      )
      on conflict (gate_device_code) do nothing;
      return jsonb_build_object(
        'ok', false,
        'pending_approval', true,
        'message', 'الجهاز بانتظار اعتماد الإدارة'
      );
    end if;
  end if;

  select exists (
    select 1
    from public.offline_device_tokens
    where gate_device_id = device_row.id
      and is_active = true
      and revoked_at is null
  ) into has_existing_token;

  if clean_token <> '' then
    clean_token_hash := public.hash_offline_device_token(clean_token);

    select exists (
      select 1
      from public.offline_device_tokens
      where gate_device_id = device_row.id
        and token_hash = clean_token_hash
        and is_active = true
        and revoked_at is null
    ) into token_is_valid;

    -- PROD-1: record auth failures (audit insert throttled inside the
    -- helper so an attacker cannot flood the audit log).
    if has_existing_token and token_is_valid = false then
      update public.gate_sync_status
      set last_error = 'offline device token is invalid',
          updated_at = now()
      where gate_device_code = clean_device_code;

      perform public.log_gate_auth_failure(clean_device_code, 'heartbeat: invalid token');

      return jsonb_build_object('ok', false, 'message', 'offline device token is invalid');
    end if;

    if has_existing_token = false then
      insert into public.offline_device_tokens (
        gate_device_id,
        device_code,
        token_hash,
        last_used_at
      )
      values (
        device_row.id,
        device_row.device_code,
        clean_token_hash,
        now()
      )
      on conflict (token_hash)
      do update set last_used_at = now();
    else
      update public.offline_device_tokens
      set last_used_at = now()
      where gate_device_id = device_row.id
        and token_hash = clean_token_hash;
    end if;
  elsif has_existing_token then
    update public.gate_sync_status
    set last_error = 'offline device token is required',
        updated_at = now()
    where gate_device_code = clean_device_code;

    perform public.log_gate_auth_failure(clean_device_code, 'heartbeat: missing token');

    return jsonb_build_object('ok', false, 'message', 'offline device token is required');
  end if;

  insert into public.gate_sync_status (
    gate_device_id,
    gate_device_code,
    pending_count,
    last_sync_status,
    last_seen_at,
    updated_at
  )
  values (
    device_row.id,
    device_row.device_code,
    greatest(coalesce(p_pending_count, 0), 0),
    'ONLINE',
    now(),
    now()
  )
  on conflict (gate_device_code)
  do update set
    gate_device_id = excluded.gate_device_id,
    pending_count = excluded.pending_count,
    last_sync_status = 'ONLINE',
    last_seen_at = now(),
    updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'device_id', device_row.id,
    'device_code', device_row.device_code,
    'pending_approval', false,
    'pending_count', greatest(coalesce(p_pending_count, 0), 0)
  );
end;
$$;

drop function if exists public.sync_offline_access_logs(jsonb);
drop function if exists public.sync_offline_access_logs(text, jsonb);

create or replace function public.sync_offline_access_logs(
  p_device_code text,
  p_logs jsonb,
  p_device_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  synced_count integer := 0;
  device_id uuid;
  device_active boolean := true;
  token_is_valid boolean := false;
  batch_size integer := 0;
  payload_bytes integer := 0;
  clean_client_log_id text;
  clean_device_code text := trim(coalesce(p_device_code, ''));
  clean_token text := trim(coalesce(p_device_token, ''));
  clean_token_hash text;
  inserted_count integer := 0;
begin
  if clean_device_code = '' then
    return jsonb_build_object('ok', false, 'message', 'device_code is required');
  end if;

  if clean_token = '' then
    return jsonb_build_object('ok', false, 'message', 'offline device token is required');
  end if;

  if jsonb_typeof(p_logs) <> 'array' then
    return jsonb_build_object('ok', false, 'message', 'p_logs must be a JSON array');
  end if;

  -- PROD-2: batch + payload caps so one device cannot stall the database.
  -- Clients must split larger queues into chunks of <= 500.
  batch_size := jsonb_array_length(p_logs);
  if batch_size > 500 then
    return jsonb_build_object('ok', false, 'message', 'batch too large, max 500 logs per request');
  end if;

  payload_bytes := pg_column_size(p_logs);
  if payload_bytes > 1048576 then
    return jsonb_build_object('ok', false, 'message', 'payload too large, split into smaller batches');
  end if;

  clean_token_hash := public.hash_offline_device_token(clean_token);

  -- Device lookup separated from the token check for clearer diagnostics.
  select gd.id, gd.is_active
  into device_id, device_active
  from public.gate_devices gd
  where gd.device_code = clean_device_code
  limit 1;

  if device_id is null then
    perform public.log_gate_auth_failure(clean_device_code, 'sync: unknown device');
    return jsonb_build_object('ok', false, 'message', 'device is not authorized for offline sync');
  end if;

  if coalesce(device_active, true) = false then
    update public.gate_sync_status
    set last_error = 'pending admin approval',
        updated_at = now()
    where gate_device_code = clean_device_code;
    return jsonb_build_object('ok', false, 'pending_approval', true, 'message', 'device pending admin approval');
  end if;

  select exists (
    select 1
    from public.offline_device_tokens
    where gate_device_id = device_id
      and token_hash = clean_token_hash
      and is_active = true
      and revoked_at is null
  ) into token_is_valid;

  if not token_is_valid then
    perform public.log_gate_auth_failure(clean_device_code, 'sync: invalid token');
    update public.gate_sync_status
    set last_error = 'offline device token is invalid',
        last_sync_status = 'FAILED',
        updated_at = now()
    where gate_device_code = clean_device_code;
    return jsonb_build_object('ok', false, 'message', 'device is not authorized for offline sync');
  end if;

  update public.gate_sync_status
  set last_sync_started_at = now(),
      last_sync_status = 'SYNCING',
      last_error = null,
      updated_at = now()
  where gate_device_code = clean_device_code;

  for item in select value from jsonb_array_elements(p_logs)
  loop
    clean_client_log_id := trim(coalesce(item->>'client_log_id', ''));

    if clean_client_log_id = '' then
      continue;
    end if;

    insert into public.offline_access_logs (
      client_log_id,
      gate_device_id,
      gate_device_code,
      gate_name,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason,
      qr_token,
      offline_created_at,
      synced_at,
      payload
    )
    values (
      clean_client_log_id,
      device_id,
      clean_device_code,
      nullif(item->>'gate_name', ''),
      nullif(item->>'employee_id', ''),
      nullif(item->>'mobile_number', ''),
      nullif(item->>'full_name', ''),
      nullif(item->>'specialty', ''),
      coalesce(nullif(item->>'result', ''), 'DENIED'),
      nullif(item->>'reason', ''),
      nullif(item->>'qr_token', ''),
      coalesce((item->>'offline_created_at')::timestamptz, now()),
      now(),
      coalesce(item->'payload', '{}'::jsonb)
    )
    on conflict (client_log_id)
    do nothing;

    get diagnostics inserted_count = row_count;
    synced_count := synced_count + inserted_count;
  end loop;

  update public.offline_device_tokens
  set last_used_at = now()
  where gate_device_id = device_id
    and token_hash = clean_token_hash;

  update public.gate_sync_status
  set pending_count = 0,
      last_sync_finished_at = now(),
      last_sync_status = 'SYNCED',
      last_error = null,
      updated_at = now()
  where gate_device_code = clean_device_code;

  return jsonb_build_object('ok', true, 'synced_count', synced_count);
exception
  when others then
    update public.gate_sync_status
    set last_sync_finished_at = now(),
        last_sync_status = 'FAILED',
        last_error = sqlerrm,
        updated_at = now()
    where gate_device_code = clean_device_code;
    raise;
end;
$$;

-- =========================================================
-- PROD-1: throttled auth-failure logger (internal use only).
-- Capped at 1 audit row per device per 5 minutes so an attacker
-- cannot flood admin_audit_logs. Called from SECURITY DEFINER
-- functions, so no direct grants are given.
-- =========================================================

create or replace function public.log_gate_auth_failure(
  p_device_code text,
  p_source text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  fail_logged boolean := false;
begin
  if trim(coalesce(p_device_code, '')) = '' then
    return;
  end if;

  select exists (
    select 1 from public.admin_audit_logs
    where action = 'GATE_DEVICE_AUTH_FAILED'
      and target_id = p_device_code
      and created_at > now() - interval '5 minutes'
  ) into fail_logged;

  if not fail_logged then
    insert into public.admin_audit_logs (
      admin_auth_user_id, action, target_table, target_id, details
    ) values (
      null, 'GATE_DEVICE_AUTH_FAILED', 'gate_devices', p_device_code,
      jsonb_build_object('source', p_source)
    );
  end if;
end;
$$;

-- =========================================================
-- PROD-5: admin approval for quarantined gate devices.
-- =========================================================

create or replace function public.admin_approve_gate_device(
  p_device_code text,
  p_approve boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_code text := trim(coalesce(p_device_code, ''));
  dev_id uuid;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح');
  end if;

  if clean_code = '' then
    return jsonb_build_object('ok', false, 'message', 'device_code is required');
  end if;

  update public.gate_devices
  set is_active = coalesce(p_approve, true),
      updated_at = now()
  where device_code = clean_code
  returning id into dev_id;

  if dev_id is null then
    return jsonb_build_object('ok', false, 'message', 'device not found');
  end if;

  insert into public.admin_audit_logs (
    admin_auth_user_id, action, target_table, target_id, details
  ) values (
    auth.uid(), 'GATE_DEVICE_APPROVAL', 'gate_devices', clean_code,
    jsonb_build_object('approved', coalesce(p_approve, true))
  );

  return jsonb_build_object('ok', true, 'message', 'تم تحديث اعتماد الجهاز');
end;
$$;

-- =========================================================
-- PROD-4: retention cleanup for synced offline logs.
-- Default keeps 12 months online. Run manually or via pg_cron:
--   select cron.schedule('erp-offline-logs-retention', '0 3 1 * *',
--     $$select public.cleanup_old_offline_access_logs(12)$$);
-- =========================================================

create or replace function public.cleanup_old_offline_access_logs(
  p_retention_months integer default 12
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer := 0;
  cutoff timestamptz;
  retention integer := greatest(coalesce(p_retention_months, 12), 1);
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  cutoff := now() - (retention || ' months')::interval;

  delete from public.offline_access_logs
  where synced_at < cutoff;

  get diagnostics deleted_count = row_count;

  insert into public.admin_audit_logs (
    admin_auth_user_id, action, target_table, target_id, details
  ) values (
    auth.uid(), 'OFFLINE_LOGS_RETENTION_CLEANUP', 'offline_access_logs', null,
    jsonb_build_object('retention_months', retention, 'deleted', deleted_count)
  );

  return jsonb_build_object('ok', true, 'deleted_count', deleted_count);
end;
$$;

-- NOTE on PROD-1 (wide anon grants): heartbeat + sync MUST stay
-- executable by anon because the guard screen is open-access by design
-- (no login) and employees are unauthenticated. Real enforcement lives
-- inside the functions: offline token hash check, 5s heartbeat throttle,
-- 500-row / 1MB batch caps, device cap + creation throttle, quarantine
-- for new devices, and throttled auth-failure logging above.

grant execute on function public.hash_offline_device_token(text) to anon, authenticated;
grant execute on function public.upsert_gate_device_heartbeat(text, text, text, text, integer, text, text, timestamptz, timestamptz) to anon, authenticated;
grant execute on function public.sync_offline_access_logs(text, jsonb, text) to anon, authenticated;

revoke all on function public.log_gate_auth_failure(text, text) from public, anon, authenticated;
revoke all on function public.admin_approve_gate_device(text, boolean) from public, anon;
grant execute on function public.admin_approve_gate_device(text, boolean) to authenticated;
revoke all on function public.cleanup_old_offline_access_logs(integer) from public, anon;
grant execute on function public.cleanup_old_offline_access_logs(integer) to authenticated;

notify pgrst, 'reload schema';
