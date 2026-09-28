-- ALBASHIR Gate: pgcrypto schema compatibility fix for existing Supabase projects.
-- Safe to run more than once. It does not modify employee or access-log data.

begin;

create extension if not exists "pgcrypto" with schema extensions;

create or replace function public.hash_trusted_device_token(p_token text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(extensions.digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
$$;

create or replace function public.hash_offline_device_token(p_token text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

commit;

notify pgrst, 'reload schema';
