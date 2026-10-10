-- Staging-only migration applied 2026-10-10.
-- Purpose: allow emergency manual guard entry only when the backend itself
-- detects that QR generation has stalled on a live approved gate device.
-- This migration does not modify Production.

create or replace function private.guard_qr_generation_failure_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  live_devices integer := 0;
  healthy_devices integer := 0;
  stale_devices integer := 0;
  latest_seen timestamptz;
  latest_qr timestamptz;
begin
  select
    count(*) filter (
      where coalesce(g.is_active,false)=true
        and g.last_seen_at > now() - interval '120 seconds'
    ),
    count(*) filter (
      where coalesce(g.is_active,false)=true
        and g.last_seen_at > now() - interval '120 seconds'
        and g.last_qr_at is not null
        and g.last_qr_at > now() - interval '90 seconds'
    ),
    count(*) filter (
      where coalesce(g.is_active,false)=true
        and g.last_seen_at > now() - interval '120 seconds'
        and (
          (g.last_qr_at is null and g.created_at < now() - interval '90 seconds')
          or g.last_qr_at <= now() - interval '90 seconds'
        )
    ),
    max(g.last_seen_at),
    max(g.last_qr_at)
  into live_devices, healthy_devices, stale_devices, latest_seen, latest_qr
  from public.gate_devices g;

  if healthy_devices > 0 then
    return jsonb_build_object(
      'failed', false,
      'code', 'QR_HEALTHY',
      'live_devices', live_devices,
      'healthy_devices', healthy_devices,
      'stale_devices', stale_devices,
      'last_seen_at', latest_seen,
      'last_qr_at', latest_qr
    );
  end if;

  if stale_devices > 0 then
    return jsonb_build_object(
      'failed', true,
      'code', 'QR_GENERATION_STALLED',
      'live_devices', live_devices,
      'healthy_devices', healthy_devices,
      'stale_devices', stale_devices,
      'last_seen_at', latest_seen,
      'last_qr_at', latest_qr
    );
  end if;

  return jsonb_build_object(
    'failed', false,
    'code', 'NO_LIVE_GATE_HEARTBEAT',
    'live_devices', live_devices,
    'healthy_devices', healthy_devices,
    'stale_devices', stale_devices,
    'last_seen_at', latest_seen,
    'last_qr_at', latest_qr
  );
end;
$$;

revoke all on function private.guard_qr_generation_failure_status() from public, anon, authenticated;

