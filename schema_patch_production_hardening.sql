-- ALBASHIR Gate - production hardening
-- Run LAST, after schema.sql and every schema_patch_*.sql file listed in README.md.

create table if not exists public.hospital_settings (
  setting_key text primary key,
  setting_value jsonb not null,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table public.hospital_settings enable row level security;
drop policy if exists "Anyone can read hospital settings" on public.hospital_settings;
create policy "Anyone can read hospital settings"
  on public.hospital_settings for select to anon, authenticated using (true);
drop policy if exists "Super admin can insert hospital settings" on public.hospital_settings;
create policy "Super admin can insert hospital settings"
  on public.hospital_settings for insert to authenticated
  with check (public.is_super_admin());
drop policy if exists "Super admin can update hospital settings" on public.hospital_settings;
create policy "Super admin can update hospital settings"
  on public.hospital_settings for update to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());
grant select on public.hospital_settings to anon, authenticated;
grant insert, update on public.hospital_settings to authenticated;

create index if not exists idx_gate_access_logs_specialty_created_at
on public.gate_access_logs(specialty, created_at desc);

create index if not exists idx_employee_registrations_employee_mobile
on public.employee_registrations(employee_id, mobile_number);

alter table if exists public.gate_devices
add column if not exists last_qr_at timestamptz;

alter table if exists public.gate_devices
add column if not exists last_scan_at timestamptz;

alter table if exists public.gate_devices
add column if not exists app_version text;

create or replace function public.cleanup_expired_qr_sessions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer := 0;
begin
  delete from public.qr_sessions
  where expires_at < now() - interval '10 minutes';

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

create or replace function public.create_qr_session()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_token uuid;
begin
  insert into public.qr_sessions (expires_at)
  values (now() + interval '30 seconds')
  returning token into new_token;

  return jsonb_build_object(
    'ok', true,
    'token', new_token::text,
    'expires_in_seconds', 30
  );
end;
$$;

grant execute on function public.cleanup_expired_qr_sessions() to authenticated;

drop policy if exists "Anyone can upload violation photos" on storage.objects;
drop policy if exists "Gate can upload violation photos" on storage.objects;
create policy "Gate can upload violation photos"
on storage.objects
for insert
to anon, authenticated
with check (
  bucket_id = 'violation-photos'
  and (storage.foldername(name))[1] = 'violations'
  and lower(coalesce(metadata->>'mimetype', '')) in ('image/jpeg', 'image/png', 'image/webp')
  and coalesce((metadata->>'size')::bigint, 0) <= 5242880
);

-- Internal helper: callers must use a verification RPC, never write the guard state directly.
revoke all on function public.set_guard_status(text, text, text, text) from public, anon, authenticated;

