-- =========================================================
-- Emergency Room Parking - Employee profile fields for verify.html
-- Run after schema.sql, schema_patch_permanent_specialty.sql,
-- schema_patch_auto_verify.sql, and schema_patch_offline_gate_mode.sql.
-- =========================================================

alter table public.employee_registrations
add column if not exists job_type text;

alter table public.employee_registrations
add column if not exists department text;

alter table public.employee_registrations
add column if not exists employee_photo_url text;

create index if not exists idx_employee_registrations_job_type
on public.employee_registrations(job_type);

insert into storage.buckets (id, name, public)
values ('employee-photos', 'employee-photos', true)
on conflict (id) do update set public = true;

drop policy if exists "Anyone can upload employee photos" on storage.objects;
create policy "Anyone can upload employee photos"
on storage.objects
for insert
to anon, authenticated
with check (bucket_id = 'employee-photos');

drop policy if exists "Anyone can read employee photos" on storage.objects;
create policy "Anyone can read employee photos"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'employee-photos');

create or replace function public.employee_result_details(p_registration_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', er.id,
    'full_name', er.full_name,
    'employee_id', er.employee_id,
    'mobile_number', er.mobile_number,
    'department', coalesce(er.department, er.job_type, '-'),
    'specialty', er.specialty,
    'job_type', coalesce(er.job_type, '-'),
    'employee_type', coalesce(er.job_type, '-'),
    'classification',
      case
        when public.normalize_specialty_name(coalesce(er.job_type, '')) like '%مقيم%' then 'مقيم'
        when public.normalize_specialty_name(coalesce(er.job_type, '')) like '%تمريض%' then 'ممرض'
        when public.normalize_specialty_name(coalesce(er.specialty, '')) = public.normalize_specialty_name('طب عام') then 'طبيب عام'
        when public.normalize_specialty_name(coalesce(er.job_type, '')) like '%طبيب%'
          and public.is_permanently_allowed_specialty(er.specialty) then 'أخصائي / طوارئ'
        when public.normalize_specialty_name(coalesce(er.job_type, '')) like '%طبيب%' then 'مقيم'
        when public.normalize_specialty_name(coalesce(er.job_type, '')) like '%أمن%' then 'أمن'
        when public.normalize_specialty_name(coalesce(er.job_type, '')) like '%إداري%' then 'إداري'
        when public.normalize_specialty_name(coalesce(er.job_type, '')) like '%فني%' then 'فني'
        else coalesce(er.job_type, er.specialty, '-')
      end,
    'photo_url', er.employee_photo_url,
    'status', er.status
  )
  from public.employee_registrations er
  where er.id = p_registration_id;
$$;

drop function if exists public.register_employee_request(text, text, text, text, text);
drop function if exists public.register_employee_request(text, text, text, text, text, text, text, text);

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
  reg record;
  qr_ok boolean := false;
  clean_name text := trim(coalesce(p_full_name, ''));
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
  clean_specialty text := trim(coalesce(p_specialty, ''));
  clean_job_type text := trim(coalesce(p_job_type, ''));
  clean_department text := trim(coalesce(p_department, p_job_type, ''));
  clean_photo_url text := trim(coalesce(p_photo_url, ''));
begin
  if clean_name = '' or clean_emp = '' or clean_mobile = '' or clean_specialty = '' or clean_job_type = '' or clean_photo_url = '' then
    return jsonb_build_object(
      'ok', false,
      'result', 'DENIED',
      'message', 'الرجاء تعبئة الاسم والرقم الوظيفي/الوطني والهاتف والوظيفة والقسم/الاختصاص ورفع الصورة الشخصية'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
  limit 1;

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
      first_entry_at
    )
    values (
      clean_name,
      clean_emp,
      clean_mobile,
      clean_specialty,
      clean_job_type,
      clean_department,
      clean_photo_url,
      'PENDING',
      false,
      null
    )
    returning * into reg;
  elsif reg.status = 'PENDING' then
    update public.employee_registrations
    set full_name = clean_name,
        mobile_number = clean_mobile,
        specialty = clean_specialty,
        job_type = clean_job_type,
        department = clean_department,
        employee_photo_url = clean_photo_url
    where id = reg.id
    returning * into reg;
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'REJECTED_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب مسبقًا');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'تم رفض الطلب، يرجى مراجعة الإدارة',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  if reg.status = 'APPROVED' then
    return public.manual_employee_check(reg.employee_id, reg.mobile_number, p_qr_token);
  end if;

  if reg.first_entry_used = true then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'PENDING_FIRST_ENTRY_ALREADY_USED'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة — تم استخدام الدخول الأول سابقًا');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'طلبك قيد المراجعة، وتم استخدام الدخول الأول سابقًا',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok then
    update public.employee_registrations
    set first_entry_used = true,
        first_entry_at = now()
    where id = reg.id
    returning * into reg;

    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason,
      qr_token
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'PENDING_FIRST_ENTRY',
      'FIRST_ENTRY_AFTER_REGISTRATION',
      p_qr_token::uuid
    );

    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'دخول أول مرة — بانتظار موافقة الإدارة');

    return jsonb_build_object(
      'ok', true,
      'result', 'LIMITED',
      'message', 'تم إرسال طلبك. تم السماح بدخول أول مرة فقط، والطلب بانتظار موافقة الإدارة',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'result', 'PENDING',
    'message', 'تم إرسال طلبك، الرجاء انتظار موافقة الإدارة',
    'employee', public.employee_result_details(reg.id)
  );