create or replace function public.guard_session_status(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  g_id uuid := private.guard_session_id(p_token);
  q jsonb;
  failed boolean := false;
  configured boolean := false;
begin
  if g_id is null then
    return jsonb_build_object('ok',false,'error','AUTH_REQUIRED');
  end if;

  q := private.guard_qr_generation_failure_status();
  failed := coalesce((q->>'failed')::boolean,false);
  select enabled into configured from private.guard_emergency_settings where singleton=true;

  if not failed and coalesce(configured,false) then
    update private.guard_emergency_settings set enabled=false where singleton=true;
    configured := false;
    insert into public.admin_audit_logs(action,target_table,target_id,details)
    values(
      'GUARD_EMERGENCY_AUTO_DISABLED',
      'guard_emergency_settings',
      'true',
      jsonb_build_object('guard_id',g_id,'reason',q->>'code')
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'full_name',(select full_name from private.guard_accounts where id=g_id),
    'emergency_enabled',failed,
    'emergency_available',failed,
    'emergency_configured',coalesce(configured,false),
    'emergency_reason',q->>'code',
    'qr_generation_failed',failed,
    'qr_health',q
  );
end;
$$;

create or replace function public.guard_set_emergency(p_token text, p_enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $$
declare
  gid uuid := private.guard_session_id(p_token);
  q jsonb;
  failed boolean := false;
begin
  if gid is null then
    return jsonb_build_object('ok',false,'error','AUTH_REQUIRED');
  end if;
  if p_enabled is null then
    return jsonb_build_object('ok',false,'message','اختيار غير صالح');
  end if;

  perform 1 from private.guard_accounts where id=gid for share;
  if private.guard_session_id(p_token) is null then
    return jsonb_build_object('ok',false,'error','AUTH_REQUIRED');
  end if;

  q := private.guard_qr_generation_failure_status();
  failed := coalesce((q->>'failed')::boolean,false);

  if p_enabled and not failed then
    update private.guard_emergency_settings set enabled=false where singleton=true;
    insert into public.admin_audit_logs(action,target_table,target_id,details)
    values(
      'GUARD_EMERGENCY_ENABLE_DENIED',
      'guard_emergency_settings',
      'true',
      jsonb_build_object('guard_id',gid,'reason',q->>'code')
    );
    return jsonb_build_object(
      'ok',false,
      'error','QR_NOT_FAILED',
      'emergency_enabled',false,
      'emergency_available',false,
      'reason',q->>'code',
      'message','الدخول اليدوي لا يتاح إلا عند تعطل توليد QR الذي يرصده الخادم تلقائيًا'
    );
  end if;

  update private.guard_emergency_settings set enabled=(p_enabled and failed) where singleton=true;

  insert into public.admin_audit_logs(action,target_table,target_id,details)
  values(
    'GUARD_SET_EMERGENCY',
    'guard_emergency_settings',
    'true',
    jsonb_build_object('guard_id',gid,'enabled',(p_enabled and failed),'qr_health',q)
  );

  return jsonb_build_object(
    'ok',true,
    'emergency_enabled',(p_enabled and failed),
    'emergency_available',failed,
    'reason',q->>'code',
    'message',case
      when p_enabled and failed then 'تم تفعيل الدخول اليدوي لأن الخادم رصد تعطل توليد QR'
      else 'تم إيقاف الدخول اليدوي للطوارئ'
    end
  );
end;
$$;

create or replace function public.guard_manual_employee_entry(
  p_token text,
  p_employee_id text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  g_id uuid;
  reg public.employee_registrations%rowtype;
  q public.qr_sessions%rowtype;
  prior private.guard_manual_entries%rowtype;
  r jsonb;
  response jsonb;
  read_key text;
  health jsonb;
  qr_failed boolean := false;
  emp text:=translate(trim(coalesce(p_employee_id,'')),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789');
begin
  g_id:=private.guard_session_id(p_token);
  if g_id is null then
    return jsonb_build_object('ok',false,'error','AUTH_REQUIRED','message','سجّل دخول الحارس أولًا');
  end if;

  perform 1 from private.guard_accounts where id=g_id for share;
  if private.guard_session_id(p_token) is null then
    return jsonb_build_object('ok',false,'error','AUTH_REQUIRED');
  end if;

  if p_request_id is null or length(emp) not between 1 and 100 then
    return jsonb_build_object('ok',false,'message','أدخل الرقم الوظيفي أو الوطني');
  end if;

  perform pg_advisory_xact_lock(610100902);

  select * into prior
  from private.guard_manual_entries
  where guard_id=g_id and request_id=p_request_id;

  if prior.request_id is not null then
    if prior.employee_id<>emp then
      return jsonb_build_object('ok',false,'error','REQUEST_MISMATCH');
    end if;
    return prior.response;
  end if;

  health := private.guard_qr_generation_failure_status();
  qr_failed := coalesce((health->>'failed')::boolean,false);

  if not qr_failed then
    update private.guard_emergency_settings set enabled=false where singleton=true;
    insert into public.admin_audit_logs(action,target_table,target_id,details)
    values(
      'GUARD_MANUAL_ENTRY_DENIED_QR_HEALTHY',
      'guard_emergency_settings',
      'true',
      jsonb_build_object('guard_id',g_id,'request_id',p_request_id,'qr_health',health)
    );
    return jsonb_build_object(
      'ok',false,
      'error','QR_NOT_FAILED',
      'emergency_available',false,
      'message','الدخول اليدوي غير متاح: لا يوجد تعطل مؤكد في توليد QR'
    );
  end if;

  update private.guard_emergency_settings set enabled=true where singleton=true;

  if (select count(*) from private.guard_manual_entries where guard_id=g_id and created_at>now()-interval '1 minute')>=30 then
    return jsonb_build_object('ok',false,'message','محاولات كثيرة؛ انتظر دقيقة');
  end if;

  select * into reg
  from public.employee_registrations
  where employee_id=emp
  order by created_at desc
  limit 1;

  if reg.id is null then
    response:=jsonb_build_object(
      'ok',true,'result','DENIED',
      'message','الموظف غير موجود أو غير مصرح',
      'employee',null,'counted',false,
      'emergency_reason',health->>'code'
    );
  else
    insert into public.qr_sessions(expires_at)
    values(now()+interval '30 seconds')
    returning * into q;

    r:=public.manual_employee_check(reg.employee_id,reg.mobile_number,q.token::text);
    read_key:=encode(extensions.gen_random_bytes(32),'hex');

    insert into private.public_guard_sessions(
      qr_session_id,read_key_hash,expires_at,result,employee_registration_id,decided_at
    )
    values(
      q.id,
      encode(extensions.digest(read_key,'sha256'),'hex'),
      now()+interval '60 seconds',
      case when r->>'result' in ('ALLOWED','LIMITED') then r->>'result' else 'DENIED' end,
      reg.id,
      now()
    );

    response:=public.get_public_guard_result(read_key)
      || jsonb_build_object(
        'message',r->>'message',
        'read_key',read_key,
        'counted',(r->>'result') in ('ALLOWED','LIMITED'),
        'emergency_reason',health->>'code'
      );

    update public.gate_access_logs
    set reason='GUARD_MANUAL_EMERGENCY:'||coalesce(reason,'')
    where qr_token=q.token;
  end if;

  insert into private.guard_manual_entries(guard_id,request_id,employee_id,response)
  values(g_id,p_request_id,emp,response);

  insert into public.admin_audit_logs(admin_auth_user_id,action,target_table,target_id,details)
  values(
    null,'GUARD_MANUAL_ENTRY','employee_registrations',reg.id::text,
    jsonb_build_object(
      'guard_id',g_id,
      'request_id',p_request_id,
      'result',response->>'result',
      'counted',response->'counted',
      'qr_health',health
    )
  );

  return response;
end;
$$;

revoke all on function public.guard_session_status(text) from public;
revoke all on function public.guard_set_emergency(text,boolean) from public;
revoke all on function public.guard_manual_employee_entry(text,text,uuid) from public;

grant execute on function public.guard_session_status(text) to anon, authenticated;
grant execute on function public.guard_set_emergency(text,boolean) to anon, authenticated;
grant execute on function public.guard_manual_employee_entry(text,text,uuid) to anon, authenticated;

notify pgrst, 'reload schema';