-- Consume the original QR or its five-minute claim atomically.
create or replace function public.claim_qr_session(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  token_uuid uuid;
  new_claim uuid := gen_random_uuid();
  claimed_id uuid;
begin
  begin
    token_uuid := nullif(trim(coalesce(p_token, '')), '')::uuid;
  exception when others then
    return jsonb_build_object('ok', false, 'message', 'QR غير صحيح');
  end;

  update public.qr_sessions
  set used_at = now(),
      claimed_at = now(),
      claim_token = new_claim,
      claim_expires_at = now() + interval '5 minutes',
      claim_used_at = null
  where token = token_uuid
    and used_at is null
    and expires_at > now()
  returning id into claimed_id;

  if claimed_id is null then
    return jsonb_build_object('ok', false, 'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد من شاشة الحارس');
  end if;

  return jsonb_build_object(
    'ok', true,
    'claim_token', new_claim::text,
    'expires_in_seconds', 300,
    'message', 'تم تفعيل جلسة QR، أكمل البيانات خلال 5 دقائق'
  );
end;
$$;

create or replace function public.validate_and_use_qr_token(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  input_uuid uuid;
  consumed_id uuid;
begin
  begin
    input_uuid := nullif(trim(coalesce(p_token, '')), '')::uuid;
  exception when others then
    return false;
  end;

  update public.qr_sessions
  set used_at = now()
  where token = input_uuid
    and used_at is null
    and expires_at > now()
  returning id into consumed_id;

  if consumed_id is not null then
    return true;
  end if;

  update public.qr_sessions
  set claim_used_at = now()
  where claim_token = input_uuid
    and claim_used_at is null
    and claim_expires_at > now()
  returning id into consumed_id;

  return consumed_id is not null;
end;
$$;

-- A registration is immutable after its first submission. Identity changes use
-- employee_data_change_requests and require an administrator decision.
create or replace function public.register_employee_request(
  p_full_name text,
  p_employee_id text,
  p_mobile_number text,
  p_specialty text,
  p_qr_token text default null,
  p_job_type text default null,
  p_department text default null,
  p_photo_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg public.employee_registrations%rowtype;
  qr_ok boolean := false;
  clean_name text := trim(coalesce(p_full_name, ''));
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
  clean_specialty text := trim(coalesce(p_specialty, ''));
  clean_job_type text := trim(coalesce(p_job_type, ''));
  clean_department text := trim(coalesce(p_department, p_job_type, ''));
  clean_photo_url text := trim(coalesce(p_photo_url, ''));
begin
  if clean_name = '' or clean_emp = '' or clean_mobile = '' or clean_specialty = ''
     or clean_job_type = '' or clean_department = '' or clean_photo_url = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED',
      'message', 'جميع البيانات والصورة الشخصية مطلوبة');
  end if;

  select * into reg
  from public.employee_registrations
  where employee_id = clean_emp
  limit 1;

  if reg.id is not null then
    return jsonb_build_object(
      'ok', false,
      'result', case when reg.status = 'REJECTED' then 'DENIED' else reg.status end,
      'message', case
        when reg.status = 'PENDING' then 'الطلب مسجل وقيد مراجعة الإدارة. لا يمكن تعديل بيانات الهوية من نموذج التسجيل.'
        when reg.status = 'APPROVED' then 'الموظف مسجل ومعتمد. استخدم تسجيل الدخول أو التحقق.'
        else 'الطلب مرفوض. راجع الإدارة.'
      end
    );
  end if;

  insert into public.employee_registrations (
    full_name, employee_id, mobile_number, specialty, job_type, department,
    employee_photo_url, status, first_entry_used, first_entry_at
  ) values (
    clean_name, clean_emp, clean_mobile, clean_specialty, clean_job_type,
    clean_department, clean_photo_url, 'PENDING', false, null
  ) returning * into reg;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);
  if qr_ok then
    update public.employee_registrations
    set first_entry_used = true, first_entry_at = now()
    where id = reg.id;

    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name,
      specialty, result, reason, qr_token
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name,
      reg.specialty, 'PENDING_FIRST_ENTRY', 'FIRST_ENTRY_AFTER_REGISTRATION',
      p_qr_token::uuid
    );
    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id,
      'دخول أول مرة — بانتظار موافقة الإدارة');
    return jsonb_build_object('ok', true, 'result', 'LIMITED',
      'message', 'تم إرسال الطلب والسماح بدخول أول مرة فقط',
      'employee', public.employee_result_details(reg.id));
  end if;

  return jsonb_build_object('ok', true, 'result', 'PENDING',
    'message', 'تم إرسال الطلب، الرجاء انتظار موافقة الإدارة',
    'employee', public.employee_result_details(reg.id));
end;
$$;

