-- ALBASHIR Gate: authenticate reset_guard_screen() to the approved gate device
-- and fix a signature mismatch that silently broke the auto-reset flow.
--
-- Bug found during audit (NEW-7 / feeds into NEW-6):
-- index.html calls:
--     supabaseClient.rpc("reset_guard_screen", { p_device_code, p_device_token })
-- but the only function defined in schema.sql is reset_guard_screen() with NO
-- arguments. PostgREST cannot match a call with named parameters to a
-- zero-argument function, so every reset attempt fails. The failure is
-- swallowed client-side (console.warn only), so nothing visibly breaks — but
-- the last employee's name + employee_id keeps broadcasting on
-- guard_screen_status (readable by anyone holding the anon key, via
-- Realtime) until the NEXT QR scan overwrites it, instead of clearing after
-- ~6 seconds as the UI intends.
--
-- This migration adds the 2-argument overload the client actually calls,
-- authenticated the same way create_qr_session() is (device must be active
-- and present a valid, non-revoked offline_device_tokens entry). The
-- existing 0-argument function is left untouched for backward compatibility
-- but is no longer called by index.html.
--
-- Apply after schema_patch_gate_qr_device_auth.sql (uses
-- hash_offline_device_token() and offline_device_tokens from that layer).

create or replace function public.reset_guard_screen(
  p_device_code text,
  p_device_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_device_code text := trim(coalesce(p_device_code, ''));
  clean_token text := trim(coalesce(p_device_token, ''));
  clean_token_hash text;
  gate public.gate_devices%rowtype;
  token_ok boolean := false;
begin
  if clean_device_code = '' or clean_token = '' then
    return jsonb_build_object('ok', false, 'message', 'جهاز الحارس غير موثق');
  end if;

  select * into gate
  from public.gate_devices
  where device_code = clean_device_code
  limit 1;

  if gate.id is null or coalesce(gate.is_active, false) = false then
    perform public.log_gate_auth_failure(clean_device_code, 'reset_guard_screen: device not approved');
    return jsonb_build_object('ok', false, 'message', 'جهاز الحارس غير معتمد');
  end if;

  clean_token_hash := public.hash_offline_device_token(clean_token);

  select exists (
    select 1
    from public.offline_device_tokens
    where gate_device_id = gate.id
      and device_code = clean_device_code
      and token_hash = clean_token_hash
      and is_active = true
      and revoked_at is null
  )
  into token_ok;

  if token_ok = false then
    perform public.log_gate_auth_failure(clean_device_code, 'reset_guard_screen: invalid token');
    return jsonb_build_object('ok', false, 'message', 'رمز جهاز الحارس غير صالح');
  end if;

  update public.guard_screen_status
  set current_status = 'READY',
      employee_name = null,
      employee_id = null,
      message = 'QR جاهز للمسح',
      updated_at = now()
  where id = 1;

  update public.gate_devices
  set last_seen_at = now(),
      updated_at = now()
  where id = gate.id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.reset_guard_screen(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
