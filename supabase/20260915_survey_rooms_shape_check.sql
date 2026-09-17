-- ============================================================
-- public_submit_survey_impl: validate the SHAPE of each element,
-- not just the length of the array.
--
-- 15 Sept 2026. Companion to 20260915_drop_ungated_public_rpcs.sql,
-- which must run FIRST -- this migration's whole justification is that
-- after that drop there is exactly ONE writer of customer_surveys.rooms.
--
-- ------------------------------------------------------------
-- WHY: one column, two jsonb shapes, and nothing refused either.
-- ------------------------------------------------------------
-- Counted against the live table 15 Sept 2026, not estimated:
--
--   rows with a non-empty rooms array : 5
--   shape {cat,cft,item,qty,sub}      : 4   (used_at SET)
--   shape {items,room}                : 1   (used_at NULL, 2 Sep)
--   max elements in any row           : 10
--
-- The odd row was written by the now-dropped submit_survey, which
-- validated nothing at all. This function validated more -- a token
-- length floor, that the payload is an ARRAY, and a 150-element cap --
-- and would have accepted that row too, because none of those three
-- checks looks INSIDE an element.
--
-- So the array-level checks are not the gate they read as. A caller can
-- send [{"anything":"at all"}] x 150 today and it is written verbatim
-- into a column the quote builder, the survey PDF and the CFT total all
-- read. The cost is not a crash -- it is a survey that renders blank or
-- wrong on the vendor's own quote, from data the customer believes they
-- submitted.
--
-- ------------------------------------------------------------
-- The shape is TAKEN FROM THE LIVE WRITER, not invented here.
-- ------------------------------------------------------------
-- public_site/survey/index.html:267-270 builds every element as:
--
--     { cat: catName, item: item.name, sub: sub.label,
--       cft: Number(sub.cft), qty: n }
--
-- and clamps n with Math.max(0, Math.min(99, n)), deleting the entry at
-- 0. Every bound below is read off that line. Nothing here is a product
-- decision about what a vendor may catalogue.
--
-- STRICT on unknown keys, deliberately. Permissive accretion is exactly
-- how this column ended up holding two shapes. The only client is in
-- this repo, so adding a sixth field is a two-line change in two files
-- that ship together -- whereas a silently-accepted stray key is a third
-- shape nobody finds until a document renders wrong. The rejection names
-- the offending key so that change takes seconds.
--
-- ------------------------------------------------------------
-- The reason code stays 'bad_payload'. That is deliberate too.
-- ------------------------------------------------------------
-- public_site/survey/index.html's SUBMIT_ERRORS map carries exactly
-- three codes -- too_large, bad_payload, invalid -- and bad_payload's
-- copy is already right for this case ("Something went wrong building
-- your list. Reload the page and pick your items again.").
--
-- A NEW code would show the customer a generic fallback until
-- public_site/ is redeployed, and that deploy is Arun's call on a live
-- customer page. A server-side hardening must not be able to degrade the
-- customer's error message while it waits for a client release.
--
-- The diagnosis an operator needs goes in a `detail` field instead. The
-- page ignores unknown response fields. `detail` names an index and a
-- key from the caller's OWN payload, so it discloses nothing.
-- ============================================================

begin;

set local search_path = public, pg_catalog;

-- ------------------------------------------------------------
-- PREFLIGHT
-- ------------------------------------------------------------
-- Behavioural, and it tests the thing rather than describing it: it
-- CALLS the function with a deliberately malformed element and reads
-- what comes back.
--
-- A string match for 'jsonb_typeof' over the body would be the
-- always-passes trap this project keeps recording -- that identifier
-- appears in the CURRENT body (the array-type check) and in the new one,
-- so it returns the same answer in both states and cannot discriminate.
--
-- The probe needs a real pending, unexpired token. If there is none it
-- RAISES rather than skipping: a preflight that passes without having
-- tested anything is worse than no preflight.
do $preflight$
declare
  v_token   text;
  v_res     jsonb;
  v_bad     jsonb := '[{"cat":"Kitchen","item":"Refrigerator","sub":"Double Door","cft":"20","qty":1}]'::jsonb;
  --                                                                        ^^^^ cft as a STRING: the
  --                                                                        smallest possible violation.
begin
  select token into v_token
    from public.customer_surveys
   where status = 'pending' and expires_at > now()
   order by expires_at desc
   limit 1;

  if v_token is null then
    raise exception
      'PREFLIGHT: no pending, unexpired customer_surveys row exists, so the probe '
      'cannot exercise the function. Refusing rather than reporting a pass over an '
      'untested change. Mint a survey link and re-run.';
  end if;

  -- Call it, then throw the write away. The raise rolls back this
  -- block's database changes; v_res survives, because plpgsql does not
  -- roll back variable assignments.
  begin
    v_res := public.public_submit_survey_impl(v_token, v_bad, 'ccr preflight probe');
    raise exception 'ccr_probe_rollback';
  exception when others then
    if sqlerrm <> 'ccr_probe_rollback' then
      raise exception 'PREFLIGHT: probe call failed unexpectedly: %', sqlerrm;
    end if;
  end;

  if coalesce(v_res->>'ok', '') = 'true' then
    raise notice 'PREFLIGHT: confirmed -- a string cft is ACCEPTED today (ok=true). Applying the shape check.';
  elsif v_res->>'reason' = 'bad_payload' then
    raise exception
      'PREFLIGHT: a string cft is already refused as bad_payload. This migration '
      'appears to be applied already. Refusing rather than replacing a function '
      'whose current behaviour was not established.';
  else
    raise exception
      'PREFLIGHT: probe returned an unexpected result (%). Expected either ok=true '
      '(not yet applied) or reason=bad_payload (already applied). Refusing.', v_res::text;
  end if;
end
$preflight$;

-- ------------------------------------------------------------
-- THE FUNCTION
-- ------------------------------------------------------------
-- Same signature and same return type, so CREATE OR REPLACE is correct
-- and no DROP is needed. SECURITY DEFINER and the search_path setting
-- are RESTATED rather than assumed -- the same discipline as restating
-- security_invoker on a view, for the same reason: a property that is
-- silently lost has no symptom.
create or replace function public.public_submit_survey_impl(
  p_token        text,
  p_rooms        jsonb,
  p_instructions text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id      uuid;
  v_el      jsonb;
  v_i       integer := 0;
  v_key     text;
  v_bad     text;

  -- Bounds are read off public_site/survey/index.html, not chosen here.
  -- qty: the page clamps to 0..99 and deletes the entry at 0.
  c_qty_max  constant integer := 99;
  -- cft: a sanity ceiling for a public endpoint, NOT an opinion about
  -- what a vendor may catalogue. Live catalogue values run 4..35, so
  -- this cannot refuse a real one; it refuses garbage.
  c_cft_max  constant numeric := 100000;
  -- cat/item/sub are printed on the vendor's quote and survey PDF. The
  -- customer does not type them -- they come from the vendor's own
  -- catalogue -- but an arbitrary caller CAN send anything, so the bound
  -- is a real guard. Generous enough never to refuse a real label.
  c_str_max  constant integer := 200;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  if p_rooms is null or jsonb_typeof(p_rooms) <> 'array' then
    return jsonb_build_object('ok', false, 'reason', 'bad_payload',
                              'detail', 'p_rooms is not a JSON array');
  end if;

  -- Guard against an oversized payload at a public endpoint. 150, not
  -- 50: the catalogue itself offers 110 selectable lines (counted live
  -- 15 Sept 2026 -- 5 categories, 40 items, 110 subs, identical in all
  -- three orgs), so the old ceiling refused legitimate lists. Keep this
  -- ABOVE the largest catalogue any tenant can build, or this refuses
  -- real customers again.
  if jsonb_array_length(p_rooms) > 150 then
    return jsonb_build_object('ok', false, 'reason', 'too_large');
  end if;

  -- ---- ELEMENT SHAPE -------------------------------------------------
  -- The three checks above are all ARRAY-level: they never look inside
  -- an element, which is why a free-text {room, items} row was accepted
  -- and sat in this column alongside the real shape.
  for v_el in select value from jsonb_array_elements(p_rooms)
  loop
    v_i := v_i + 1;

    if jsonb_typeof(v_el) <> 'object' then
      return jsonb_build_object('ok', false, 'reason', 'bad_payload',
        'detail', format('element %s is %s, expected an object', v_i, jsonb_typeof(v_el)));
    end if;

    -- Strict key set: no missing keys, and no unknown ones. See the
    -- header for why unknown keys are refused rather than ignored.
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
        'detail', format('element %s has unexpected key %L; expected exactly cat,item,sub,cft,qty',
                         v_i, v_bad));
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

    -- qty is a count of identical items. 0 cannot arrive from the page
    -- (it deletes the entry instead), and a 0 here would contribute a
    -- line to the survey that adds nothing to the CFT total -- visible
    -- to the vendor as an item the customer did not actually list.
    if (v_el ->> 'qty')::numeric <> trunc((v_el ->> 'qty')::numeric)
       or (v_el ->> 'qty')::numeric < 1
       or (v_el ->> 'qty')::numeric > c_qty_max then
      return jsonb_build_object('ok', false, 'reason', 'bad_payload',
        'detail', format('element %s: qty must be a whole number 1..%s', v_i, c_qty_max));
    end if;

    -- cft feeds the CFT total, which feeds the vehicle/crew slab
    -- suggestion. A negative value would silently REDUCE the total and
    -- under-suggest a vehicle -- wrong in the direction nobody checks.
    if (v_el ->> 'cft')::numeric < 0
       or (v_el ->> 'cft')::numeric > c_cft_max then
      return jsonb_build_object('ok', false, 'reason', 'bad_payload',
        'detail', format('element %s: cft must be 0..%s', v_i, c_cft_max));
    end if;
  end loop;

  update public.customer_surveys
     set rooms                = p_rooms,
         special_instructions = nullif(left(coalesce(p_instructions, ''), 2000), ''),
         status               = 'submitted',
         submitted_at         = now(),
         used_at              = now()
   where token      = p_token
     and status     = 'pending'
     and expires_at > now()
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_submittable');
  end if;

  return jsonb_build_object('ok', true, 'survey_id', v_id);
end;
$function$;

-- ------------------------------------------------------------
-- POSTFLIGHT
-- ------------------------------------------------------------
-- Same transaction, so a failure rolls the replacement away.
--
-- Tests BOTH directions, because they are mutually exclusive and a check
-- that only proves the refusal could pass on a function that refuses
-- everything -- which would take the live /survey page down silently.
do $postflight$
declare
  v_token text;
  v_res   jsonb;
  v_ok    jsonb := '[{"cat":"Kitchen","item":"Refrigerator","sub":"Double Door","cft":20,"qty":2}]'::jsonb;
  v_bad   jsonb := '[{"cat":"Kitchen","item":"Refrigerator","sub":"Double Door","cft":"20","qty":1}]'::jsonb;
  v_free  jsonb := '[{"room":"Kitchen","items":"fridge, mixer, some boxes"}]'::jsonb;
  v_prosecdef boolean;
  v_acl   text;
begin
  select token into v_token
    from public.customer_surveys
   where status = 'pending' and expires_at > now()
   order by expires_at desc
   limit 1;

  if v_token is null then
    raise exception 'POSTFLIGHT: no pending, unexpired row to probe with. Refusing to report a pass.';
  end if;

  -- (1) The malformed element is now REFUSED.
  begin
    v_res := public.public_submit_survey_impl(v_token, v_bad, null);
    raise exception 'ccr_probe_rollback';
  exception when others then
    if sqlerrm <> 'ccr_probe_rollback' then
      raise exception 'POSTFLIGHT: bad-shape probe failed unexpectedly: %', sqlerrm;
    end if;
  end;
  if v_res->>'reason' is distinct from 'bad_payload' then
    raise exception 'POSTFLIGHT: a string cft was NOT refused (got %). Rolling back.', v_res::text;
  end if;

  -- (2) The shape that produced the odd live row is refused too. This is
  -- the specific thing the migration exists to stop.
  begin
    v_res := public.public_submit_survey_impl(v_token, v_free, null);
    raise exception 'ccr_probe_rollback';
  exception when others then
    if sqlerrm <> 'ccr_probe_rollback' then
      raise exception 'POSTFLIGHT: free-text probe failed unexpectedly: %', sqlerrm;
    end if;
  end;
  if v_res->>'reason' is distinct from 'bad_payload' then
    raise exception 'POSTFLIGHT: the free-text {room,items} shape was NOT refused (got %).', v_res::text;
  end if;

  -- (3) THE HALF THAT MATTERS MOST: a WELL-FORMED payload still
  -- succeeds. Without this, a function that refuses everything passes
  -- checks (1) and (2) perfectly and breaks the live customer page.
  begin
    v_res := public.public_submit_survey_impl(v_token, v_ok, 'ccr postflight probe');
    raise exception 'ccr_probe_rollback';
  exception when others then
    if sqlerrm <> 'ccr_probe_rollback' then
      raise exception 'POSTFLIGHT: good-shape probe failed unexpectedly: %', sqlerrm;
    end if;
  end;
  if coalesce(v_res->>'ok', '') <> 'true' then
    raise exception
      'POSTFLIGHT: a VALID payload was refused (%). The live /survey page would break. '
      'Rolling back.', v_res::text;
  end if;

  -- (4) The security properties survived the replace. CREATE OR REPLACE
  -- does preserve these -- this asserts it rather than trusting it, the
  -- same reason the view rule restates security_invoker.
  select p.prosecdef,
         coalesce(array_to_string(p.proacl, ','), '<default>')
    into v_prosecdef, v_acl
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'public_submit_survey_impl';

  if not v_prosecdef then
    raise exception 'POSTFLIGHT: public_submit_survey_impl lost SECURITY DEFINER.';
  end if;

  -- The impl must stay unreachable by anon: the wrapper
  -- public_submit_survey is the anon-callable entry point, and it is
  -- what applies the serviceability gate. anon holding EXECUTE on the
  -- impl would make that gate decorative -- the exact bypass the 8 Sept
  -- suspension migration was verified against.
  if v_acl like '%anon=X%' then
    raise exception
      'POSTFLIGHT: anon holds EXECUTE on public_submit_survey_impl (acl %). '
      'That bypasses the serviceability gate in the wrapper.', v_acl;
  end if;

  raise notice 'POSTFLIGHT OK: bad shapes refused, valid payload accepted, secdef intact, acl %', v_acl;
end
$postflight$;

commit;