-- Keep the approved-access decision and specialty daily limits in one function.
create or replace function public.manual_employee_check(
  p_employee_id text,
  p_mobile_number text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg public.employee_registrations%rowtype;
  lim public.specialty_daily_limits%rowtype;
  used_count integer := 0;
  qr_ok boolean := true;
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
  access_result text;
  access_reason text;
  access_message text;
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED',
      'message', 'أدخل الرقم الوظيفي/الوطني ورقم الهاتف');
  end if;

  select * into reg
  from public.employee_registrations
  where employee_id = clean_emp and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    perform public.set_guard_status('DENIED', null, clean_emp, 'الموظف غير موجود');
    return jsonb_build_object('ok', true, 'result', 'NOT_FOUND',
      'message', 'الموظف غير موجود، الرجاء التسجيل أولًا');
  end if;

  if reg.status <> 'APPROVED' then
    access_message := case when reg.status = 'PENDING'
      then 'طلبك قيد المراجعة' else 'تم رفض الطلب، يرجى مراجعة الإدارة' end;
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name,
      specialty, result, reason
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name,
      reg.specialty, 'DENIED', reg.status || '_EMPLOYEE'
    );
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, access_message);
    return jsonb_build_object('ok', true, 'result', 'DENIED',
      'message', access_message, 'employee', public.employee_result_details(reg.id));
  end if;

  -- Reject a linked device that was disabled or revoked before consuming the
  -- QR. A row without a linked token remains eligible for the existing manual
  -- bootstrap flow. Exact token ownership is validated by auto_employee_check.
  if nullif(reg.trusted_device_token_hash, '') is not null
     and (
       coalesce(reg.trusted_device_enabled, false) = false
       or reg.trusted_device_revoked_at is not null
     ) then
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name,
      specialty, result, reason
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name,
      reg.specialty, 'DENIED', 'TRUSTED_DEVICE_NOT_ACTIVE'
    );
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id,
      'الجهاز الموثوق غير مفعّل');
    return jsonb_build_object('ok', true, 'result', 'DENIED',
      'message', 'الجهاز الموثوق غير مفعّل، يرجى مراجعة الإدارة',
      'employee', public.employee_result_details(reg.id));
  end if;

  if nullif(trim(coalesce(p_qr_token, '')), '') is not null then
    qr_ok := public.validate_and_use_qr_token(p_qr_token);
    if not qr_ok then
      perform public.set_guard_status('DENIED', null, clean_emp, 'QR غير صالح أو منتهي');
      return jsonb_build_object('ok', true, 'result', 'DENIED',
        'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد');
    end if;
  end if;

  if public.is_permanently_allowed_specialty(reg.specialty) then
    access_result := 'ALLOWED';
    access_reason := 'PERMANENTLY_ALLOWED_SPECIALTY';
    access_message := 'مسموح بالدخول';
  else
    select * into lim
    from public.specialty_daily_limits
    where specialty_name = reg.specialty and is_active = true
    limit 1;

    if lim.id is not null then
      select count(*) into used_count
      from public.gate_access_logs
      where specialty = reg.specialty
        and result = 'LIMITED'
        and created_at >= date_trunc('day', now())
        and created_at < date_trunc('day', now()) + interval '1 day';

      if used_count >= lim.daily_limit then
        access_result := 'DENIED';
        access_reason := 'SPECIALTY_DAILY_LIMIT_REACHED';
        access_message := 'غير مسموح — تم الوصول للحد اليومي لهذا الاختصاص';
      else
        access_result := 'LIMITED';
        access_reason := 'SPECIALTY_LIMITED_ACCESS';
        access_message := 'مسموح بشكل مؤقت';
      end if;
    elsif public.normalize_specialty_name(coalesce(reg.job_type, '')) =
          public.normalize_specialty_name('طبيب') then
      access_result := 'LIMITED';
      access_reason := 'TEMPORARY_DOCTOR_NON_EMERGENCY';
      access_message := 'مسموح جزئيًا — طبيب من اختصاص آخر';
    else
      access_result := 'LIMITED';
      access_reason := 'TEMPORARY_APPROVED_ACCESS';
      access_message := 'مسموح بشكل مؤقت';
    end if;
  end if;

  insert into public.gate_access_logs (
    employee_registration_id, employee_id, mobile_number, full_name,
    specialty, result, reason, qr_token
  ) values (
    reg.id, reg.employee_id, reg.mobile_number, reg.full_name,
    reg.specialty, access_result, access_reason,
    case when nullif(trim(coalesce(p_qr_token, '')), '') is null
      then null else p_qr_token::uuid end
  );
  perform public.set_guard_status(access_result, reg.full_name, reg.employee_id, access_message);

  return jsonb_build_object('ok', true, 'result', access_result,
    'message', access_message, 'employee', public.employee_result_details(reg.id));
end;
$$;

