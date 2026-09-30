-- ALBASHIR Gate: Guard device admin approval controls
-- Adds explicit admin actions for activating/deactivating guard terminals.
-- Apply after schema_patch_offline_gate_mode.sql
-- DEPRECATED: not the production canonical API. Do not apply this patch to Production.
-- Production canonical: public.admin_approve_gate_device(text, boolean).

create or replace function public.admin_set_guard_device_status(
  p_device_code text,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.gate_devices%rowtype;
begin
  if not public.is_super_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'SUPER_ADMIN permission required'
    );
  end if;

  update public.gate_devices
  set is_active = p_is_active,
      updated_at = now()
  where device_code = trim(coalesce(p_device_code, ''))
  returning * into target;

  if target.id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Guard device not found'
    );
  end if;

  insert into public.admin_audit_logs(
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  ) values (
    auth.uid(),
    case when p_is_active then 'GUARD_DEVICE_APPROVED' else 'GUARD_DEVICE_DISABLED' end,
    'gate_devices',
    target.device_code,
    jsonb_build_object('is_active', p_is_active)
  );

  return jsonb_build_object(
    'ok', true,
    'device_code', target.device_code,
    'is_active', target.is_active
  );
end;
$$;

grant execute on function public.admin_set_guard_device_status(text, boolean) to authenticated;

notify pgrst, 'reload schema';
