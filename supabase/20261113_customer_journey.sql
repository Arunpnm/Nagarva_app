-- ============================================================
-- 20261113_customer_journey.sql  (13 Nov 2026)
--
-- From Arun's phone test of the whole customer journey (Arun Packers
-- and Couriers, 13 Nov 2026, "APPLICATION TESTING & DEFECT REPORT").
-- Four things on the server side:
--
--  1. QUOTATION NUMBER (report 3.1). Quotations had no number: the
--     customer's signing page and every PDF showed the row's UUID
--     ("1e02baae-a1e2-..."). Every org already has a 'quotation' number
--     series (ARU-Q/2026/0001); it was seeded and never used. A trigger
--     now gives every new quote its number from that series, and the
--     quotes already on file get theirs in the order they were made.
--     Revisions keep the number: a revision updates the same row.
--
--  2. SIGNATURE = ACCEPTANCE = ORDER (report 5.1). When the customer
--     signs a quote, the quote is accepted and, if the quote belongs to
--     a lead with no order yet, the order is created right there, by
--     the same rules the app's "Confirm order" uses (order id from the
--     org's series, the quote's figures frozen on the order, lead moved
--     to confirmed, first tracking entry). Nobody has to tap Confirm for
--     a job the customer has already accepted in writing.
--
--  3. THE SIGNED PAGE (reports 4.1, 6.1). A signed link no longer dead-
--     ends on "Already signed". It shows the signature, who signed and
--     when, the order id, the ARRIVAL CODE the crew will ask for, and a
--     download of the signed copy once the vendor's app has stored one.
--
--  4. EXTRA CHARGES NEED THE CUSTOMER'S YES (reports 7.1, 8.2, 8.1).
--     `addons` gains an approval: new rows start 'awaiting' and carry
--     amount 0 until approved, so only approved charges reach any
--     balance, invoice or report. The customer approves or rejects from their
--     tracking page; the vendor may record a yes given on the phone.
--     Every decision is logged with amount, who and when. Rows on file
--     today were agreed before this rule and stay approved.
--
-- Run once in the Supabase SQL editor. Nothing here deletes anything.
-- Read-only until the final commit; every step is checked after.
-- ============================================================

begin;

-- ---------- preflight -------------------------------------------------
do $pre$
begin
  if to_regprocedure('public.next_doc_number(uuid,text,text,text)') is null then
    raise exception 'next_doc_number is missing: run the numbering scripts first';
  end if;
  if to_regprocedure('public.next_order_id(uuid)') is null then
    raise exception 'next_order_id is missing: run 20260908_next_order_id_allocator.sql first';
  end if;
  if to_regprocedure('public.public_submit_signature_impl(text,text,text)') is null
     or to_regprocedure('public.public_get_signature_request_impl(text)') is null then
    raise exception 'the public signature functions are missing: run 20260908_suspension_gate_and_link_minting.sql first';
  end if;
  if exists (select 1 from information_schema.columns
              where table_name = 'quotations' and column_name = 'quote_no')
     or exists (select 1 from information_schema.columns
              where table_name = 'addons' and column_name = 'approval') then
    raise exception 'quote_no / addons.approval already exist: this script has been run';
  end if;
end $pre$;

-- ---------- helpers ---------------------------------------------------

-- Indian financial year label as the app writes it: '2026-27'. IST, so
-- a quote made at 00:30 on 1 April is in the new year.
create or replace function public.current_fy_ist()
returns text language sql stable as $$
  select case
    when extract(month from (now() at time zone 'Asia/Kolkata')) >= 4
    then extract(year from (now() at time zone 'Asia/Kolkata'))::int::text
         || '-' || lpad(((extract(year from (now() at time zone 'Asia/Kolkata'))::int + 1) % 100)::text, 2, '0')
    else (extract(year from (now() at time zone 'Asia/Kolkata'))::int - 1)::text
         || '-' || lpad((extract(year from (now() at time zone 'Asia/Kolkata'))::int % 100)::text, 2, '0')
  end
$$;

-- ---------- 1. quotation number ---------------------------------------
alter table public.quotations add column quote_no text;
create unique index quotations_org_quote_no_uniq
  on public.quotations (org_id, quote_no) where quote_no is not null;

