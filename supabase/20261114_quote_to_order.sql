-- ============================================================
-- 20261114_quote_to_order.sql  (14 Nov 2026)
--
-- Batch 1 of Arun's 13 Nov test list. Two things:
--
--  1. SIGNING DID NOT BOOK THE ORDER (list item 15).
--     Seen on TES-Q/2026/0007: signed 11:29 PM, but the order was made
--     ten minutes later by the owner by hand. quotations.id is TEXT and
--     book_order_from_signed_quote took a UUID, so its first line
--     (`where id = p_quotation_id`) failed with "text = uuid"; the sign
--     functions catch every error from the booking (a booking problem
--     must never lose a signature), so the failure was silent. The
--     booking now takes the id as text. The uuid version stays as a thin
--     wrapper so the two sign functions that call it need no change.
--
--  2. THE CUSTOMER'S QUOTE PAGE SHOWS THE WHOLE QUOTATION (items 13, 14).
--     The sign page only received the items, subtotal, GST and total, so
--     it could not show a price breakup or print a proper document. It
--     now also receives: every charge line, the move details (addresses,
--     floors, lift, dates, vehicle, crew, CFT), the vendor's letterhead
--     (logo, address, GSTIN, phones, email, website), the vendor's own
--     quotation terms, and the stored quotation PDF (unsigned and signed).
--     Nothing here is new data: it is what the vendor's own quote PDF
--     already prints, sent to the one customer holding this link.
--
-- Run once in the Supabase SQL editor. Nothing is deleted. Checked after.
-- ============================================================

begin;

do $pre$
begin
  if to_regprocedure('public.book_order_from_signed_quote(uuid,text)') is null then
    raise exception 'run 20261113_customer_journey.sql first';
  end if;
end $pre$;

