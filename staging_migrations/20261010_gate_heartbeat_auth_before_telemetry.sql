-- Staging 2026-10-10: authorize heartbeat before throttling and writes.
-- Never trust client-provided QR generation timestamps.
CREATE OR REPLACE FUNCTION public.upsert_gate_device_heartbeat(p_device_code text, p_gate_name text DEFAULT NULL::text, p_cache_version text DEFAULT NULL::text, p_user_agent text DEFAULT NULL::text, p_pending_count integer DEFAULT 0, p_device_token text DEFAULT NULL::text, p_app_version text DEFAULT NULL::text, p_last_qr_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_last_scan_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
 code text := trim(coalesce(p_device_code,''));
 secret text := trim(coalesce(p_device_token,''));
 gate public.gate_devices%rowtype;
 hash_value text;
 now_at timestamptz := clock_timestamp();
 total_devices integer;
 recent_devices integer;
begin
 if code = '' or length(code)>120 then
  return jsonb_build_object('ok',false,'error','INVALID_DEVICE_CODE');
 end if;
 select * into gate from public.gate_devices where device_code=code limit 1;
 if gate.id is null then
  select count(*) into total_devices from public.gate_devices;
  select count(*) into recent_devices from public.gate_devices
   where created_at>now_at-interval '1 hour';
  if total_devices>=10 or recent_devices>=3 then
   return jsonb_build_object('ok',false,'error','DEVICE_REGISTRATION_LIMIT');
  end if;
  insert into public.gate_devices (
    device_code,gate_name,cache_version,user_agent,app_version,is_active,
    last_seen_at,last_online_at,updated_at
  ) values (
    code,left(nullif(trim(coalesce(p_gate_name,'')),''),120),
    left(nullif(trim(coalesce(p_cache_version,'')),''),120),
    left(nullif(trim(coalesce(p_user_agent,'')),''),512),
    left(nullif(trim(coalesce(p_app_version,'')),''),120),
    false,null,null,now_at
  ) on conflict(device_code) do nothing;
  insert into public.admin_audit_logs(action,target_table,target_id,details)
    values('GATE_DEVICE_AUTO_REGISTERED','gate_devices',code,
    jsonb_build_object('active',false,'source','heartbeat'));
  return jsonb_build_object('ok',false,'pending_approval',true,
    'message','الجهاز بانتظار اعتماد الإدارة');
 end if;
 if not coalesce(gate.is_active,false) then
  return jsonb_build_object('ok',false,'pending_approval',true,
    'message','الجهاز بانتظار اعتماد الإدارة');
 end if;
 -- Validate the credential BEFORE throttling, any telemetry writes, or returning a device ID.
 if length(secret)<40 then
  perform public.log_gate_auth_failure(code,'heartbeat: missing token');
  return jsonb_build_object('ok',false,'error','AUTH_REQUIRED');
 end if;
 hash_value:=public.hash_offline_device_token(secret);
 if not exists(select 1 from public.offline_device_tokens
   where gate_device_id=gate.id and device_code=code and token_hash=hash_value
     and is_active=true and revoked_at is null) then
  perform public.log_gate_auth_failure(code,'heartbeat: invalid token');
  return jsonb_build_object('ok',false,'error','AUTH_INVALID');
 end if;
 if gate.last_seen_at is not null
   and gate.last_seen_at > now_at-interval '5 seconds' then
  return jsonb_build_object('ok',true,'device_id',gate.id,
    'device_code',gate.device_code,'throttled',true,'pending_approval',false);
 end if;
 update public.gate_devices set
  gate_name=coalesce(left(nullif(trim(coalesce(p_gate_name,'')),''),120),gate_name),
  cache_version=coalesce(left(nullif(trim(coalesce(p_cache_version,'')),''),120),cache_version),
  app_version=coalesce(left(nullif(trim(coalesce(p_app_version,'')),''),120),app_version),
  user_agent=coalesce(left(nullif(trim(coalesce(p_user_agent,'')),''),512),user_agent),
  last_scan_at=case
   when p_last_scan_at between now_at-interval '1 day' and now_at+interval '5 seconds'
   then greatest(coalesce(last_scan_at,p_last_scan_at),p_last_scan_at)
   else last_scan_at end,
  -- Never trust p_last_qr_at for emergency detection; only a successful
  -- authenticated create_qr_session() may advance last_qr_at.
  last_seen_at=now_at,last_online_at=now_at,updated_at=now_at
 where id=gate.id and is_active=true;
 update public.offline_device_tokens set last_used_at=now_at
 where gate_device_id=gate.id and device_code=code and token_hash=hash_value
 and is_active=true and revoked_at is null;
 insert into public.gate_sync_status (
  gate_device_id,gate_device_code,pending_count,last_sync_status,
  last_seen_at,updated_at
 ) values(
  gate.id,code,greatest(coalesce(p_pending_count,0),0),
  'ONLINE',now_at,now_at
 ) on conflict(gate_device_code) do update set
  gate_device_id=excluded.gate_device_id,
  pending_count=excluded.pending_count,
  last_sync_status='ONLINE',
  last_seen_at=now_at,updated_at=now_at;
 return jsonb_build_object('ok',true,'device_id',gate.id,
  'device_code',code,'pending_approval',false,
  'pending_count',greatest(coalesce(p_pending_count,0),0));
end;
$function$
;
notify pgrst,'reload schema';