-- The number comes from the org's own 'quotation' series. An org with
-- no active series (none today) still gets its quote saved: the number
-- is simply left empty and the app falls back to a short reference.
create or replace function public.quotations_assign_quote_no()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.quote_no is null or new.quote_no = '' then
    begin
      new.quote_no := public.next_doc_number(new.org_id, 'quotation', null, public.current_fy_ist());
    exception when others then
      new.quote_no := null;
    end;
  end if;
  return new;
end $$;

drop trigger if exists quotations_assign_quote_no on public.quotations;
create trigger quotations_assign_quote_no
  before insert on public.quotations
  for each row execute function public.quotations_assign_quote_no();

-- Quotes already on file, numbered in the order they were made, each
-- from its own org's series, so the series continues from today's
-- quotes without a gap or a repeat.
do $backfill$
declare
  r record;
  n text;
begin
  for r in
    select id, org_id from public.quotations
     where quote_no is null and deleted_at is null
     order by org_id, created_at
  loop
    begin
      n := public.next_doc_number(r.org_id, 'quotation', null, public.current_fy_ist());
      update public.quotations set quote_no = n where id = r.id;
    exception when others then
      -- No series for this org: leave it; the app shows a short ref.
      null;
    end;
  end loop;
end $backfill$;

-- ---------- 2. signature accepts the quote and books the order ----------

-- Books the order for a signed quote. Idempotent: a second call for the
-- same quote returns the order already made. Returns null when the
-- quote has no lead (a walk-in quote: the office books it by hand).
create or replace function public.book_order_from_signed_quote(
  p_quotation_id uuid,
  p_signed_by     text
) returns text language plpgsql security definer set search_path = public as $$
declare
  q          public.quotations%rowtype;
  l          public.leads%rowtype;
  v_order_id text;
  v_cust     uuid;
  v_date     date;
  v_mode     text;
begin
  select * into q from public.quotations where id = p_quotation_id and deleted_at is null;
  if not found then return null; end if;

  -- Accepted, in the customer's own name.
  update public.quotations
     set status = 'accepted',
         accepted_at = coalesce(accepted_at, now()),
         accepted_by_name = coalesce(accepted_by_name, p_signed_by)
   where id = q.id;

  if q.lead_id is null then return null; end if;

  -- Already booked (by the office, or by an earlier signature)?
  select o.id into v_order_id
    from public.orders o
   where o.org_id = q.org_id
     and o.deleted_at is null
     and lower(coalesce(o.status, '')) <> 'cancelled'
     and (o.quotation_id::text = q.id::text or o.lead_id::text = q.lead_id::text)
   order by o.created_at desc
   limit 1;
  if v_order_id is not null then return v_order_id; end if;

  select * into l from public.leads where id::text = q.lead_id::text;

  -- The customer record, by phone, the same match the app uses.
  if coalesce(q.phone, l.phone) is not null then
    select c.id into v_cust from public.customers c
     where c.org_id = q.org_id and c.deleted_at is null
       and (c.phone_normalized = regexp_replace(coalesce(q.phone, l.phone), '\D', '', 'g')
            or c.phone = coalesce(q.phone, l.phone))
     limit 1;
  end if;

  -- The move date: the quote's, else the lead's (free text there, so a
  -- value that is not a date is skipped), else today.
  v_date := q.moving_date::date;
  if v_date is null then
    begin
      v_date := nullif(trim(l.approx_date::text), '')::date;
    exception when others then
      v_date := null;
    end;
  end if;
  v_date := coalesce(v_date, (now() at time zone 'Asia/Kolkata')::date);
  v_mode := case when q.charges->>'_gstType' in ('inter', 'intra') then q.charges->>'_gstType' end;

  v_order_id := public.next_order_id(q.org_id);

  insert into public.orders (
    id, org_id, lead_id, customer_id, quotation_id,
    customer, phone, from_city, to_city, from_address, to_address,
    from_floor, to_floor, move_date, amount, service, branch, notes,
    status, payment_status, tracking_status
  ) values (
    v_order_id, q.org_id, q.lead_id, v_cust, q.id::text,
    coalesce(nullif(q.customer, ''), l.customer, 'Customer'),
    coalesce(q.phone, l.phone),
    coalesce(q.from_city, l.from_city), coalesce(q.to_city, l.to_city),
    coalesce(q.from_address, l.from_address), coalesce(q.to_address, l.to_address),
    coalesce(q.from_floor, l.from_floor), coalesce(q.to_floor, l.to_floor),
    v_date, coalesce(q.total, 0), l.service, l.branch, l.notes,
    'booked', 'pending', 'Booked'
  );

  -- The quote's figures, frozen on the order (the app's quote snapshot).
  -- Best effort, as in the app: the booking above already stands.
  begin
    update public.orders set
      quote_items = q.items, quote_charges = q.charges,
      quote_subtotal = q.subtotal, quote_gst_pct = q.gst_pct,
      quote_gst_amount = q.gst_amount, quote_total = q.total,
      quote_gst_mode = v_mode,
      quote_packing_type = q.charges->>'_suggestedPackage',
      suggested_package = q.suggested_package,
      suggested_vehicle = q.suggested_vehicle,
      suggested_crew = q.suggested_crew,
      chosen_package = coalesce(q.chosen_package, q.charges->>'_suggestedPackage'),
      chosen_vehicle = q.chosen_vehicle, chosen_crew = q.chosen_crew,
      quote_version = coalesce(q.version, 1),
      quote_snapshot_at = now()
    where id = v_order_id;
  exception when others then null;
  end;

  insert into public.order_status_history (org_id, order_id, status, note)
  values (q.org_id, v_order_id, 'booked', 'Order confirmed: quotation signed by ' || coalesce(p_signed_by, 'the customer'));

  update public.leads set status = 'confirmed' where id::text = q.lead_id::text;
  begin
    update public.leads set order_id = v_order_id where id::text = q.lead_id::text;
  exception when others then null;
  end;

  return v_order_id;
