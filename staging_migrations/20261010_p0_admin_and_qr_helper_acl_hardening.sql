-- Staging-only P0 ACL hardening applied 2026-10-10.
-- Remove anonymous EXECUTE from admin-facing RPCs and retire direct browser access
-- to the internal QR consumption helper. Production is untouched.

revoke execute on function public.admin_review_employee_data_change(uuid,text,text) from anon;
revoke execute on function public.admin_update_violation_status(uuid,text) from anon;
revoke execute on function public.admin_upsert_specialty_limit(text,integer,boolean) from anon;
revoke execute on function public.current_admin_role() from anon;
revoke execute on function public.get_my_admin_profile() from anon;
revoke execute on function public.has_admin_permission(text) from anon;
revoke execute on function public.is_admin() from anon;
revoke execute on function public.is_super_admin() from anon;
revoke execute on function public.super_admin_delete_admin_profile(uuid) from anon;
revoke execute on function public.super_admin_disable_admin_profile(uuid) from anon;
revoke execute on function public.super_admin_upsert_admin_profile(text,text,text,text,boolean,jsonb) from anon;
revoke execute on function public.super_admin_upsert_admin_profile(text,text,text,boolean) from anon;

revoke execute on function public.validate_and_use_qr_token(text) from public, anon, authenticated;


-- Follow-up: PostgreSQL PUBLIC carried default EXECUTE, so revoke it explicitly
-- and restore only authenticated access for admin-facing RPCs.
revoke execute on function public.admin_review_employee_data_change(uuid,text,text) from public, anon;
revoke execute on function public.admin_update_violation_status(uuid,text) from public, anon;
revoke execute on function public.admin_upsert_specialty_limit(text,integer,boolean) from public, anon;
revoke execute on function public.current_admin_role() from public, anon;
revoke execute on function public.get_my_admin_profile() from public, anon;
revoke execute on function public.has_admin_permission(text) from public, anon;
revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.is_super_admin() from public, anon;
revoke execute on function public.super_admin_delete_admin_profile(uuid) from public, anon;
revoke execute on function public.super_admin_disable_admin_profile(uuid) from public, anon;
revoke execute on function public.super_admin_upsert_admin_profile(text,text,text,text,boolean,jsonb) from public, anon;
revoke execute on function public.super_admin_upsert_admin_profile(text,text,text,boolean) from public, anon;

grant execute on function public.admin_review_employee_data_change(uuid,text,text) to authenticated;
grant execute on function public.admin_update_violation_status(uuid,text) to authenticated;
grant execute on function public.admin_upsert_specialty_limit(text,integer,boolean) to authenticated;
grant execute on function public.current_admin_role() to authenticated;
grant execute on function public.get_my_admin_profile() to authenticated;
grant execute on function public.has_admin_permission(text) to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_super_admin() to authenticated;
grant execute on function public.super_admin_delete_admin_profile(uuid) to authenticated;
grant execute on function public.super_admin_disable_admin_profile(uuid) to authenticated;
grant execute on function public.super_admin_upsert_admin_profile(text,text,text,text,boolean,jsonb) to authenticated;
grant execute on function public.super_admin_upsert_admin_profile(text,text,text,boolean) to authenticated;
