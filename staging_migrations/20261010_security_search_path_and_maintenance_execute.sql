-- Staging-only hardening applied 2026-10-10.
-- Fix mutable function search_path findings and remove direct client EXECUTE
-- from maintenance/event-trigger helpers. Production is untouched.

alter function public.default_admin_permissions(text) set search_path = pg_catalog, public;
alter function public.hash_offline_device_token(text) set search_path = pg_catalog, extensions;
alter function public.hash_trusted_device_token(text) set search_path = pg_catalog, extensions;
alter function public.normalize_specialty_name(text) set search_path = pg_catalog, public;
alter function public.sync_trusted_device_activity() set search_path = pg_catalog, public;

revoke execute on function public.cleanup_expired_qr_sessions() from anon, authenticated;
revoke execute on function public.rls_auto_enable() from anon, authenticated;
