-- 20261111_public_quote_link.sql  (11 Nov 2026)
--
-- The customer quote link: link.nagarva.in/quote?token=...
-- A customer opens their quotation, sees exactly the lines the quote PDF
-- prints, and can ACCEPT it (typing their name) or ASK FOR CHANGES (a
-- short message). The vendor still confirms the booking: acceptance does
-- what the app's own "Accepted" follow-up does, nothing more.
--
-- Two functions, both anon-callable, both gated like the survey link:
--
--   public_get_quote(token)
--     - token >= 20 chars, quote exists and is not deleted
--     - the vendor is serviceable (organizations.active), else 'unavailable'
--     - a quote marked 'lost' answers 'closed' and returns nothing else
--     - first open stamps viewed_at (so the vendor can see it was opened)
--     - returns the vendor's name and phone, the customer's own move
--       details, the items, the PRINTED charge lines (computed here, from
--       the same rules as lib/components/quote_pdf.dart), totals, advance,
--       validity and acceptance state.
--     - never returns: org_id, lead_id, ids, the customer's phone, margin,
--       list price, approval state, the raw charges json.
--
--   public_respond_quote(token, action, name, note)
--     action 'accept'  : name required (2-80 chars). Sets status
--                        'accepted', accepted_at, accepted_by_name. Logs an
--                        'accepted' follow-up on the lead (same as the
--                        app's Quote-stage "Accepted") and a notification
--                        to the owner. "Convert Quote to Order" then shows
--                        for the vendor, exactly as when they log it.
--     action 'changes' : note required (3-500 chars). Logs a 'negotiation'
--                        follow-up and a notification. Quote unchanged.
--     Refused: already accepted, closed, expired (valid_until passed),
--     more than 5 responses on one quote in 24 hours.
--
-- A revised quote keeps its row and its token (revise_quote updates in
-- place), so the same link always shows the latest version, and a
-- customer can accept a revision.
--
-- Grants: EXECUTE revoked from PUBLIC, granted to anon and authenticated
-- only (the security lint flags any SECURITY DEFINER writer PUBLIC can
-- reach; revoking from anon alone would change nothing).
--
-- Run the WHOLE file. One transaction; a failed check rolls it all back.
-- The postflight opens and answers a real quote inside a savepoint and
-- rolls that back, so no data changes.

begin;

-- ---------- preflight -------------------------------------------------
do $pre$
declare
  v_missing text[];
begin
  if to_regprocedure('public.public_get_quote(text)') is not null
     or to_regprocedure('public.public_respond_quote(text,text,text,text)') is not null then
    raise exception 'The quote link functions already exist -- this file has been run.';
  end if;
  if to_regprocedure('public.public_org_serviceable(uuid)') is null then
    raise exception 'public_org_serviceable(uuid) is missing -- the suspension gate (8 Sept) must exist first.';
  end if;

  select array_agg(c) into v_missing
    from unnest(array['token','status','accepted_at','accepted_by_name','viewed_at',
      'deleted_at','charges','items','subtotal','gst_pct','gst_amount','total',
      'total_cft','valid_until','lead_id','org_id','customer','from_address',
      'to_address','from_city','to_city','from_floor','to_floor','from_has_lift',
      'to_has_lift','move_date','moving_date','created_at','version']) c
   where not exists (select 1 from information_schema.columns
                      where table_schema = 'public' and table_name = 'quotations'
                        and column_name = c);
  if v_missing is not null then
    raise exception 'quotations is missing column(s): %', array_to_string(v_missing, ', ');
  end if;

  if not exists (select 1 from pg_indexes where schemaname = 'public'
                  and tablename = 'quotations' and indexdef ilike '%unique%(token)%') then
    raise exception 'quotations.token has no unique index -- a token could match two quotes.';
  end if;

  -- The values this file writes must be allowed by the table checks.
  if not exists (select 1 from pg_constraint where conrelid = 'public.follow_up_logs'::regclass
                  and contype = 'c' and pg_get_constraintdef(oid) ~ '''negotiation''')
     or not exists (select 1 from pg_constraint where conrelid = 'public.follow_up_logs'::regclass
                  and contype = 'c' and pg_get_constraintdef(oid) ~ '''other''') then
    raise exception 'follow_up_logs does not allow outcome ''negotiation'' or channel ''other''.';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.quotations'::regclass
                  and contype = 'c' and pg_get_constraintdef(oid) ~ '''accepted''') then
    raise exception 'quotations.status check does not allow ''accepted''.';
  end if;
