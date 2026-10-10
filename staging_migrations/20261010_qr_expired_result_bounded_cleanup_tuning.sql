-- Bounded opportunistic cleanup (only sessions expired >10 minutes, up to 500 rows per cycle).
-- Safe after public result retention expires at ~6 minutes.
CREATE OR REPLACE FUNCTION public.create_public_guard_qr()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  q public.qr_sessions%rowtype;
  read_key text;
  v_shard smallint;
  v_accepted integer;
  v_server_now timestamptz;
begin
  read_key:=encode(extensions.gen_random_bytes(32),'hex');
  v_shard:=((pg_catalog.hashtextextended(read_key,0) % 16 + 16) % 16)::smallint;
  -- Sixteen row-level admission buckets avoid the single global transaction lock.
  -- Per-minute capacity: 16 * 250 = 4,000 issues; enough for 400 screens
  -- refreshing at least every 8 seconds, with no unlimited anonymous minting.
  insert into private.guard_qr_generation_minutes(minute_at,shard,issue_count)
  values(date_trunc('minute',clock_timestamp()),v_shard,1)
  on conflict(minute_at,shard)
  do update set issue_count=private.guard_qr_generation_minutes.issue_count+1
  where private.guard_qr_generation_minutes.issue_count < 250
  returning issue_count into v_accepted;
  if v_accepted is null then
    perform private.guard_qr_log_failure('RATE_LIMITED');
    return jsonb_build_object('ok',false,'error','RATE_LIMITED',
      'retry_after_seconds',2,'message','ازدحام مؤقت في إصدار QR');
  end if;

  insert into public.qr_sessions(expires_at)
  values(clock_timestamp()+interval '30 seconds') returning * into q;
  insert into private.public_guard_sessions(qr_session_id,read_key_hash)
  values(q.id,encode(extensions.digest(read_key,'sha256'),'hex'));
  v_server_now:=clock_timestamp();

  -- Bounded opportunistic cleanup, not an unbounded DELETE on every QR.
  if v_shard=0 and v_accepted % 12=0 then
    delete from private.public_guard_sessions
    where id in (
      select id from private.public_guard_sessions
      where expires_at < clock_timestamp()-interval '10 minutes'
      order by expires_at limit 500
    );
    delete from private.guard_qr_generation_minutes
    where minute_at < date_trunc('minute',clock_timestamp())-interval '1 day';
    delete from private.guard_qr_generation_errors
    where minute_at < date_trunc('minute',clock_timestamp())-interval '30 days';
  end if;
  return jsonb_build_object('ok',true,'token',q.token::text,
    'expires_at',q.expires_at,
    'server_now',v_server_now,
    'expires_in_seconds',greatest(0,extract(epoch from q.expires_at-v_server_now)),
    'read_key',read_key);
exception when others then
  perform private.guard_qr_log_failure('DB_'||SQLSTATE);
  return jsonb_build_object('ok',false,'error','QR_GENERATION_FAILED',
    'retry_after_seconds',2,
    'message','تعذر توليد QR مؤقتًا، حاول مرة أخرى');
end;
$function$
;
