-- ALBASHIR Gate - trusted device metadata and secure device registration
-- Run after schema_patch_auto_verify.sql.

alter table public.employee_registrations
  add column if not exists trusted_device_id text,
  add column if not exists trusted_device_type text,
  add column if not exists trusted_device_name text,
  add column if not exists trusted_device_user_agent text,
  add column if not exists trusted_device_last_activity_at timestamptz;

create index if not exists idx_employee_registrations_trusted_device_id
  on public.employee_registrations(trusted_device_id)
  where trusted_device_id is not null;

create or replace function public.sync_trusted_device_activity()
returns trigger
language plpgsql
as $$
begin
  if new.trusted_device_last_used_at is distinct from old.trusted_device_last_used_at then
    new.trusted_device_last_activity_at := new.trusted_device_last_used_at;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_trusted_device_activity on public.employee_registrations;
create trigger trg_sync_trusted_device_activity
before update on public.employee_registrations
for each row execute function public.sync_trusted_device_activity();

create or replace function public.register_trusted_device_with_metadata(
  p_employee_id text,
  p_mobile_number text,
  p_device_token text,
  p_device_id text,
  p_device_type text,
  p_device_name text,
  p_user_agent text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
  reg_id uuid;
begin
  select public.register_trusted_device(
    p_employee_id,
    p_mobile_number,
    p_device_token
  ) into result;

  if coalesce((result->>'ok')::boolean, false) = false then
    return result;
  end if;

  select id into reg_id
  from public.employee_registrations
  where employee_id = trim(coalesce(p_employee_id, ''))
    and mobile_number = trim(coalesce(p_mobile_number, ''))
  limit 1;

  update public.employee_registrations
  set trusted_device_id = nullif(trim(coalesce(p_device_id, '')), ''),
      trusted_device_type = nullif(trim(coalesce(p_device_type, '')), ''),
      trusted_device_name = nullif(trim(coalesce(p_device_name, '')), ''),
      trusted_device_user_agent = nullif(trim(coalesce(p_user_agent, '')), ''),
      trusted_device_last_activity_at = now()
  where id = reg_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  ) values (
    null,
    'TRUSTED_DEVICE_METADATA_REGISTERED',
    'employee_registrations',
    reg_id::text,
    jsonb_build_object(
      'device_id', nullif(trim(coalesce(p_device_id, '')), ''),
      'device_type', nullif(trim(coalesce(p_device_type, '')), ''),
      'device_name', nullif(trim(coalesce(p_device_name, '')), '')
    )
  );

  return result || jsonb_build_object(
    'device_id', nullif(trim(coalesce(p_device_id, '')), ''),
    'device_type', nullif(trim(coalesce(p_device_type, '')), ''),
    'device_name', nullif(trim(coalesce(p_device_name, '')), '')
  );
exception when others then
  return jsonb_build_object('ok', false, 'message', 'تعذر حفظ بيانات الجهاز الموثوق');
end;
$$;

grant execute on function public.register_trusted_device_with_metadata(text, text, text, text, text, text, text)
  to anon, authenticated;

create or replace function public.trusted_device_profile_login(p_device_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_token text := trim(coalesce(p_device_token, ''));
begin
  if length(clean_token) < 40 then
    return jsonb_build_object('ok', false, 'clear_device', true, 'message', 'رمز الجهاز غير صالح');
  end if;

  select * into reg
  from public.employee_registrations
  where trusted_device_enabled = true
    and trusted_device_token_hash = public.hash_trusted_device_token(clean_token)
    and status = 'APPROVED'
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', false, 'clear_device', true, 'message', 'الجهاز جديد أو تم إلغاء اعتماده');
  end if;

  update public.employee_registrations
  set trusted_device_last_used_at = now(), trusted_device_last_activity_at = now()
  where id = reg.id;

  insert into public.admin_audit_logs (admin_auth_user_id, action, target_table, target_id, details)
  values (null, 'TRUSTED_DEVICE_FAST_LOGIN', 'employee_registrations', reg.id::text,
    jsonb_build_object('device_id', reg.trusted_device_id, 'employee_id', reg.employee_id));

  return jsonb_build_object(
    'ok', true,
    'profile', jsonb_build_object(
      'employee_id', reg.employee_id,
      'mobile_number', reg.mobile_number,
      'full_name', reg.full_name,
      'job_type', coalesce(reg.job_type, ''),
      'department', coalesce(reg.department, ''),
      'specialty', reg.specialty,
      'status', reg.status
    )
  );
end;
$$;

grant execute on function public.trusted_device_profile_login(text) to anon, authenticated;
