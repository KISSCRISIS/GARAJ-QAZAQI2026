-- Staging 2026-10-10: trusted device QR issuance with server expiry and sharded cap.
-- Requires 20261010_qr_generation_sharded_admission_metrics.sql
CREATE OR REPLACE FUNCTION public.create_qr_session(p_device_code text, p_device_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  v_code text:=trim(coalesce(p_device_code,''));
  v_secret text:=trim(coalesce(p_device_token,''));
  gate public.gate_devices%rowtype;
  v_hash text;
  v_token uuid;
  v_expires timestamptz;
  v_now timestamptz;
  v_bucket smallint;
  v_count integer;
begin
  if v_code='' or length(v_code)>120 or length(v_secret)<40 then
    return jsonb_build_object('ok',false,'error','GATE_AUTH_REQUIRED','message','جهاز الحارس غير موثق لإصدار QR');
  end if;
  select * into gate from public.gate_devices where device_code=v_code limit 1;
  if gate.id is null then
    perform public.log_gate_auth_failure(v_code,'create_qr_session: unknown device');
    return jsonb_build_object('ok',false,'error','GATE_NOT_FOUND','message','جهاز الحارس غير مسجل');
  end if;
  if not coalesce(gate.is_active,false) then
    return jsonb_build_object('ok',false,'error','GATE_NOT_APPROVED','pending_approval',true,'message','جهاز الحارس بانتظار اعتماد الإدارة');
  end if;
  v_hash:=public.hash_offline_device_token(v_secret);
  if not exists(select 1 from public.offline_device_tokens
    where gate_device_id=gate.id and device_code=v_code and token_hash=v_hash
      and is_active=true and revoked_at is null) then
    perform public.log_gate_auth_failure(v_code,'create_qr_session: invalid token');
    return jsonb_build_object('ok',false,'error','GATE_AUTH_INVALID','message','رمز جهاز الحارس غير صالح');
  end if;
  v_token:=extensions.gen_random_uuid();
  v_bucket:=((pg_catalog.hashtextextended(v_token::text,0)%16+16)%16)::smallint;
  insert into private.guard_qr_generation_minutes(minute_at,shard,issue_count)
  values(date_trunc('minute',clock_timestamp()),v_bucket,1)
  on conflict(minute_at,shard)
  do update set issue_count=private.guard_qr_generation_minutes.issue_count+1
  where private.guard_qr_generation_minutes.issue_count<250
  returning issue_count into v_count;
  if v_count is null then
    perform private.guard_qr_log_failure('RATE_LIMITED');
    return jsonb_build_object('ok',false,'error','RATE_LIMITED','retry_after_seconds',2,'message','ازدحام مؤقت في إصدار QR');
  end if;
  insert into public.qr_sessions(token,expires_at)
  values(v_token,clock_timestamp()+interval '30 seconds')
  returning expires_at into v_expires;
  v_now:=clock_timestamp();
  update public.gate_devices set
    last_qr_at=v_now,last_seen_at=v_now,last_online_at=v_now,updated_at=v_now
    where id=gate.id;
  update public.offline_device_tokens set last_used_at=v_now
    where gate_device_id=gate.id and token_hash=v_hash;
  return jsonb_build_object('ok',true,'token',v_token::text,
    'expires_at',v_expires,'server_now',v_now,
    'expires_in_seconds',greatest(0,extract(epoch from v_expires-v_now)));
exception when others then
  perform private.guard_qr_log_failure('DEVICE_DB_'||SQLSTATE);
  return jsonb_build_object('ok',false,'error','QR_GENERATION_FAILED',
     'retry_after_seconds',2,'message','تعذر توليد QR مؤقتًا');
end;
$function$
;
revoke execute on function public.create_qr_session(text,text) from public;
grant execute on function public.create_qr_session(text,text) to anon,authenticated;
notify pgrst,'reload schema';
