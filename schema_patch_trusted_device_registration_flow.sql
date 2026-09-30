-- ALBASHIR Gate: trusted device registration flow fix
-- Apply after schema_patch_pgcrypto_schema_fix.sql.
-- Purpose:
-- 1) Capture the employee device token during first registration.
-- 2) Keep the browser token while the request is still pending.
-- 3) Enable the same device automatically when ADMIN/SUPER_ADMIN approves the employee.
-- 4) Let trusted-device QR checks return ALLOWED or LIMITED according to the existing access rules.

alter table public.employee_registrations
  add column if not exists job_type text,
  add column if not exists department text,
  add column if not exists employee_photo_url text,
  add column if not exists pending_trusted_device_token_hash text,
  add column if not exists pending_trusted_device_id text,
  add column if not exists pending_trusted_device_type text,
  add column if not exists pending_trusted_device_name text,
  add column if not exists pending_trusted_device_user_agent text,
  add column if not exists pending_trusted_device_created_at timestamptz;

create index if not exists idx_employee_registrations_pending_trusted_device_token_hash
  on public.employee_registrations(pending_trusted_device_token_hash)
  where pending_trusted_device_token_hash is not null;

create or replace function public.register_employee_request(
  p_full_name text,
  p_employee_id text,
  p_mobile_number text,
  p_specialty text,
  p_qr_token text default null,
  p_job_type text default null,
  p_department text default null,
  p_photo_url text default null,
  p_device_token text default null,
  p_device_id text default null,
  p_device_type text default null,
  p_device_name text default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  qr_ok boolean := false;
  clean_name text := trim(coalesce(p_full_name, ''));
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
  clean_specialty text := trim(coalesce(p_specialty, ''));
  clean_device_token text := trim(coalesce(p_device_token, ''));
begin
  if clean_name = '' or clean_emp = '' or clean_mobile = '' or clean_specialty = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'الرجاء تعبئة الاسم ورقم الموظف ورقم الهاتف والقسم');
  end if;

  if p_photo_url is null or trim(coalesce(p_photo_url, '')) = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'الصورة الشخصية مطلوبة');
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
  limit 1
  for update;

  if reg.id is null then
    insert into public.employee_registrations (
      full_name,
      employee_id,
      mobile_number,
      specialty,
      job_type,
      department,
      employee_photo_url,
      status,
      first_entry_used,
      first_entry_at,
      pending_trusted_device_token_hash,
      pending_trusted_device_id,
      pending_trusted_device_type,
      pending_trusted_device_name,
      pending_trusted_device_user_agent,
      pending_trusted_device_created_at
    )
    values (
      clean_name,
      clean_emp,
      clean_mobile,
      clean_specialty,
      nullif(trim(coalesce(p_job_type, '')), ''),
      nullif(trim(coalesce(p_department, '')), ''),
      trim(p_photo_url),
      'PENDING',
      false,
      null,
      case when length(clean_device_token) >= 40 then public.hash_trusted_device_token(clean_device_token) else null end,
      nullif(trim(coalesce(p_device_id, '')), ''),
      nullif(trim(coalesce(p_device_type, '')), ''),
      nullif(trim(coalesce(p_device_name, '')), ''),
      nullif(trim(coalesce(p_user_agent, '')), ''),
      case when length(clean_device_token) >= 40 then now() else null end
    )
    returning * into reg;
  else
    if reg.status = 'PENDING' then
      if length(clean_device_token) < 40
         or reg.pending_trusted_device_token_hash is null
         or reg.pending_trusted_device_token_hash <> public.hash_trusted_device_token(clean_device_token) then
        return jsonb_build_object(
          'ok', false,
          'result', 'DENIED',
          'message', 'تعذر التحقق من ملكية الطلب المعلق. استخدم الجهاز الذي أرسل الطلب أو راجع الإدارة'
        );
      end if;

      update public.employee_registrations
      set mobile_number = clean_mobile,
          specialty = clean_specialty,
          job_type = nullif(trim(coalesce(p_job_type, '')), ''),
          department = nullif(trim(coalesce(p_department, '')), ''),
          employee_photo_url = trim(p_photo_url)
      where id = reg.id
      returning * into reg;
    end if;
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason)
    values (reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'DENIED', 'REJECTED_EMPLOYEE');
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب مسبقًا');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'تم رفض الطلب، يرجى مراجعة الإدارة');
  end if;

  if reg.status = 'APPROVED' then
    return public.manual_employee_check(reg.employee_id, reg.mobile_number, p_qr_token);
  end if;

  if reg.first_entry_used = true then
    insert into public.gate_access_logs (employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason)
    values (reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'DENIED', 'PENDING_FIRST_ENTRY_ALREADY_USED');
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة — تم استخدام الدخول الأول سابقًا');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'طلبك قيد المراجعة، وتم استخدام الدخول الأول سابقًا');
  end if;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok then
    update public.employee_registrations
    set first_entry_used = true,
        first_entry_at = now()
    where id = reg.id
    returning * into reg;

    insert into public.gate_access_logs (employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason, qr_token)
    values (reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'PENDING_FIRST_ENTRY', 'FIRST_ENTRY_AFTER_REGISTRATION',
      case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end);
    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'دخول أول مرة — بانتظار موافقة الإدارة');
    return jsonb_build_object('ok', true, 'result', 'LIMITED', 'message', 'تم إرسال طلبك. تم السماح بدخول أول مرة فقط، والطلب بانتظار موافقة الإدارة');
  end if;

  return jsonb_build_object('ok', true, 'result', 'PENDING', 'message', 'تم إرسال طلبك، الرجاء انتظار موافقة الإدارة');