end $pre$;

-- ---------- the printed charge lines (mirror of quote_pdf.dart) --------
-- A charge value is a plain number (lumpsum) or {amount, basis, ...}.
-- Lines: every field except discount and advanceOnQuote whose amount is
-- not zero. "Included" footnote: billable fields in 'included' mode
-- (the default) with a zero amount. Same order and labels as
-- kDefaultChargeFields in lib/backend/pricing_defaults.dart.
create function public.quote_charge_amount(p_charges jsonb, p_key text)
returns numeric
language sql immutable
set search_path = public
as $$
  select case
    when jsonb_typeof(p_charges -> p_key) = 'number' then (p_charges ->> p_key)::numeric
    when jsonb_typeof(p_charges -> p_key) = 'object'
         and jsonb_typeof(p_charges -> p_key -> 'amount') = 'number'
      then (p_charges -> p_key ->> 'amount')::numeric
    when jsonb_typeof(p_charges -> p_key) = 'string'
         and (p_charges ->> p_key) ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'
      then trim(p_charges ->> p_key)::numeric
    else 0
  end
$$;
revoke all on function public.quote_charge_amount(jsonb, text) from public;

create function public.quote_print_lines(p_charges jsonb)
returns jsonb
language plpgsql immutable
set search_path = public
as $$
declare
  v_fields constant text[][] := array[
    ['transport','Freight / Transport','n'],
    ['packing','Packing Charge','y'],
    ['unpacking','Un Packing Charge','y'],
    ['loading','Loading Charge','y'],
    ['unloading','Un Loading Charge','y'],
    ['materials','Packing Material Charge','y'],
    ['storage','Storage','n'],
    ['carTransport','Car Transport','n'],
    ['misc','Miscellaneous','n'],
    ['stCharge','S.T. Charge','n'],
    ['otherCharges','Other Charges','n'],
    ['acUninstall','AC Uninstall','n'],
    ['acInstall','AC Install','n'],
    ['tvUninstall','TV Uninstall','n'],
    ['tvInstall','TV Install','n'],
    ['wardrobe','Wardrobe Dismantle/Assemble','n'],
    ['carpenter','Carpenter Charges','n'],
    ['electrician','Electrician Charges','n'],
    ['bikeTransport','Bike Transport','n']
  ];
  v_c jsonb := coalesce(case when jsonb_typeof(p_charges) = 'object' then p_charges end, '{}'::jsonb);
  v_mode jsonb := coalesce(case when jsonb_typeof(v_c -> '_billingMode') = 'object'
                                then v_c -> '_billingMode' end, '{}'::jsonb);
  v_lines jsonb := '[]'::jsonb;
  v_incl  jsonb := '[]'::jsonb;
  v_amt numeric;
  i int;
begin
  for i in 1 .. array_length(v_fields, 1) loop
    v_amt := public.quote_charge_amount(v_c, v_fields[i][1]);
    if v_amt <> 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'label', v_fields[i][2], 'amount', v_amt));
    elsif v_fields[i][3] = 'y'
          and coalesce(v_mode ->> v_fields[i][1], 'included') = 'included' then
      v_incl := v_incl || to_jsonb(v_fields[i][2]);
    end if;
  end loop;
  return jsonb_build_object(
    'lines', v_lines,
    'included', v_incl,
    'discount', public.quote_charge_amount(v_c, 'discount'),
    'advance', public.quote_charge_amount(v_c, 'advanceOnQuote'));
end $$;
revoke all on function public.quote_print_lines(jsonb) from public;