end;
$$;

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
  reg record;
  qr_required boolean := false;
  qr_ok boolean := true;
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
  is_permanent boolean := false;
  access_result text := 'LIMITED';
  access_reason text := 'TEMPORARY_APPROVED_ACCESS';
  access_message text := 'مسموح بشكل مؤقت';
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'أدخل الرقم الوظيفي/الوطني ورقم الهاتف');
  end if;

  if p_qr_token is not null and length(trim(p_qr_token)) > 0 then
    qr_required := true;
    qr_ok := public.validate_and_use_qr_token(p_qr_token);
  end if;

  if qr_required and qr_ok = false then
    perform public.set_guard_status('DENIED', null, clean_emp, 'QR غير صالح أو منتهي');
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    perform public.set_guard_status('DENIED', null, clean_emp, 'الموظف غير موجود');
    return jsonb_build_object(
      'ok', true,
      'result', 'NOT_FOUND',
      'message', 'الموظف غير موجود، الرجاء التسجيل أولًا'
    );
  end if;

  if reg.status = 'PENDING' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'PENDING_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'طلبك قيد المراجعة',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'REJECTED_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'تم رفض الطلب، يرجى مراجعة الإدارة',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  is_permanent := public.is_permanently_allowed_specialty(reg.specialty);

  if is_permanent then
    access_result := 'ALLOWED';
    access_reason := 'PERMANENTLY_ALLOWED_SPECIALTY';
    access_message := 'مسموح بالدخول';
  elsif public.normalize_specialty_name(coalesce(reg.job_type, '')) = public.normalize_specialty_name('طبيب')
        and public.normalize_specialty_name(reg.specialty) not in (
          public.normalize_specialty_name('الإسعاف والطوارئ (DRS/NRS/EMT/MLT)'),
          public.normalize_specialty_name('الإسعاف والطوارئ'),
          public.normalize_specialty_name('طب عام')
        ) then
    access_result := 'LIMITED';
    access_reason := 'TEMPORARY_DOCTOR_NON_EMERGENCY';
    access_message := 'مسموح جزئيًا — طبيب من اختصاص آخر';
  end if;

  insert into public.gate_access_logs (
    employee_registration_id,
    employee_id,
    mobile_number,
    full_name,
    specialty,
    result,
    reason,
    qr_token
  )
  values (
    reg.id,
    reg.employee_id,
    reg.mobile_number,
    reg.full_name,
    reg.specialty,
    access_result,
    access_reason,
    case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
  );

  perform public.set_guard_status(access_result, reg.full_name, reg.employee_id, access_message);

  return jsonb_build_object(
    'ok', true,
    'result', access_result,
    'message', access_message,
    'employee', public.employee_result_details(reg.id)
  );
end;
$$;

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
  clean_token text := trim(coalesce(p_device_token, ''));
  qr_ok boolean := false;
begin
  if length(clean_token) < 40 then
    return jsonb_build_object(
      'ok', false,
      'result', 'DENIED',
      'clear_device', true,
      'message', 'رمز الجهاز غير صالح. أعد التفعيل من التحقق اليدوي.'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where trusted_device_enabled = true
    and trusted_device_token_hash = public.hash_trusted_device_token(clean_token)
  limit 1;

  if reg.id is null then
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'clear_device', true,
      'message', 'هذا الجهاز غير مربوط أو تم إلغاء ربطه. استخدم التحقق اليدوي ثم أعد التفعيل.'
    );
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'clear_device', true,
      'message', 'الموظف غير معتمد حاليًا',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  if p_qr_token is null or length(trim(p_qr_token)) = 0 then
    return jsonb_build_object(
      'ok', false,
      'result', 'DENIED',
      'message', 'يجب مسح QR مباشر من شاشة الحارس',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok = false then
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'QR غير صالح أو منتهي');
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  update public.employee_registrations
  set trusted_device_last_used_at = now()
  where id = reg.id;

  insert into public.gate_access_logs (
    employee_registration_id,
    employee_id,
    mobile_number,
    full_name,
    specialty,
    result,
    reason,
    qr_token
  ) values (
    reg.id,
    reg.employee_id,
    reg.mobile_number,
    reg.full_name,
    reg.specialty,
    'ALLOWED',
    'AUTO_TRUSTED_DEVICE',
    case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
  );

  perform public.set_guard_status(
    'ALLOWED',
    reg.full_name,
    reg.employee_id,
    'مسموح بالدخول — تحقق تلقائي من جهاز موثوق'
  );

  return jsonb_build_object(
    'ok', true,
    'result', 'ALLOWED',
    'message', 'مسموح بالدخول — تم التحقق تلقائيًا من الجهاز الموثوق',
    'employee', public.employee_result_details(reg.id)
  );
end;
$$;

grant execute on function public.employee_result_details(uuid) to anon, authenticated;
grant execute on function public.register_employee_request(text, text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.manual_employee_check(text, text, text) to anon, authenticated;
grant execute on function public.auto_employee_check(text, text) to anon, authenticated;

create or replace function public.get_guard_employee_result(p_employee_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
begin
  select *
  into reg
  from public.employee_registrations
  where employee_id = trim(coalesce(p_employee_id, ''))
  limit 1;

  if reg.id is null then
    return null;
  end if;

  return public.employee_result_details(reg.id);
end;
$$;

grant execute on function public.get_guard_employee_result(text) to anon, authenticated;