-- ---------- 1. booking takes the quote id as text ----------------------
create or replace function public.book_order_from_signed_quote(
  p_quotation_id text,
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
  select * into q from public.quotations
   where id = p_quotation_id and deleted_at is null;
  if not found then return null; end if;

  update public.quotations
     set status = 'accepted',
         accepted_at = coalesce(accepted_at, now()),
         accepted_by_name = coalesce(accepted_by_name, p_signed_by)
   where id = q.id;

  if q.lead_id is null then return null; end if;

  select o.id into v_order_id
    from public.orders o
   where o.org_id = q.org_id
     and o.deleted_at is null
     and lower(coalesce(o.status, '')) <> 'cancelled'
     and (o.quotation_id::text = q.id::text or o.lead_id::text = q.lead_id::text)
   order by o.created_at desc
   limit 1;
  if v_order_id is not null then
    -- Re-signed after "Customer wants changes" (list item 17): the order
    -- takes the new figures, as long as no invoice has been made on it.
    -- An invoiced order is never re-priced from here.
    update public.orders o set
      amount = coalesce(q.total, o.amount),
      move_date = coalesce(q.moving_date::date, o.move_date),
      quote_items = q.items, quote_charges = q.charges,
      quote_subtotal = q.subtotal, quote_gst_pct = q.gst_pct,
      quote_gst_amount = q.gst_amount, quote_total = q.total,
      quote_version = coalesce(q.version, 1),
      quote_snapshot_at = now()
     where o.id = v_order_id
       and coalesce(o.invoice_no, '') = ''
       and coalesce(o.quote_version, 0) < coalesce(q.version, 1);
    return v_order_id;
  end if;

  select * into l from public.leads where id::text = q.lead_id::text;

  if coalesce(q.phone, l.phone) is not null then
    select c.id into v_cust from public.customers c
     where c.org_id = q.org_id and c.deleted_at is null
       and (c.phone_normalized = regexp_replace(coalesce(q.phone, l.phone), '\D', '', 'g')
            or c.phone = coalesce(q.phone, l.phone))
     limit 1;
  end if;

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
  values (q.org_id, v_order_id, 'booked',
          'Order confirmed: quotation signed by ' || coalesce(p_signed_by, 'the customer'));

  update public.leads set status = 'confirmed' where id::text = q.lead_id::text;
  begin
    update public.leads set order_id = v_order_id where id::text = q.lead_id::text;
  exception when others then null;
  end;

  return v_order_id;
end $$;

-- The old uuid entry point, kept so the sign functions need no change.
create or replace function public.book_order_from_signed_quote(
  p_quotation_id uuid,
  p_signed_by     text
) returns text language sql security definer set search_path = public as $$
  select public.book_order_from_signed_quote(p_quotation_id::text, p_signed_by);
$$;

revoke all on function public.book_order_from_signed_quote(text, text) from public, anon, authenticated;
revoke all on function public.book_order_from_signed_quote(uuid, text) from public, anon, authenticated;

-- ---------- 2. the whole quotation for the sign page --------------------
create or replace function public.public_get_signature_request_impl(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v   public.document_signatures%rowtype;
  o   public.orders%rowtype;
  q   public.quotations%rowtype;
  g   public.organizations%rowtype;
  doc jsonb := '{}'::jsonb;
  v_signed jsonb := '{}'::jsonb;
  v_pdf text;
  v_quote_pdf text;
  v_terms text;
  v_base constant text :=
    'https://hqqcapifefsaqvotqvlt.supabase.co/storage/v1/object/public/order-documents/';
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

  select * into g from public.organizations where id = v.org_id;

  -- The vendor's own quotation terms, else their standard document terms.
  select nullif(trim(value #>> '{}'), '') into v_terms from public.app_settings
   where org_id = v.org_id and category = 'documents' and key = 'quotation_terms';
  if v_terms is null then
    select nullif(trim(value #>> '{}'), '') into v_terms from public.app_settings
     where org_id = v.org_id and category = 'documents' and key = 'document_terms';
  end if;

  if v.document_type = 'quote' then
    select * into q from public.quotations where id::text = v.document_id;
    if found then
      select v_base || d.storage_path into v_quote_pdf
        from public.documents d
       where d.org_id = v.org_id and d.deleted_at is null
         and d.entity_type = 'quotation' and d.entity_id = q.id::text
         and d.doc_type = 'quote'
       order by d.created_at desc limit 1;

      doc := jsonb_build_object(
        'document_no',   coalesce(q.quote_no, upper(left(q.id::text, 8))),
        'quote_no',      q.quote_no,
        'version',       coalesce(q.version, 1),
        'quote_date',    q.created_at,
        'valid_until',   q.valid_until,
        'customer',      q.customer,
        'customer_phone', q.phone,
        'from_city',     q.from_city,
        'to_city',       q.to_city,
        'from_address',  q.from_address,
        'to_address',    q.to_address,
        'from_floor',    q.from_floor,
        'to_floor',      q.to_floor,
        'from_has_lift', q.from_has_lift,
        'to_has_lift',   q.to_has_lift,
        'move_date',     q.moving_date,
        'packing_date',  q.packing_date,
        'delivery_date', q.delivery_date,
        'total_cft',     q.total_cft,
        'vehicle',       coalesce(q.chosen_vehicle, q.suggested_vehicle, q.vehicle_type),
        'crew',          coalesce(q.chosen_crew, q.suggested_crew),
        'package',       coalesce(q.chosen_package, q.suggested_package, q.charges->>'_suggestedPackage'),
        'load_type',     q.load_type,
        'declared_value', q.declared_value,
        'fov_amount',    q.fov_amount,
        'items',         coalesce(q.items, '[]'::jsonb),
        'charges',       coalesce(q.charges, '{}'::jsonb),
        'subtotal',      q.subtotal,
        'gst_pct',       q.gst_pct,
        'gst_amount',    q.gst_amount,
        'total',         q.total,
        'interstate',    case when q.charges->>'_gstType' = 'inter' then true
                              when q.charges->>'_gstType' = 'intra' then false end,
        'quote_pdf_url', v_quote_pdf
      );
      if v.status = 'signed' then
        select * into o from public.orders ord
         where ord.org_id = v.org_id and ord.deleted_at is null
           and lower(coalesce(ord.status, '')) <> 'cancelled'
           and (ord.quotation_id::text = q.id::text
                or (q.lead_id is not null and ord.lead_id::text = q.lead_id::text))
         order by ord.created_at desc limit 1;
        select v_base || d.storage_path into v_pdf
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
        'document_no',  o.invoice_no,
        'customer',     o.customer,
        'from_city',    o.from_city,
        'to_city',      o.to_city,
        'from_address', o.from_address,
        'to_address',   o.to_address,
        'move_date',    o.move_date,
        'items',        coalesce(o.quote_items, '[]'::jsonb),
        'charges',      coalesce(o.quote_charges, '{}'::jsonb),
        'total',        o.amount
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
    'vendor_name',   g.name,
    'vendor_phone',  g.phone,
    'vendor', jsonb_build_object(
      'name',     g.name,
      'tagline',  g.tagline,
      'logo_url', g.logo_url,
      'address',  g.address,
      'city',     g.city,
      'state',    g.state,
      'pincode',  g.pincode,
      'gstin',    g.gstin,
      'phones',   to_jsonb(array_remove(array[g.phone, g.phone_secondary, g.phone_tertiary], null)),
      'email',    g.support_email,
      'website',  g.website,
      'color',    g.primary_color
    ),
    'terms',         case when v_terms is null then '[]'::jsonb
                          else to_jsonb(array_remove(array(
                            select nullif(trim(t), '') from regexp_split_to_table(v_terms, E'\n') t
                          ), null)) end,
    'customer_name', v.customer_name,
    'document_type', v.document_type,
    'document_id',   v.document_id,
    'signed',        false
  ) || doc || v_signed;
end;
$function$;

do $post$
begin
  if to_regprocedure('public.book_order_from_signed_quote(text,text)') is null then
    raise exception 'postflight: text booking missing';
  end if;
  if has_function_privilege('anon', 'public.book_order_from_signed_quote(text,text)', 'execute') then
    raise exception 'postflight: booking callable by anon';
  end if;
end $post$;

commit;
