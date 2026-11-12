-- 20261112_quote_upi_advance.sql  (12 Nov 2026)
--
-- Arun's September list, item 5: "a re-quote must be shareable for
-- re-confirmation: the customer reviews and agrees, then pays the advance,
-- then the order confirms." The quote link (11 Nov) covers review and
-- agree; this adds the advance.
--
-- After the customer ACCEPTS, the quote page offers the advance the vendor
-- asked for on that quote ("Advance requested") by UPI, straight to the
-- VENDOR's own UPI ID (Settings -> business profile). Nagarva never holds
-- the money: this is the SaaS model, no gateway, no wallet.
--   * no advance on the quote, no UPI ID, or an order already made for
--     this quote -> nothing is offered (no suggested money);
--   * the customer can tap "I've paid" with their UPI reference; the
--     vendor gets a notification and a follow-up line to CHECK the account,
--     then records the payment and confirms the booking as today.
--
-- Changes:
--   quotations      + advance_reported_at, advance_reported_ref
--   public_get_quote      + 'pay' (upi_id, payee, amount, note, reported_at)
--                         + 'booked'
--   public_respond_quote  + action 'paid' (refusal 'not_accepted')
-- Both functions are replaced from the bodies live on 12 Nov 2026 (checked
-- by fingerprint below); grants are kept by CREATE OR REPLACE and checked.
--
-- Run the WHOLE file. One transaction; a failed check rolls it all back.

begin;

-- ---------- preflight -------------------------------------------------
do $pre$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'quotations'
                and column_name = 'advance_reported_at') then
    raise exception 'quotations.advance_reported_at already exists -- this file has been run.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.public_get_quote(text)'::regprocedure)
       <> '87c386bf3b3f64c3b327d76457429bde'
     or (select md5(prosrc) from pg_proc where oid = 'public.public_respond_quote(text,text,text,text)'::regprocedure)
       <> 'd711728f7cab566fbb6f4ab84446add6' then
    raise exception 'The quote link functions changed since this file was written. Stop and check.';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public'
                  and table_name = 'organizations' and column_name = 'upi_id')
     or not exists (select 1 from information_schema.columns where table_schema = 'public'
                  and table_name = 'organizations' and column_name = 'beneficiary_name')
     or not exists (select 1 from information_schema.columns where table_schema = 'public'
                  and table_name = 'orders' and column_name = 'quotation_id') then
    raise exception 'organizations.upi_id / beneficiary_name or orders.quotation_id is missing.';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.follow_up_logs'::regclass
                  and contype = 'c' and pg_get_constraintdef(oid) ~ '''accepted''') then
    raise exception 'follow_up_logs does not allow outcome ''accepted''.';
  end if;
end $pre$;

alter table public.quotations
  add column advance_reported_at  timestamptz,
  add column advance_reported_ref text;

-- ---------- public_get_quote ------------------------------------------
create or replace function public.public_get_quote(p_token text)
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
  v_adv numeric;
  v_pay jsonb;
  v_booked boolean;
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

  -- 12 Nov 2026: once the customer has ACCEPTED, the advance the vendor
  -- asked for on this quote ("Advance requested") is offered by UPI to the
  -- VENDOR's own UPI ID -- Nagarva never touches the money. Shown only
  -- when there is an advance, a UPI ID that looks like one, and no order
  -- yet (after booking the vendor has the payment in hand).
  v_adv := (v_print ->> 'advance')::numeric;
  v_booked := exists (select 1 from public.orders o
                       where o.quotation_id = q.id and o.deleted_at is null);
  if q.status = 'accepted' and not v_booked and coalesce(v_adv, 0) > 0
     and coalesce(v_org.upi_id, '') ~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$' then
    v_pay := jsonb_build_object(
      'upi_id', v_org.upi_id,
      'payee', coalesce(nullif(btrim(coalesce(v_org.beneficiary_name, '')), ''), v_org.name),
      'amount', v_adv,
      'note', 'Advance for quote ' || v_ref,
      'reported_at', q.advance_reported_at);
  end if;

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
    'pdf', v_pdf,
    'booked', v_booked,
    'pay', v_pay
  );
end $$;