end;
$$;

grant execute on function public.register_employee_request(text, text, text, text, text, text, text, text, text, text, text, text, text)
  to anon, authenticated;

create or replace function public.admin_update_registration_status(
  p_registration_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
begin
  if not (public.is_super_admin() or public.has_admin_permission('can_approve_requests')) then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بالموافقة أو الرفض');
  end if;

  if p_status not in ('APPROVED', 'REJECTED') then
    return jsonb_build_object('ok', false, 'message', 'حالة غير صحيحة');
  end if;

  update public.employee_registrations
  set status = p_status,
      approved_at = case when p_status = 'APPROVED' then now() else approved_at end,
      approved_by = case when p_status = 'APPROVED' then auth.uid() else approved_by end,
      rejected_at = case when p_status = 'REJECTED' then now() else rejected_at end,
      rejected_by = case when p_status = 'REJECTED' then auth.uid() else rejected_by end,
      trusted_device_enabled = case
        when p_status = 'APPROVED' and pending_trusted_device_token_hash is not null then true
        else trusted_device_enabled
      end,
      trusted_device_token_hash = case
        when p_status = 'APPROVED' and pending_trusted_device_token_hash is not null then pending_trusted_device_token_hash
        else trusted_device_token_hash
      end,
      trusted_device_id = case when p_status = 'APPROVED' and pending_trusted_device_token_hash is not null then pending_trusted_device_id else trusted_device_id end,
      trusted_device_type = case when p_status = 'APPROVED' and pending_trusted_device_token_hash is not null then pending_trusted_device_type else trusted_device_type end,
      trusted_device_name = case when p_status = 'APPROVED' and pending_trusted_device_token_hash is not null then pending_trusted_device_name else trusted_device_name end,
      trusted_device_user_agent = case when p_status = 'APPROVED' and pending_trusted_device_token_hash is not null then pending_trusted_device_user_agent else trusted_device_user_agent end,
      trusted_device_registered_at = case
        when p_status = 'APPROVED' and pending_trusted_device_token_hash is not null then now()
        else trusted_device_registered_at
      end,
      trusted_device_revoked_at = case
        when p_status = 'APPROVED' and pending_trusted_device_token_hash is not null then null
        else trusted_device_revoked_at
      end,
      pending_trusted_device_token_hash = case when p_status = 'APPROVED' then null else pending_trusted_device_token_hash end,
      pending_trusted_device_id = case when p_status = 'APPROVED' then null else pending_trusted_device_id end,
      pending_trusted_device_type = case when p_status = 'APPROVED' then null else pending_trusted_device_type end,
      pending_trusted_device_name = case when p_status = 'APPROVED' then null else pending_trusted_device_name end,
      pending_trusted_device_user_agent = case when p_status = 'APPROVED' then null else pending_trusted_device_user_agent end,
      pending_trusted_device_created_at = case when p_status = 'APPROVED' then null else pending_trusted_device_created_at end
  where id = p_registration_id
  returning * into reg;

  insert into public.admin_audit_logs (admin_auth_user_id, action, target_table, target_id, details)
  values (auth.uid(), 'UPDATE_REGISTRATION_STATUS', 'employee_registrations', p_registration_id::text,
    jsonb_build_object('status', p_status, 'trusted_device_linked', reg.trusted_device_token_hash is not null));

  return jsonb_build_object('ok', true, 'message', 'تم تحديث الطلب');
end;
$$;

grant execute on function public.admin_update_registration_status(uuid, text) to authenticated;

create or replace function public.auto_employee_check(
  p_device_token text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  check_result jsonb;
  clean_token text := trim(coalesce(p_device_token, ''));
begin
  if length(clean_token) < 40 then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'clear_device', true, 'message', 'رمز الجهاز غير صالح. أعد التفعيل من التحقق اليدوي.');
  end if;

  select *
  into reg
  from public.employee_registrations
  where trusted_device_token_hash = public.hash_trusted_device_token(clean_token)
     or pending_trusted_device_token_hash = public.hash_trusted_device_token(clean_token)
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'clear_device', true, 'message', 'هذا الجهاز غير مربوط أو تم إلغاء ربطه. استخدم التحقق اليدوي ثم أعد التفعيل.');
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'clear_device', false, 'message', 'طلب الموظف لم يعتمد بعد');
  end if;

  if coalesce(reg.trusted_device_enabled, false) = false then
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'clear_device', false, 'message', 'الجهاز محفوظ لكنه غير مفعّل بعد');
  end if;

  check_result := public.manual_employee_check(reg.employee_id, reg.mobile_number, p_qr_token);

  if (check_result->>'ok')::boolean = true
     and coalesce(check_result->>'result', '') in ('ALLOWED', 'LIMITED') then
    update public.employee_registrations
    set trusted_device_last_used_at = now(), trusted_device_last_activity_at = now()
    where id = reg.id;
  end if;

  return check_result || jsonb_build_object(
    'employee',
    jsonb_build_object(
      'full_name', reg.full_name,
      'employee_id', reg.employee_id,
      'mobile_number', reg.mobile_number,
      'department', coalesce(reg.department, ''),
      'specialty', reg.specialty,
      'job_type', coalesce(reg.job_type, ''),
      'employee_photo_url', coalesce(reg.employee_photo_url, '')
    )
  );
end;
$$;

grant execute on function public.auto_employee_check(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