end $$;

revoke all on function public.book_order_from_signed_quote(uuid, text) from public, anon, authenticated;

-- The sign page's submit: unchanged checks, then the booking.
create or replace function public.public_submit_signature_impl(p_token text, p_customer_name text, p_signature_data text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_id   uuid;
  v_row  public.document_signatures%rowtype;
  v_ord  text;
  v_code text;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if p_signature_data is null or length(p_signature_data) < 100 then
    return jsonb_build_object('ok', false, 'reason', 'bad_payload');
  end if;
  if length(p_signature_data) > 524288 then
    return jsonb_build_object('ok', false, 'reason', 'too_large');
  end if;

  update public.document_signatures
     set signature_data = p_signature_data,
         customer_name  = coalesce(nullif(left(p_customer_name, 120), ''), customer_name),
         signed_at      = now(),
         status         = 'signed'
   where sign_token = p_token
     and signed_at  is null
     and status     = 'pending'
     and expires_at > now()
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signable');
  end if;

  select * into v_row from public.document_signatures where id = v_id;

  -- 13 Nov 2026: a signed quote is an accepted quote, and an accepted
  -- quote with a lead is a booked order. Best effort: a booking problem
  -- must never lose the signature that was just recorded.
  if v_row.document_type = 'quote' then
    begin
      v_ord := public.book_order_from_signed_quote(v_row.document_id::uuid, v_row.customer_name);
      if v_ord is not null then
        select arrival_code into v_code from public.orders where id = v_ord;
      end if;
    exception when others then
      v_ord := null;
    end;
  end if;

  return jsonb_build_object('ok', true, 'signature_id', v_id,
                            'order_id', v_ord, 'arrival_code', v_code);
end;
$function$;

-- The app's own path (the sign-document edge function) books too.
create or replace function public.submit_signature(p_token text, p_signature_data text, p_customer_name text, p_signer_ip text)
returns table(ok boolean, message text) language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare
  v_row public.document_signatures%rowtype;
  v_id uuid;
begin
  select * into v_row from public.document_signatures where sign_token = p_token;
  if not found then
    return query select false, 'Invalid or expired link'::text; return;
  end if;
  if v_row.status = 'signed' then
    return query select true, 'Already signed'::text; return;
  end if;
  if v_row.expires_at is not null and v_row.expires_at < now() then
    return query select false, 'This link has expired'::text; return;
  end if;
  if p_signature_data is null or length(trim(p_signature_data)) = 0 then
    return query select false, 'Signature is required'::text; return;
  end if;
  if length(p_signature_data) > 524288 then
    return query select false, 'Signature image too large'::text; return;
  end if;

  update public.document_signatures
     set signature_data = p_signature_data,
         customer_name  = coalesce(nullif(trim(p_customer_name), ''), customer_name),
         signer_ip      = p_signer_ip,
         signed_at      = now(),
         status         = 'signed'
   where sign_token = p_token
     and status = 'pending'
     and (expires_at is null or expires_at > now())
  returning id into v_id;

  if v_id is null then
    select * into v_row from public.document_signatures where sign_token = p_token;
    if v_row.status = 'signed' then
      return query select true, 'Already signed'::text;
    else
      return query select false, 'This link has expired'::text;
    end if;
    return;
  end if;

  select * into v_row from public.document_signatures where id = v_id;
  if v_row.document_type = 'quote' then
    begin
      perform public.book_order_from_signed_quote(v_row.document_id::uuid, v_row.customer_name);
    exception when others then null;
    end;
  end if;

  return query select true, 'Signed'::text;
end;
$function$;

-- ---------- 3. what the sign page shows -------------------------------

-- A signed link now answers ok:true with signed:true and everything the
-- confirmation view needs. 'already_signed' is no longer returned.
create or replace function public.public_get_signature_request_impl(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v   public.document_signatures%rowtype;
  o   public.orders%rowtype;
  q   public.quotations%rowtype;
  doc jsonb := '{}'::jsonb;
  v_signed jsonb := '{}'::jsonb;
  v_pdf text;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  select * into v from public.document_signatures where sign_token = p_token;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if v.status is distinct from 'signed' and v.expires_at < now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  if v.document_type = 'quote' then
    select * into q from public.quotations where id::text = v.document_id;
    if found then
      doc := jsonb_build_object(
        'document_no', coalesce(q.quote_no, upper(left(q.id::text, 8))),
        'quote_no',    q.quote_no,
        'version',     q.version,
        'customer',    q.customer,
        'from_city',   q.from_city,
        'to_city',     q.to_city,
        'move_date',   q.moving_date,
        'items',       coalesce(q.items, '[]'::jsonb),
        'subtotal',    q.subtotal,
        'gst_pct',     q.gst_pct,
        'gst_amount',  q.gst_amount,
        'total',       q.total
      );
      if v.status = 'signed' then
        -- The order this signature booked (or the office booked).
        select * into o from public.orders ord
         where ord.org_id = v.org_id and ord.deleted_at is null
           and lower(coalesce(ord.status, '')) <> 'cancelled'
           and (ord.quotation_id::text = q.id::text or (q.lead_id is not null and ord.lead_id::text = q.lead_id::text))
         order by ord.created_at desc limit 1;
        -- The signed PDF: the vendor's app stores one, carrying the
        -- signature, under its own document type.
        select 'https://hqqcapifefsaqvotqvlt.supabase.co/storage/v1/object/public/order-documents/' || d.storage_path
          into v_pdf
          from public.documents d
         where d.org_id = v.org_id and d.deleted_at is null
           and d.entity_type = 'quotation' and d.entity_id = q.id::text
           and d.doc_type = 'quote_signed'
         order by d.created_at desc limit 1;
      end if;
    end if;
  else
    select * into o from public.orders where id = coalesce(v.order_id, v.document_id);
    if found then
      doc := jsonb_build_object(
        'document_no', o.invoice_no,
        'customer',    o.customer,
        'from_city',   o.from_city,
        'to_city',     o.to_city,
        'from_address', o.from_address,
        'to_address',   o.to_address,
        'move_date',   o.move_date,
        'items',       coalesce(o.quote_items, '[]'::jsonb),
        'total',       o.amount
      );
    end if;
  end if;

  if v.status = 'signed' then
    v_signed := jsonb_build_object(
      'signed',          true,
      'signed_by',       v.customer_name,
      'signed_at',       v.signed_at,
      'signature_data',  v.signature_data,
      'order_id',        o.id,
      'arrival_code',    case when o.id is not null then o.arrival_code end,
      'order_move_date', o.move_date,
      'signed_pdf_url',  v_pdf
    );
  end if;

  return jsonb_build_object(
    'ok',            true,
    'vendor_name',   (select org.name from public.organizations org where org.id = v.org_id),
    'vendor_phone',  (select org.phone from public.organizations org where org.id = v.org_id),
    'customer_name', v.customer_name,
    'document_type', v.document_type,
    'document_id',   v.document_id,
    'signed',        false
  ) || doc || v_signed;
end;
$function$;

-- ---------- 4. extra charges: the customer's yes ----------------------
--
-- How "only approved charges are billed" is made true EVERYWHERE at once:
-- `amount` stays what it has always been, the figure every balance,
-- invoice, P&L, GST view and dashboard already adds up. The figure the
-- vendor ASKED for now lives in `requested_amount`, and a guard keeps
-- `amount` at zero until the charge is approved. So not one of the dozen
-- places that sum add-ons had to change, and none can be forgotten.
alter table public.addons
  add column approval         text not null default 'awaiting'
    check (approval in ('awaiting', 'approved', 'rejected')),
  add column requested_amount numeric not null default 0,
  add column approval_at      timestamptz,
  add column approval_by      text,          -- 'customer' | 'vendor'
  add column approval_note    text,
  add column requested_at     timestamptz not null default now();

-- Agreed before this rule existed: stays in the balance as it was.
update public.addons
   set approval = 'approved', approval_by = 'vendor',
       requested_amount = coalesce(amount, 0),
       approval_at = coalesce(created_at, now()),
       requested_at = coalesce(created_at, now());

create or replace function public.addons_approval_guard()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(new.requested_amount, 0) = 0 then
      new.requested_amount := coalesce(new.amount, 0);
    end if;
    if new.approval = 'approved' then
      new.approval_at := coalesce(new.approval_at, now());
      new.approval_by := coalesce(new.approval_by, 'vendor');
    end if;
  elsif new.approval is distinct from old.approval then
    -- A decision (or a fresh request).
    if old.approval = 'rejected' and new.approval = 'approved' then
      raise exception 'The customer said no to this charge. Ask them again first.'
        using errcode = 'P0001';
    end if;
    if new.approval_note is not distinct from old.approval_note then
      new.approval_note := null;
    end if;
    if new.approval = 'awaiting' then
      new.approval_at := null; new.approval_by := null;
      new.requested_at := now();
    else
      new.approval_at := now();
      new.approval_by := coalesce(new.approval_by, 'vendor');
    end if;
  elsif new.amount is distinct from old.amount and coalesce(new.amount, 0) > 0
        and new.amount is distinct from old.requested_amount then
    -- The vendor changed the figure. The customer agreed to a figure,
    -- not to a line, so a changed figure needs a fresh yes.
    new.requested_amount := new.amount;
    if old.approval <> 'awaiting' then
      new.approval := 'awaiting';
      new.approval_at := null; new.approval_by := null; new.approval_note := null;
      new.requested_at := now();
    end if;
  end if;

  -- The one rule: billed only when approved.
  if new.approval = 'approved' then
    new.amount := new.requested_amount;
  else
    new.amount := 0;
  end if;
  return new;
end $$;

drop trigger if exists addons_approval_guard on public.addons;
create trigger addons_approval_guard
  before insert or update on public.addons
  for each row execute function public.addons_approval_guard();

create table public.addon_approval_log (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid,
  addon_id    uuid not null references public.addons(id) on delete cascade,
  order_id    text,
  event       text not null,   -- requested | approved | rejected | amount_changed | cancelled
  amount      numeric,
  description text,
  actor       text,            -- 'customer' | 'vendor'
  note        text,
  at          timestamptz not null default now()
);
create index addon_approval_log_order_idx on public.addon_approval_log (org_id, order_id, at);
alter table public.addon_approval_log enable row level security;
create policy addon_approval_log_select on public.addon_approval_log
  for select to authenticated
  using (org_id in (select a.org_id from public.addons a where a.id = addon_id));
-- Read through the addons row, so whoever may see the charge may see its
-- history and nobody else. Written only by the trigger below.

create or replace function public.addons_log_approval()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_event text; v_actor text; v_note text;
begin
  if tg_op = 'INSERT' then
    v_event := case when new.approval = 'approved' then 'approved' else 'requested' end;
  elsif new.approval is distinct from old.approval then
    v_event := case new.approval when 'awaiting' then 'requested' else new.approval end;
  elsif new.requested_amount is distinct from old.requested_amount then
    v_event := 'amount_changed';
    v_note := 'was ' || old.requested_amount::text;
  elsif new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    v_event := 'cancelled';
  else
    return new;
  end if;
  v_actor := case when v_event in ('approved', 'rejected')
                  then coalesce(new.approval_by, 'vendor') else 'vendor' end;
  insert into public.addon_approval_log (org_id, addon_id, order_id, event, amount, description, actor, note)
  values (new.org_id, new.id, new.order_id, v_event, new.requested_amount, new.description,
          v_actor, coalesce(v_note, new.approval_note));
  return new;
end $$;

drop trigger if exists addons_log_approval on public.addons;
create trigger addons_log_approval
  after insert or update on public.addons
  for each row execute function public.addons_log_approval();

-- The customer's view, on the tracking link.
create or replace function public.public_get_order_addons_impl(p_token text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare o public.orders%rowtype;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  select * into o from public.orders where tracking_token = p_token and deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  return jsonb_build_object(
    'ok', true,
    'order_ref', o.id,
    -- The customer's own code, on the customer's own link, until the
    -- crew has used it.
    'arrival_code', case
        when coalesce(o.supervisor_status, '') in ('', 'assigned', 'accepted')
         and lower(coalesce(o.status, '')) not in ('transit', 'delivered', 'closed', 'cancelled', 'completed')
        then o.arrival_code end,
    'gst_pct', case when coalesce(o.quote_gst_amount, 0) > 0 then coalesce(o.quote_gst_pct, 0) else 0 end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'description', a.description,
               'amount', a.requested_amount,
               'approval', a.approval, 'approval_at', a.approval_at,
               'approval_by', a.approval_by, 'requested_at', a.requested_at)
             order by a.requested_at)
        from public.addons a
       where a.order_id = o.id and a.org_id = o.org_id
         and a.status is distinct from 'cancelled'
    ), '[]'::jsonb)
  );
