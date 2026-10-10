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
