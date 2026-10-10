-- Staging 2026-10-10: sharded issuance and 15-minute observability.
create table if not exists private.guard_qr_generation_minutes (
 minute_at timestamptz not null,
 shard smallint not null check (shard between 0 and 15),
 issue_count integer not null default 0,
 primary key(minute_at,shard)
);
create table if not exists private.guard_qr_generation_errors (
 minute_at timestamptz not null,
 error_code text not null,
 error_count integer not null default 0,
 primary key(minute_at,error_code)
);
create index if not exists guard_public_sessions_expires_idx
 on private.public_guard_sessions(expires_at);
revoke all on private.guard_qr_generation_minutes from public,anon,authenticated;
revoke all on private.guard_qr_generation_errors from public,anon,authenticated;
alter table private.guard_qr_generation_minutes enable row level security;
alter table private.guard_qr_generation_errors enable row level security;

CREATE OR REPLACE FUNCTION public.admin_guard_qr_generation_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare recent_issued bigint; recent_errors bigint; breakdown jsonb;
begin
  if not (public.is_super_admin() or public.has_admin_permission('can_view_logs'))
  then return jsonb_build_object('ok',false,'error','AUTH_REQUIRED'); end if;
  select coalesce(sum(issue_count),0) into recent_issued
    from private.guard_qr_generation_minutes
    where minute_at >= date_trunc('minute',clock_timestamp())-interval '15 minutes';
  select coalesce(sum(error_count),0) into recent_errors
    from private.guard_qr_generation_errors
    where minute_at >= date_trunc('minute',clock_timestamp())-interval '15 minutes';
  select coalesce(jsonb_object_agg(error_code,n),'{}'::jsonb) into breakdown
  from (
    select error_code,sum(error_count)::bigint n
    from private.guard_qr_generation_errors
    where minute_at >= date_trunc('minute',clock_timestamp())-interval '15 minutes'
    group by error_code
  ) s;
  return jsonb_build_object('ok',true,'window_minutes',15,
    'issued',recent_issued,'failures',recent_errors,
    'failure_codes',breakdown,'server_now',clock_timestamp());
end;
$function$
;

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
      where expires_at < clock_timestamp()-interval '1 day'
      order by expires_at limit 100
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

CREATE OR REPLACE FUNCTION private.guard_qr_log_failure(p_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private'
AS $function$
begin
  insert into private.guard_qr_generation_errors(minute_at,error_code,error_count)
  values(date_trunc('minute',clock_timestamp()),left(coalesce(p_code,'UNKNOWN'),36),1)
  on conflict(minute_at,error_code)
  do update set error_count=private.guard_qr_generation_errors.error_count+1;
end;
$function$
;

revoke all on function private.guard_qr_log_failure(text) from public,anon,authenticated;
revoke execute on function public.create_public_guard_qr() from public;
grant execute on function public.create_public_guard_qr() to anon,authenticated;
revoke all on function public.admin_guard_qr_generation_metrics() from public,anon;
grant execute on function public.admin_guard_qr_generation_metrics() to authenticated;
notify pgrst,'reload schema';