end $$;

create or replace function public.public_decide_addon_impl(p_token text, p_addon_id uuid, p_decision text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $$
declare
  o public.orders%rowtype;
  a public.addons%rowtype;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if p_decision is null or p_decision not in ('approved', 'rejected') then
    return jsonb_build_object('ok', false, 'reason', 'bad_decision');
  end if;
  select * into o from public.orders where tracking_token = p_token and deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  select * into a from public.addons
   where id = p_addon_id and order_id = o.id and org_id = o.org_id
     and status is distinct from 'cancelled'
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if a.approval <> 'awaiting' then
    return jsonb_build_object('ok', false, 'reason', 'already_decided', 'approval', a.approval);
  end if;
  update public.addons
     set approval = p_decision, approval_by = 'customer',
         approval_note = nullif(left(coalesce(p_note, ''), 300), '')
   where id = a.id;
  return jsonb_build_object('ok', true, 'approval', p_decision);
end $$;

-- Public wrappers with the same suspension gate as every other link RPC.
create or replace function public.public_get_order_addons(p_token text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_get_order_addons_impl(p_token);
end $$;

create or replace function public.public_decide_addon(p_token text, p_addon_id uuid, p_decision text, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_decide_addon_impl(p_token, p_addon_id, p_decision, p_note);
end $$;

revoke all on function public.public_get_order_addons_impl(text) from public, anon, authenticated;
revoke all on function public.public_decide_addon_impl(text, uuid, text, text) from public, anon, authenticated;
revoke all on function public.public_get_order_addons(text) from public;
revoke all on function public.public_decide_addon(text, uuid, text, text) from public;
grant execute on function public.public_get_order_addons(text) to anon, authenticated, service_role;
grant execute on function public.public_decide_addon(text, uuid, text, text) to anon, authenticated, service_role;

-- ---------- postflight ------------------------------------------------
do $post$
declare v_missing int; v_fy text;
begin
  v_fy := public.current_fy_ist();
  if v_fy !~ '^\d{4}-\d{2}$' then
    raise exception 'postflight: current_fy_ist returned %', v_fy;
  end if;
  select count(*) into v_missing from public.quotations
   where quote_no is null and deleted_at is null;
  if v_missing > 0 then
    raise notice 'postflight: % quotation(s) have no number (their org has no active quotation series)', v_missing;
  end if;
  if exists (select 1 from public.addons where approval <> 'approved') then
    raise exception 'postflight: an existing extra charge was left unapproved';
  end if;
  if exists (select 1 from public.addons where requested_amount is distinct from coalesce(amount, 0)) then
    raise exception 'postflight: an existing extra charge changed its amount';
  end if;
  if to_regprocedure('public.book_order_from_signed_quote(uuid,text)') is null then
    raise exception 'postflight: book_order_from_signed_quote missing';
  end if;
  if has_function_privilege('anon', 'public.book_order_from_signed_quote(uuid,text)', 'execute') then
    raise exception 'postflight: book_order_from_signed_quote is callable by anon';
  end if;
end $post$;

commit;