-- ---------- public_respond_quote --------------------------------------
create or replace function public.public_respond_quote(
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
  if p_action not in ('accept', 'changes', 'paid') then
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
  v_ref := upper(left(coalesce(q.lead_id::text, q.id), 8));

  -- 12 Nov 2026: 'paid' = the customer says they paid the advance by UPI
  -- (p_note = their UPI reference, optional). It only TELLS the vendor to
  -- check their account; the vendor records the payment as usual. Saying
  -- it twice is fine and notifies once.
  if p_action = 'paid' then
    if q.status <> 'accepted' then
      return jsonb_build_object('ok', false, 'reason', 'not_accepted');
    end if;
    if q.advance_reported_at is not null then
      return jsonb_build_object('ok', true, 'reported_at', q.advance_reported_at);
    end if;
    v_note := left(regexp_replace(v_note, '[^A-Za-z0-9]', '', 'g'), 40);
    update public.quotations
       set advance_reported_at = now(), advance_reported_ref = nullif(v_note, '')
     where id = q.id;
    if q.lead_id is not null then
      insert into public.follow_up_logs (org_id, entity_type, entity_id, channel, outcome, notes)
      values (q.org_id, 'lead', q.lead_id::text, 'other', 'accepted',
              'Customer says the advance is paid by UPI'
              || coalesce(' (reference ' || nullif(v_note, '') || ')', '') || '. Check the account before confirming.');
    end if;
    insert into public.notifications (org_id, recipient_staff_id, type, title, body, ref_lead_id)
    values (q.org_id, null, 'quote_advance_paid', 'Customer says the advance is paid',
            coalesce(nullif(btrim(coalesce(q.customer, '')), ''), 'The customer')
              || ' says the advance for quote ' || v_ref || ' is paid by UPI'
              || coalesce(' (reference ' || nullif(v_note, '') || ')', '')
              || '. Check your account, record the payment and confirm the booking.',
            q.lead_id::text);
    return jsonb_build_object('ok', true, 'reported_at', now());
  end if;

  if q.status = 'accepted' then
    return jsonb_build_object('ok', false, 'reason', 'already_accepted');
  end if;
  if q.valid_until is not null and q.valid_until < (now() at time zone 'Asia/Kolkata')::date then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

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

-- ---------- postflight ------------------------------------------------
do $post$
declare
  q record;
  r jsonb;
  v_before int;
  v_after int;
begin
  if not has_function_privilege('anon', 'public.public_get_quote(text)', 'execute')
     or not has_function_privilege('anon', 'public.public_respond_quote(text,text,text,text)', 'execute') then
    raise exception 'POSTFLIGHT: anon lost EXECUTE on a quote link function';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
              where p.oid in ('public.public_get_quote(text)'::regprocedure,
                              'public.public_respond_quote(text,text,text,text)'::regprocedure)
                and a.grantee = 0) then
    raise exception 'POSTFLIGHT: PUBLIC holds EXECUTE on a quote link function';
  end if;
  if public.public_get_quote('short') ->> 'reason' <> 'invalid'
     or public.public_respond_quote(repeat('z', 48), 'paid', null, null) ->> 'reason' <> 'not_found' then
    raise exception 'POSTFLIGHT: bad tokens are not refused plainly';
  end if;

  -- Behaviour on a real quote, rolled back. It borrows a live quote (any
  -- quote of a serviceable company with a UPI ID and no order yet) and sets
  -- the state it needs inside the savepoint, so the test never depends on
  -- one being accepted with an advance today.
  select qq.id, qq.token, qq.org_id into q
    from public.quotations qq join public.organizations o on o.id = qq.org_id
   where qq.deleted_at is null and qq.token is not null and qq.status <> 'lost'
     and o.upi_id ~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$'
     and public.public_org_serviceable(qq.org_id)
     and (qq.valid_until is null or qq.valid_until >= (now() at time zone 'Asia/Kolkata')::date)
     and not exists (select 1 from public.orders x where x.quotation_id = qq.id and x.deleted_at is null)
   order by qq.created_at desc limit 1;
  if q.id is null then
    raise exception 'POSTFLIGHT: no quote of a company with a UPI ID to test on.';
  end if;

  begin
    -- not accepted yet: nothing offered, nothing taken
    update public.quotations
       set status = 'sent',
           charges = case when jsonb_typeof(charges) = 'object' then charges else '{}'::jsonb end
                     || '{"advanceOnQuote": 1500}'::jsonb
     where id = q.id;
    if public.public_get_quote(q.token) -> 'pay' <> 'null'::jsonb
       or public.public_respond_quote(q.token, 'paid', null, null) ->> 'reason' <> 'not_accepted' then
      raise exception 'POSTFLIGHT: a quote not yet accepted offers or takes the advance';
    end if;

    -- accepted: the advance is offered to the vendor's UPI ID
    update public.quotations set status = 'accepted', accepted_at = now() where id = q.id;
    r := public.public_get_quote(q.token);
    if jsonb_typeof(r -> 'pay') is distinct from 'object'
       or (r -> 'pay' ->> 'amount')::numeric <> 1500
       or (r -> 'pay' ->> 'upi_id') is null
       or r -> 'pay' -> 'reported_at' <> 'null'::jsonb
       or (r ->> 'booked')::boolean then
      raise exception 'POSTFLIGHT: an accepted quote does not offer its advance by UPI: %', r -> 'pay';
    end if;

    -- "I've paid": reference cleaned and kept, vendor told once
    select count(*) into v_before from public.notifications
     where org_id = q.org_id and type = 'quote_advance_paid';
    r := public.public_respond_quote(q.token, 'paid', null, ' 4123-5678 9012 ');
    if not coalesce((r ->> 'ok')::boolean, false) then
      raise exception 'POSTFLIGHT: paid was refused: %', r;
    end if;
    r := public.public_respond_quote(q.token, 'paid', null, null);
    if not coalesce((r ->> 'ok')::boolean, false) then
      raise exception 'POSTFLIGHT: a repeated paid was refused: %', r;
    end if;
    select count(*) into v_after from public.notifications
     where org_id = q.org_id and type = 'quote_advance_paid';
    if v_after <> v_before + 1 then
      raise exception 'POSTFLIGHT: paid twice gave % notifications, expected 1', v_after - v_before;
    end if;
    if (select advance_reported_ref from public.quotations where id = q.id) is distinct from '412356789012' then
      raise exception 'POSTFLIGHT: the UPI reference was not cleaned and kept';
    end if;
    if public.public_get_quote(q.token) -> 'pay' -> 'reported_at' = 'null'::jsonb then
      raise exception 'POSTFLIGHT: the page does not show that the payment was reported';
    end if;
    raise exception 'PROBE-ROLLBACK';
  exception when others then
    if sqlerrm <> 'PROBE-ROLLBACK' then raise; end if;
  end;

  if exists (select 1 from public.quotations where advance_reported_at is not null) then
    raise exception 'POSTFLIGHT: the probe left a reported payment behind';
  end if;
end $post$;

commit;
