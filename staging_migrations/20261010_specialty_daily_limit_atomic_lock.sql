-- Staging-only migration applied 2026-10-10.
-- Serializes the existing specialty daily-limit check and log insert.
-- The current day-boundary rule is intentionally unchanged.

create or replace function public.manual_employee_check(
  p_employee_id text,
  p_mobile_number text,
  p_qr_token text default null::text
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
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'أدخل الرقم الوظيفي/الوطني ورقم الهاتف');
  end if;

  select * into reg
  from public.employee_registrations
  where employee_id = clean_emp and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    perform public.set_guard_status('DENIED', null, clean_emp, 'الموظف غير موجود');
    return jsonb_build_object('ok', true, 'result', 'NOT_FOUND', 'message', 'الموظف غير موجود، الرجاء التسجيل أولًا');
  end if;

  if reg.status <> 'APPROVED' then
    access_message := case when reg.status = 'PENDING' then 'طلبك قيد المراجعة' else 'تم رفض الطلب، يرجى مراجعة الإدارة' end;
    insert into public.gate_access_logs (employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason)
    values (reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'DENIED', reg.status || '_EMPLOYEE');
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, access_message);
    return jsonb_build_object(
      'ok', true, 'result', 'DENIED', 'message', access_message,
      'employee', public.employee_result_details(reg.id),
      'access', jsonb_build_object(
        'entry_time', now(),
        'daily_visits', (
          select count(*) from public.gate_access_logs gal
          where gal.employee_registration_id = reg.id
            and gal.result = 'ALLOWED'
            and gal.created_at >= date_trunc('day', now())
            and gal.created_at < date_trunc('day', now()) + interval '1 day'
        )
      )
    );
  end if;

  if nullif(reg.trusted_device_token_hash, '') is not null
     and (coalesce(reg.trusted_device_enabled, false) = false or reg.trusted_device_revoked_at is not null)
  then
    insert into public.gate_access_logs (employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason)
    values (reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'DENIED', 'TRUSTED_DEVICE_NOT_ACTIVE');
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'الجهاز الموثوق غير مفعّل');
    return jsonb_build_object(
      'ok', true, 'result', 'DENIED',
      'message', 'الجهاز الموثوق غير مفعّل، يرجى مراجعة الإدارة',
      'employee', public.employee_result_details(reg.id)
    );
  end if;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);
  if qr_ok is not true then
    perform public.set_guard_status('DENIED', null, clean_emp, 'QR غير صالح أو منتهي');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد');
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
      perform pg_advisory_xact_lock(
        hashtextextended(
          'SPECIALTY_DAILY_LIMIT:' || coalesce(reg.specialty,'') || ':' || date_trunc('day', now())::text,
          0
        )
      );

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
    elsif public.normalize_specialty_name(coalesce(reg.job_type, '')) = public.normalize_specialty_name('طبيب') then
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
  )
  values (
    reg.id, reg.employee_id, reg.mobile_number, reg.full_name,
    reg.specialty, access_result, access_reason,
    case when nullif(trim(coalesce(p_qr_token, '')), '') is null then null else p_qr_token::uuid end
  );

  perform public.set_guard_status(access_result, reg.full_name, reg.employee_id, access_message);

  return jsonb_build_object(
    'ok', true, 'result', access_result, 'message', access_message,
    'employee', public.employee_result_details(reg.id),
    'access', jsonb_build_object(
      'entry_time', now(),
      'daily_visits', (
        select count(*) from public.gate_access_logs gal
        where gal.employee_registration_id = reg.id
          and gal.result = 'ALLOWED'
          and gal.created_at >= date_trunc('day', now())
          and gal.created_at < date_trunc('day', now()) + interval '1 day'
      )
    )
  );
end;
$$;