-- Guard display result: never expose the phone credential.
create or replace function public.get_guard_employee_result(p_employee_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg public.employee_registrations%rowtype;
  result jsonb;
begin
  select * into reg from public.employee_registrations
  where employee_id = trim(coalesce(p_employee_id, ''))
  limit 1;
  if reg.id is null then return null; end if;
  result := public.employee_result_details(reg.id);
  return result - 'mobile_number';
end;
$$;

-- Existing trusted device cannot be silently replaced. Admin must revoke it first.
create or replace function public.register_trusted_device(
  p_employee_id text,
  p_mobile_number text,
  p_device_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg public.employee_registrations%rowtype;
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
  clean_token text := trim(coalesce(p_device_token, ''));
  token_hash text;
begin
  if clean_emp = '' or clean_mobile = '' or length(clean_token) < 40 then
    return jsonb_build_object('ok', false, 'message', 'بيانات تفعيل الجهاز غير مكتملة');
  end if;

  select * into reg from public.employee_registrations
  where employee_id = clean_emp and mobile_number = clean_mobile
  limit 1;

  if reg.id is null or reg.status <> 'APPROVED'
     or not coalesce(reg.trusted_device_enabled, false)
     or not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object('ok', false, 'message', 'الجهاز غير مؤهل للربط');
  end if;

  token_hash := public.hash_trusted_device_token(clean_token);
  if reg.trusted_device_token_hash is not null
     and reg.trusted_device_token_hash <> token_hash then
    return jsonb_build_object('ok', false, 'new_device', true,
      'message', 'تم اكتشاف جهاز جديد. يجب أن تلغي الإدارة ربط الجهاز السابق أولًا.');
  end if;

  update public.employee_registrations
  set trusted_device_token_hash = token_hash,
      trusted_device_registered_at = coalesce(trusted_device_registered_at, now()),
      trusted_device_revoked_at = null
  where id = reg.id;

  insert into public.admin_audit_logs (
    admin_auth_user_id, action, target_table, target_id, details
  ) values (
    null, 'TRUSTED_DEVICE_LINKED_BY_EMPLOYEE', 'employee_registrations',
    reg.id::text, jsonb_build_object('employee_id', reg.employee_id)
  );
  return jsonb_build_object('ok', true, 'message', 'تم ربط هذا الجهاز بنجاح');
end;
$$;

-- Enforce detailed administrator permissions in the database.
create or replace function public.admin_can_approve_requests()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin()
    or public.has_admin_permission('can_approve_requests');
$$;

-- The two existing administrative functions keep their signatures; inject a
-- mandatory permission check through wrappers by renaming their implementations.
do $$
begin
  if to_regprocedure('public.admin_review_employee_data_change_impl(uuid,text,text)') is null then
    alter function public.admin_review_employee_data_change(uuid,text,text)
      rename to admin_review_employee_data_change_impl;
  end if;
  if to_regprocedure('public.admin_set_trusted_device_impl(uuid,boolean,boolean)') is null then
    alter function public.admin_set_trusted_device(uuid,boolean,boolean)
      rename to admin_set_trusted_device_impl;
  end if;
end
$$;

create or replace function public.admin_review_employee_data_change(
  p_request_id uuid, p_status text, p_admin_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.admin_can_approve_requests() then
    return jsonb_build_object('ok', false, 'message', 'لا تملك صلاحية مراجعة الطلبات');
  end if;
  return public.admin_review_employee_data_change_impl(p_request_id, p_status, p_admin_note);
end;
$$;

create or replace function public.admin_set_trusted_device(
  p_registration_id uuid, p_enabled boolean, p_revoke boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.admin_can_approve_requests() then
    return jsonb_build_object('ok', false, 'message', 'لا تملك صلاحية إدارة الأجهزة');
  end if;
  return public.admin_set_trusted_device_impl(p_registration_id, p_enabled, p_revoke);
end;
$$;

revoke all on function public.admin_review_employee_data_change_impl(uuid,text,text) from public, anon, authenticated;
revoke all on function public.admin_set_trusted_device_impl(uuid,boolean,boolean) from public, anon, authenticated;
revoke all on function public.admin_can_approve_requests() from public, anon, authenticated;
grant execute on function public.claim_qr_session(text) to anon, authenticated;
grant execute on function public.validate_and_use_qr_token(text) to anon, authenticated;
grant execute on function public.register_employee_request(text,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.manual_employee_check(text,text,text) to anon, authenticated;
grant execute on function public.get_guard_employee_result(text) to anon, authenticated;
grant execute on function public.register_trusted_device(text,text,text) to anon, authenticated;
grant execute on function public.admin_review_employee_data_change(uuid,text,text) to authenticated;
grant execute on function public.admin_set_trusted_device(uuid,boolean,boolean) to authenticated;

notify pgrst, 'reload schema';
