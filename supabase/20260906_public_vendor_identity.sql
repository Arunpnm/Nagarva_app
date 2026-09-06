-- The customer-facing pages must carry the VENDOR's name, not Nagarva's.
--
-- Arun, 6 Sept 2026, seeing his own survey link in a browser: "here the
-- top it showing nagarva but this vendor name is Arun packers and
-- couriers ... we are creating a saas product so the name should be
-- according to the vendor".
--
-- A customer of Arun Packers opens a link their mover sent and is shown
-- the name of a company they have never heard of. They cannot tell the
-- link is genuine, and the vendor looks like they are using someone
-- else's tool. Same class of defect as the hardcoded "Net to APC" in
-- New Order, in the opposite direction.
--
-- Both functions deliberately disclose very little (their own comments
-- say "No org_id, no lead_id, no phone. No pricing of any kind"), and
-- that stays true: this adds the org's PUBLIC TRADING NAME only. It is
-- the least private field the org has - it is printed on the invoice,
-- the LR and the quotation the same customer already holds - and the
-- recipient necessarily knows who they hired. No id, no GSTIN, no
-- contact details, no logo URL.
--
-- The page falls back to showing NOTHING when the field is absent, so
-- running this improves the page and skipping it never breaks it.

do $pre$
begin
  if to_regprocedure('public.public_get_survey(text)') is null
     or to_regprocedure('public.public_get_signature_request(text)') is null then
    raise exception
      'public_get_survey(text) and/or public_get_signature_request(text) are missing. Check the signatures before running this.';
  end if;
end
$pre$;

create or replace function public.public_get_survey(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v public.surveys%rowtype;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  select * into v from public.surveys where token = p_token;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if v.status is distinct from 'pending' then
    return jsonb_build_object('ok', false, 'reason', 'already_submitted');
  end if;

  if v.expires_at < now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  -- No org_id, no lead_id, no phone. No pricing of any kind.
  -- vendor_name is the org's public trading name and nothing else.
  return jsonb_build_object(
    'ok',                   true,
    'vendor_name',          (select o.name from public.organizations o
                              where o.id = v.org_id),
    'customer_name',        v.customer_name,
    'from_address',         v.from_address,
    'to_address',           v.to_address,
    'move_date',            v.move_date,
    'rooms',                coalesce(v.rooms, '[]'::jsonb),
    'special_instructions', v.special_instructions,
    'survey_cats',          public.resolve_survey_cats(v.org_id)
  );
end;
$function$;

create or replace function public.public_get_signature_request(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v public.document_signatures%rowtype;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  select * into v from public.document_signatures where sign_token = p_token;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if v.signed_at is not null or v.status is distinct from 'pending' then
    return jsonb_build_object('ok', false, 'reason', 'already_signed');
  end if;

  if v.expires_at < now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  return jsonb_build_object(
    'ok',            true,
    'vendor_name',   (select o.name from public.organizations o
                       where o.id = v.org_id),
    'customer_name', v.customer_name,
    'document_type', v.document_type,
    'document_id',   v.document_id
  );
end;
$function$;

do $post$
declare
  v_src text;
begin
  for v_src in
    select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('public_get_survey', 'public_get_signature_request')
  loop
    if v_src not like '%vendor_name%' then
      raise exception 'POSTFLIGHT: a public getter is still missing vendor_name.';
    end if;
  end loop;

  if not has_function_privilege('anon', 'public.public_get_survey(text)', 'execute')
     or not has_function_privilege('anon', 'public.public_get_signature_request(text)', 'execute') then
    raise exception 'POSTFLIGHT: anon lost execute on a public getter - the customer pages cannot call it.';
  end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('public_get_survey', 'public_get_signature_request')
       and not p.prosecdef
  ) then
    raise exception 'POSTFLIGHT: a public getter is no longer SECURITY DEFINER.';
  end if;
end
$post$;