-- ---------- public_get_quote ------------------------------------------
create function public.public_get_quote(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  q public.quotations%rowtype;
  v_org public.organizations%rowtype;
  v_print jsonb;
  v_pdf jsonb;
  v_ref text;
begin
  if p_token is null or length(p_token) < 20 or length(p_token) > 200 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  select * into q from public.quotations
   where token = p_token and deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if not public.public_org_serviceable(q.org_id) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  select * into v_org from public.organizations where id = q.org_id;
  if q.status = 'lost' then
    return jsonb_build_object('ok', false, 'reason', 'closed',
      'vendor_name', v_org.name, 'vendor_phone', v_org.phone);
  end if;

  if q.viewed_at is null then
    update public.quotations set viewed_at = now() where id = q.id;
  end if;

  -- Same reference the quote PDF prints: the lead's first 8 characters.
  v_ref := upper(left(coalesce(q.lead_id::text, q.id), 8));
  v_print := public.quote_print_lines(q.charges);

  -- The latest stored quote PDF, if the vendor has generated one.
  select jsonb_build_object(
           'url', 'https://hqqcapifefsaqvotqvlt.supabase.co/storage/'
                  || 'v1/object/public/order-documents/' || d.storage_path,
           'file_name', d.file_name, 'issued_at', d.created_at)
    into v_pdf
    from public.documents d
   where d.org_id = q.org_id and d.deleted_at is null
     and coalesce(d.is_sensitive, false) = false
     and d.entity_type = 'quotation' and d.entity_id = q.id
   order by d.created_at desc limit 1;

  return jsonb_build_object(
    'ok', true,
    'vendor_name', v_org.name,
    'vendor_phone', v_org.phone,
    'quote_ref', v_ref,
    'version', coalesce(q.version, 1),
    'quote_date', q.created_at,
    'customer_name', btrim(coalesce(q.customer, '')),
    'from_address', nullif(btrim(coalesce(q.from_address, '')), ''),
    'to_address', nullif(btrim(coalesce(q.to_address, '')), ''),
    'from_city', nullif(btrim(coalesce(q.from_city, '')), ''),
    'to_city', nullif(btrim(coalesce(q.to_city, '')), ''),
    'from_floor', q.from_floor, 'to_floor', q.to_floor,
    'from_has_lift', q.from_has_lift, 'to_has_lift', q.to_has_lift,
    'move_date', coalesce(q.moving_date, q.move_date),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'item', e ->> 'item', 'sub', e ->> 'sub',
               'qty', case when jsonb_typeof(e -> 'qty') = 'number' then (e ->> 'qty')::numeric else 1 end))
        from jsonb_array_elements(case when jsonb_typeof(q.items) = 'array' then q.items else '[]'::jsonb end) e
       where coalesce(e ->> 'item', '') <> ''), '[]'::jsonb),
    'total_cft', q.total_cft,
    'lines', v_print -> 'lines',
    'included', v_print -> 'included',
    'discount', (v_print ->> 'discount')::numeric,
    'advance', (v_print ->> 'advance')::numeric,
    'subtotal', q.subtotal,
    'gst_pct', q.gst_pct,
    'gst_amount', q.gst_amount,
    'total', q.total,
    'valid_until', q.valid_until,
    'expired', (q.valid_until is not null and q.valid_until < (now() at time zone 'Asia/Kolkata')::date),
    'accepted', (q.status = 'accepted'),
    'accepted_at', case when q.status = 'accepted' then q.accepted_at end,
    'accepted_by_name', case when q.status = 'accepted' then q.accepted_by_name end,
    'pdf', v_pdf
  );
end $$;

