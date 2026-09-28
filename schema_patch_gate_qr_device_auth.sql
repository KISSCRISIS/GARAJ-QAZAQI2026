-- ALBASHIR Gate: require trusted guard device authentication before issuing QR.
-- Apply after schema_patch_offline_gate_mode.sql and schema_patch_pgcrypto_schema_fix.sql.

create or replace function public.create_qr_session(
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
  new_token uuid;
begin
  if clean_device_code = '' or clean_token = '' then
    return jsonb_build_object(
      'ok', false,
      'message', 'جهاز الحارس غير موثق لإصدار QR'
    );
  end if;

  select *
  into gate
  from public.gate_devices
  where device_code = clean_device_code
  limit 1;

  if gate.id is null then
    perform public.log_gate_auth_failure(clean_device_code, 'create_qr_session: unknown device');
    return jsonb_build_object(
      'ok', false,
      'message', 'جهاز الحارس غير مسجل'
    );
  end if;

  if coalesce(gate.is_active, false) = false then
    perform public.log_gate_auth_failure(clean_device_code, 'create_qr_session: inactive device');
    return jsonb_build_object(
      'ok', false,
      'pending_approval', true,
      'message', 'جهاز الحارس بانتظار اعتماد الإدارة'
    );
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
    perform public.log_gate_auth_failure(clean_device_code, 'create_qr_session: invalid token');
    return jsonb_build_object(
      'ok', false,
      'message', 'رمز جهاز الحارس غير صالح'
    );
  end if;

  insert into public.qr_sessions (expires_at)
  values (now() + interval '30 seconds')
  returning token into new_token;

  update public.gate_devices
  set last_qr_at = now(),
      last_seen_at = now(),
      last_online_at = now(),
      updated_at = now()
  where id = gate.id;

  update public.offline_device_tokens
  set last_used_at = now()
  where gate_device_id = gate.id
    and token_hash = clean_token_hash;

  return jsonb_build_object(
    'ok', true,
    'token', new_token::text,
    'expires_in_seconds', 30
  );
end;
$$;

grant execute on function public.create_qr_session(text, text) to anon, authenticated;

-- Replace the old no-argument function so anon-key-only callers cannot mint QR sessions.
create or replace function public.create_qr_session()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'ok', false,
    'message', 'QR requires a trusted guard device'
  );
end;
$$;

grant execute on function public.create_qr_session() to anon, authenticated;

notify pgrst, 'reload schema';
