-- ============================================================
-- 20261114_survey_edit.sql  (14 Nov 2026)
--
-- Batch 2, list items 3 and 4 (Arun, 13 Nov 2026): "After customer fill
-- the form ... shall we make him download a copy? ... if he missed and
-- wants to update again what he will do?"
--
--  * Opening a survey link AFTER sending now shows what was sent (items,
--    counts, note) instead of "already submitted", so the customer can
--    read it and download a copy.
--  * Until the vendor starts a quotation on that lead, the customer can
--    change the list from the same link and send it again. The vendor
--    gets a "Survey updated" alert each time.
--  * Once a quotation exists the list is locked; the page says to call
--    the movers. The vendor can still send a fresh link from the app.
--
-- The 14-day link expiry still applies to the first send. A change after
-- sending is allowed while the link is within 30 days of being made.
--
-- Run once in the Supabase SQL editor. Nothing is deleted.
-- ============================================================

begin;

-- Can this submitted survey still be changed by the customer?
create or replace function public.survey_editable(p_survey public.customer_surveys)
returns boolean language sql stable security definer set search_path = public as $$
  select p_survey.status = 'submitted'
     and p_survey.created_at > now() - interval '30 days'
     and not exists (
       select 1 from public.quotations q
        where q.org_id = p_survey.org_id
          and q.deleted_at is null
          and p_survey.lead_id is not null
          and q.lead_id = p_survey.lead_id
     );
$$;
revoke all on function public.survey_editable(public.customer_surveys) from public, anon, authenticated;

create or replace function public.public_get_survey_impl(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v public.customer_surveys%rowtype;
  v_edit boolean;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  select * into v from public.customer_surveys where token = p_token;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if v.status = 'pending' and v.expires_at < now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  v_edit := case when v.status = 'submitted' then public.survey_editable(v) else true end;

  -- No org_id, no lead_id, no phone. No pricing of any kind.
  return jsonb_build_object(
    'ok',                   true,
    'submitted',            v.status = 'submitted',
    'submitted_at',         v.submitted_at,
    'editable',             v_edit,
    'vendor_name',          (select o.name from public.organizations o where o.id = v.org_id),
    'vendor_phone',         (select o.phone from public.organizations o where o.id = v.org_id),
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

-- The submit: unchanged checks (copied from the live function), and a
-- second send is accepted while survey_editable says so.
create or replace function public.public_submit_survey_impl(p_token text, p_rooms jsonb, p_instructions text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_id      uuid;
  v_el      jsonb;
  v_i       integer := 0;
  v_key     text;
  v_bad     text;
  v_row     public.customer_surveys%rowtype;
  v_again   boolean := false;
  c_qty_max  constant integer := 99;
  c_cft_max  constant numeric := 100000;
  c_str_max  constant integer := 200;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if p_rooms is null or jsonb_typeof(p_rooms) <> 'array' then
    return jsonb_build_object('ok', false, 'reason', 'bad_payload',
                              'detail', 'p_rooms is not a JSON array');
  end if;
  if jsonb_array_length(p_rooms) > 150 then
    return jsonb_build_object('ok', false, 'reason', 'too_large');
  end if;

  for v_el in select value from jsonb_array_elements(p_rooms)
  loop
    v_i := v_i + 1;
    if jsonb_typeof(v_el) <> 'object' then
      return jsonb_build_object('ok', false, 'reason', 'bad_payload',
        'detail', format('element %s is %s, expected an object', v_i, jsonb_typeof(v_el)));
    end if;
    v_bad := null;
    for v_key in select jsonb_object_keys(v_el)
    loop
      if v_key not in ('cat', 'item', 'sub', 'cft', 'qty') then
        v_bad := v_key;
        exit;
      end if;
    end loop;
    if v_bad is not null then
      return jsonb_build_object('ok', false, 'reason', 'bad_payload',
        'detail', format('element %s has unexpected key %L; expected exactly cat,item,sub,cft,qty', v_i, v_bad));
    end if;
    foreach v_key in array array['cat', 'item', 'sub']
    loop
      if jsonb_typeof(v_el -> v_key) is distinct from 'string' then
        return jsonb_build_object('ok', false, 'reason', 'bad_payload',
          'detail', format('element %s: %s must be a string, got %s',
                           v_i, v_key, coalesce(jsonb_typeof(v_el -> v_key), 'missing')));
      end if;
      if length(v_el ->> v_key) = 0 or length(v_el ->> v_key) > c_str_max then
        return jsonb_build_object('ok', false, 'reason', 'bad_payload',
          'detail', format('element %s: %s must be 1..%s characters', v_i, v_key, c_str_max));
      end if;
    end loop;
    foreach v_key in array array['cft', 'qty']
    loop
      if jsonb_typeof(v_el -> v_key) is distinct from 'number' then
        return jsonb_build_object('ok', false, 'reason', 'bad_payload',
          'detail', format('element %s: %s must be a number, got %s',
                           v_i, v_key, coalesce(jsonb_typeof(v_el -> v_key), 'missing')));
      end if;
    end loop;
    if (v_el ->> 'qty')::numeric <> trunc((v_el ->> 'qty')::numeric)
       or (v_el ->> 'qty')::numeric < 1
       or (v_el ->> 'qty')::numeric > c_qty_max then
      return jsonb_build_object('ok', false, 'reason', 'bad_payload',
        'detail', format('element %s: qty must be a whole number 1..%s', v_i, c_qty_max));
    end if;
    if (v_el ->> 'cft')::numeric < 0 or (v_el ->> 'cft')::numeric > c_cft_max then
      return jsonb_build_object('ok', false, 'reason', 'bad_payload',
        'detail', format('element %s: cft must be 0..%s', v_i, c_cft_max));
    end if;
  end loop;

  select * into v_row from public.customer_surveys where token = p_token for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_submittable');
  end if;

  if v_row.status = 'pending' and v_row.expires_at > now() then
    v_again := false;
  elsif public.survey_editable(v_row) then
    v_again := true;
  else
    return jsonb_build_object('ok', false, 'reason',
      case when v_row.status = 'submitted' then 'locked' else 'not_submittable' end);
  end if;

  update public.customer_surveys
     set rooms                = p_rooms,
         special_instructions = nullif(left(coalesce(p_instructions, ''), 2000), ''),
         status               = 'submitted',
         submitted_at         = now(),
         used_at              = now()
   where id = v_row.id
  returning id into v_id;

  if v_again then
    begin
      insert into public.notifications (org_id, recipient_staff_id, type, title, body, ref_lead_id)
      values (v_row.org_id, null, 'survey_updated', 'Survey updated',
              coalesce(nullif(btrim(coalesce(v_row.customer_name, '')), ''), 'The customer')
                || ' changed their moving list. Check it before you quote.',
              v_row.lead_id::text);
    exception when others then null;
    end;
  end if;

  return jsonb_build_object('ok', true, 'survey_id', v_id, 'updated', v_again);
end;
$function$;

commit;