-- ---------- public_respond_quote --------------------------------------
create function public.public_respond_quote(
  p_token text, p_action text, p_name text, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  q public.quotations%rowtype;
  v_ref text;
  v_name text := left(btrim(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]', ' ', 'g')), 80);
  v_note text := left(btrim(regexp_replace(coalesce(p_note, ''), '[[:cntrl:]]', ' ', 'g')), 500);
  v_recent int;
begin
  if p_token is null or length(p_token) < 20 or length(p_token) > 200 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if p_action not in ('accept', 'changes') then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  select * into q from public.quotations
   where token = p_token and deleted_at is null
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if not public.public_org_serviceable(q.org_id) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  if q.status = 'lost' then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  if q.status = 'accepted' then
    return jsonb_build_object('ok', false, 'reason', 'already_accepted');
  end if;
  if q.valid_until is not null and q.valid_until < (now() at time zone 'Asia/Kolkata')::date then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  v_ref := upper(left(coalesce(q.lead_id::text, q.id), 8));

  -- Anyone holding the link can answer; five answers a day per quote is
  -- far more than a real customer needs and stops the owner's
  -- notifications being flooded.
  select count(*) into v_recent from public.notifications n
   where n.org_id = q.org_id and n.type in ('quote_accepted', 'quote_changes')
     and n.created_at > now() - interval '24 hours'
     and n.body like '%quote ' || v_ref || '%';
  if v_recent >= 5 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;

  if p_action = 'accept' then
    if length(v_name) < 2 then
      return jsonb_build_object('ok', false, 'reason', 'name_required');
    end if;
    update public.quotations
       set status = 'accepted', accepted_at = now(), accepted_by_name = v_name
     where id = q.id;
    if q.lead_id is not null then
      insert into public.follow_up_logs (org_id, entity_type, entity_id, channel, outcome, notes)
      values (q.org_id, 'lead', q.lead_id::text, 'other', 'accepted',
              'Customer accepted the quote online as "' || v_name || '".');
    end if;
    insert into public.notifications (org_id, recipient_staff_id, type, title, body, ref_lead_id)
    values (q.org_id, null, 'quote_accepted', 'Quote accepted online',
            v_name || ' accepted quote ' || v_ref || '. Confirm the booking to create the order.',
            q.lead_id::text);
    return jsonb_build_object('ok', true, 'accepted', true, 'accepted_at', now());
  end if;

  -- changes
  if length(v_note) < 3 then
    return jsonb_build_object('ok', false, 'reason', 'note_required');
  end if;
  if q.lead_id is not null then
    insert into public.follow_up_logs (org_id, entity_type, entity_id, channel, outcome, notes)
    values (q.org_id, 'lead', q.lead_id::text, 'other', 'negotiation',
            'Customer asked for changes online: ' || v_note);
  end if;
  insert into public.notifications (org_id, recipient_staff_id, type, title, body, ref_lead_id)
  values (q.org_id, null, 'quote_changes', 'Customer asked for changes',
          coalesce(nullif(btrim(coalesce(q.customer, '')), ''), 'The customer')
            || ' asked for changes to quote ' || v_ref || ': ' || v_note,
          q.lead_id::text);
  return jsonb_build_object('ok', true, 'accepted', false);
end $$;

revoke all on function public.public_get_quote(text) from public;
revoke all on function public.public_respond_quote(text, text, text, text) from public;
grant execute on function public.public_get_quote(text) to anon, authenticated;
grant execute on function public.public_respond_quote(text, text, text, text) to anon, authenticated;

-- ---------- postflight ------------------------------------------------
do $post$
declare
  r jsonb;
  q record;
  v_err text;
  v_checked int := 0;
begin
  -- Grants: anon yes, PUBLIC no (the PUBLIC test is the ACL itself).
  if not has_function_privilege('anon', 'public.public_get_quote(text)', 'execute')
     or not has_function_privilege('anon', 'public.public_respond_quote(text,text,text,text)', 'execute') then
    raise exception 'anon cannot execute the quote link functions';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
              where p.oid in ('public.public_get_quote(text)'::regprocedure,
                              'public.public_respond_quote(text,text,text,text)'::regprocedure,
                              'public.quote_print_lines(jsonb)'::regprocedure,
                              'public.quote_charge_amount(jsonb,text)'::regprocedure)
                and a.grantee = 0) then
    raise exception 'PUBLIC still holds EXECUTE on a quote link function';
  end if;

  -- Bad tokens answer plainly and return no data.
  if public.public_get_quote('short') ->> 'reason' <> 'invalid'
     or public.public_get_quote(repeat('z', 48)) ->> 'reason' <> 'not_found' then
    raise exception 'bad tokens are not refused plainly';
  end if;

  -- The printed lines match the PDF rules on a hand-made charges object.
  r := public.quote_print_lines('{"transport": 5000, "packing": {"basis":"per_cft","qty":45,"rate":0,"amount":0},
        "loading": 0, "acInstall": 800, "discount": 300, "advanceOnQuote": 1000,
        "materials": {"basis":"at_actuals","amount":0},
        "_billingMode": {"packing":"included","materials":"extra"}}'::jsonb);
  if r -> 'lines' <> '[{"label":"Freight / Transport","amount":5000},{"label":"AC Install","amount":800}]'::jsonb
     or r -> 'included' <> '["Packing Charge","Un Packing Charge","Loading Charge","Un Loading Charge"]'::jsonb
     or (r ->> 'discount')::numeric <> 300 or (r ->> 'advance')::numeric <> 1000 then
    raise exception 'quote_print_lines does not match the PDF rules: %', r;
  end if;

  -- Behaviour on real quotes, rolled back: open, ask for changes, accept.
  for q in select id, token, org_id, lead_id from public.quotations
            where deleted_at is null and token is not null
              and coalesce(status, 'draft') not in ('accepted', 'lost')
              and public.public_org_serviceable(org_id)
            order by created_at desc limit 3 loop
    v_err := null;
    begin
      r := public.public_get_quote(q.token);
      if (r ->> 'ok')::boolean is not true then raise exception 'open failed: %', r; end if;
      if r ? 'org_id' or r ? 'lead_id' or r ? 'charges' or r ? 'phone' then
        raise exception 'open leaks internal fields: %', r;
      end if;
      if (select viewed_at from public.quotations where id = q.id) is null then
        raise exception 'viewed_at was not stamped';
      end if;

      r := public.public_respond_quote(q.token, 'changes', null, 'x');
      if r ->> 'reason' <> 'note_required' then raise exception 'short note accepted: %', r; end if;
      r := public.public_respond_quote(q.token, 'changes', null, 'Can you do it for less?');
      if (r ->> 'ok')::boolean is not true then raise exception 'changes failed: %', r; end if;

      r := public.public_respond_quote(q.token, 'accept', ' ', null);
      if r ->> 'reason' <> 'name_required' then raise exception 'empty name accepted: %', r; end if;
      r := public.public_respond_quote(q.token, 'accept', 'Test Customer', null);
      if (r ->> 'ok')::boolean is not true then raise exception 'accept failed: %', r; end if;
      if (select status from public.quotations where id = q.id) <> 'accepted' then
        raise exception 'status not accepted after accept';
      end if;
      if q.lead_id is not null and not exists (
           select 1 from public.follow_up_logs f
            where f.entity_type = 'lead' and f.entity_id = q.lead_id::text
              and f.outcome = 'accepted' and f.logged_at > now() - interval '1 minute') then
        raise exception 'no accepted follow-up logged';
      end if;
      r := public.public_respond_quote(q.token, 'accept', 'Test Customer', null);
      if r ->> 'reason' <> 'already_accepted' then raise exception 'second accept not refused: %', r; end if;
      if (public.public_get_quote(q.token) ->> 'accepted')::boolean is not true then
        raise exception 'open does not show accepted';
      end if;

      raise exception 'PROBE-ROLLBACK';
    exception when others then
      if sqlerrm <> 'PROBE-ROLLBACK' then v_err := sqlerrm; end if;
    end;
    if v_err is not null then
      raise exception 'Quote link test failed on quote %: %', q.id, v_err;
    end if;
    v_checked := v_checked + 1;
  end loop;
  if v_checked = 0 then
    raise exception 'No open quote to test against -- nothing was proven. Rolled back.';
  end if;
  raise notice 'Quote link: % real quote(s) opened, answered and accepted in test; all rolled back.', v_checked;
end $post$;

commit;
