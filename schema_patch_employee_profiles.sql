-- ALBASHIR Gate - employee profile and controlled data-change requests
-- Run after schema_patch_verify_employee_profile.sql.

alter table public.employee_registrations
  add column if not exists vehicle_type text,
  add column if not exists vehicle_plate text,
  add column if not exists vehicle_color text;

create table if not exists public.employee_data_change_requests (
  id uuid primary key default gen_random_uuid(),
  employee_registration_id uuid not null references public.employee_registrations(id) on delete cascade,
  requested_changes jsonb not null default '{}'::jsonb,
  reason text,
  status text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED')),
  admin_note text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.employee_data_change_requests enable row level security;
drop policy if exists "Admins can read employee change requests" on public.employee_data_change_requests;
create policy "Admins can read employee change requests"
  on public.employee_data_change_requests for select
  using (public.is_admin());
create index if not exists idx_employee_data_change_requests_employee
  on public.employee_data_change_requests(employee_registration_id);
create index if not exists idx_employee_data_change_requests_status
  on public.employee_data_change_requests(status);

create or replace function public.employee_profile_login(
  p_employee_id text,
  p_mobile_number text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_id text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
begin
  select * into reg
  from public.employee_registrations
  where employee_id = clean_id and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', false, 'message', 'الرقم الوظيفي أو الهاتف غير صحيح');
  end if;

  return jsonb_build_object(
    'ok', true,
    'profile', jsonb_build_object(
      'id', reg.id,
      'full_name', reg.full_name,
      'employee_id', reg.employee_id,
      'mobile_number', reg.mobile_number,
      'department', coalesce(reg.department, ''),
      'specialty', reg.specialty,
      'job_type', coalesce(reg.job_type, ''),
      'employee_photo_url', coalesce(reg.employee_photo_url, ''),
      'vehicle_type', coalesce(reg.vehicle_type, ''),
      'vehicle_plate', coalesce(reg.vehicle_plate, ''),
      'vehicle_color', coalesce(reg.vehicle_color, ''),
      'status', reg.status,
      'trusted_device_type', coalesce(reg.trusted_device_type, ''),
      'trusted_device_last_activity_at', reg.trusted_device_last_activity_at
    ),
    'qr_history', coalesce((
      select jsonb_agg(to_jsonb(log_row) order by log_row.created_at desc)
      from (
        select created_at, result, reason, specialty
        from public.gate_access_logs
        where employee_registration_id = reg.id
        order by created_at desc
        limit 30
      ) log_row
    ), '[]'::jsonb),
    'change_requests', coalesce((
      select jsonb_agg(to_jsonb(request_row) order by request_row.created_at desc)
      from (
        select id, requested_changes, reason, status, admin_note, created_at, reviewed_at
        from public.employee_data_change_requests
        where employee_registration_id = reg.id
        order by created_at desc
        limit 10
      ) request_row
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.employee_request_data_change(
  p_employee_id text,
  p_mobile_number text,
  p_requested_changes jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  request_id uuid;
  allowed jsonb;
begin
  select * into reg
  from public.employee_registrations
  where employee_id = trim(coalesce(p_employee_id, ''))
    and mobile_number = trim(coalesce(p_mobile_number, ''))
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', false, 'message', 'تعذر التحقق من بيانات الموظف');
  end if;

  allowed := jsonb_build_object(
    'full_name', coalesce(p_requested_changes->'full_name', 'null'::jsonb),
    'employee_id', coalesce(p_requested_changes->'employee_id', 'null'::jsonb),
    'mobile_number', coalesce(p_requested_changes->'mobile_number', 'null'::jsonb),
    'department', coalesce(p_requested_changes->'department', 'null'::jsonb),
    'specialty', coalesce(p_requested_changes->'specialty', 'null'::jsonb),
    'job_type', coalesce(p_requested_changes->'job_type', 'null'::jsonb),
    'vehicle_type', coalesce(p_requested_changes->'vehicle_type', 'null'::jsonb),
    'vehicle_plate', coalesce(p_requested_changes->'vehicle_plate', 'null'::jsonb),
    'vehicle_color', coalesce(p_requested_changes->'vehicle_color', 'null'::jsonb)
  );

  insert into public.employee_data_change_requests (employee_registration_id, requested_changes, reason)
  values (reg.id, allowed, nullif(trim(coalesce(p_reason, '')), ''))
  returning id into request_id;

  insert into public.admin_audit_logs (admin_auth_user_id, action, target_table, target_id, details)
  values (null, 'EMPLOYEE_DATA_CHANGE_REQUESTED', 'employee_registrations', reg.id::text,
    jsonb_build_object('request_id', request_id, 'employee_id', reg.employee_id));

  return jsonb_build_object('ok', true, 'request_id', request_id, 'message', 'تم إرسال طلب تغيير البيانات للمراجعة');
end;
$$;

create or replace function public.admin_review_employee_data_change(
  p_request_id uuid,
  p_status text,
  p_admin_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  req record;
  changes jsonb;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح');
  end if;
  if upper(p_status) not in ('APPROVED', 'REJECTED') then
    return jsonb_build_object('ok', false, 'message', 'حالة الطلب غير صحيحة');
  end if;

  select * into req from public.employee_data_change_requests
  where id = p_request_id and status = 'PENDING' for update;
  if req.id is null then
    return jsonb_build_object('ok', false, 'message', 'طلب التغيير غير موجود أو تمت مراجعته');
  end if;

  changes := req.requested_changes;
  if upper(p_status) = 'APPROVED' then
    update public.employee_registrations
    set full_name = coalesce(nullif(changes->>'full_name', ''), full_name),
        employee_id = coalesce(nullif(changes->>'employee_id', ''), employee_id),
        mobile_number = coalesce(nullif(changes->>'mobile_number', ''), mobile_number),
        department = coalesce(nullif(changes->>'department', ''), department),
        specialty = coalesce(nullif(changes->>'specialty', ''), specialty),
        job_type = coalesce(nullif(changes->>'job_type', ''), job_type),
        vehicle_type = coalesce(nullif(changes->>'vehicle_type', ''), vehicle_type),
        vehicle_plate = coalesce(nullif(changes->>'vehicle_plate', ''), vehicle_plate),
        vehicle_color = coalesce(nullif(changes->>'vehicle_color', ''), vehicle_color)
    where id = req.employee_registration_id;
  end if;

  update public.employee_data_change_requests
  set status = upper(p_status), admin_note = nullif(trim(coalesce(p_admin_note, '')), ''), reviewed_by = auth.uid(), reviewed_at = now()
  where id = req.id;

  insert into public.admin_audit_logs (admin_auth_user_id, action, target_table, target_id, details)
  values (auth.uid(), 'EMPLOYEE_DATA_CHANGE_REVIEWED', 'employee_data_change_requests', req.id::text,
    jsonb_build_object('status', upper(p_status), 'employee_registration_id', req.employee_registration_id));

  return jsonb_build_object('ok', true, 'message', case when upper(p_status) = 'APPROVED' then 'تم اعتماد التغيير' else 'تم رفض التغيير' end);
exception when unique_violation then
  return jsonb_build_object('ok', false, 'message', 'الرقم الوظيفي مستخدم لموظف آخر');
end;
$$;

grant execute on function public.employee_profile_login(text, text) to anon, authenticated;
grant execute on function public.employee_request_data_change(text, text, jsonb, text) to anon, authenticated;
grant execute on function public.admin_review_employee_data_change(uuid, text, text) to authenticated;
