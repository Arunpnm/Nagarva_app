-- Show the customer WHAT they are signing.
--
-- Arun, 7 Sept 2026, after being shown the live sign page: build the
-- "require the invoice" option, "and if possible try to share the doc in
-- this link where they can download too".
--
-- THE DEFECT THIS CLOSES. `public_get_signature_request` returned five
-- fields: ok, vendor_name, customer_name, document_type, document_id. No
-- amount, no line items, no invoice number. So a customer opened a link,
-- was told they were signing "invoice ARUN-PACKERS-AND-COURIERS-1002" —
-- an ORDER id, on an order with no invoice at all — and was asked to draw
-- a signature having been shown no figure of any kind.
--
-- A signature exists to settle a dispute months later. One captured
-- against an internal id, with no amount on screen, evidences that
-- somebody drew a squiggle; it does not evidence what they agreed to.
-- That is the real defect, and the misleading label was a symptom.
--
-- WHAT IS DISCLOSED, AND WHY EXACTLY THIS SET. The fields are the
-- allow-list settled on 17 Aug 2026 for `get_signature_request` — chosen
-- then by reading what a signer's own document card renders, and already
-- reviewed for what a link holder must NOT see. Reusing it rather than
-- inventing a second answer to the same question:
--   invoice number, customer, route, move date, line items, total.
-- Still excluded, deliberately: margin_pct, commission_pct, cost fields,
-- internal ids, timestamps, workflow state, notes, billing-party and
-- e-invoicing fields. A link holder is not a member of the org.
--
-- THE TOTAL IS `orders.amount`, NOT A RECOMPUTATION. Verified by reading
-- `_generateInvoice`, which passes `total: amount` to the PDF and derives
-- the GST split downward from it (GST is inclusive here). So this returns
-- the same number the invoice prints. Recomputing it in SQL would create
-- a second definition of the invoice total, which is how the two
-- net-profit views ended up disagreeing.
--
-- A QUOTE signature reads from `quotations` instead, which carries its
-- own subtotal/gst/total. Same defect, same fix, one function.

do $pre$
begin
  if to_regprocedure('public.public_get_signature_request(text)') is null then
    raise exception
      'public_get_signature_request(text) does not exist. Check the signature before running this.';
  end if;

  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'orders'
       and column_name in ('invoice_no', 'amount', 'quote_items')
    having count(*) = 3
  ) then
    raise exception
      'orders is missing one of invoice_no / amount / quote_items - this migration reads all three.';
  end if;
end
$pre$;

create or replace function public.public_get_signature_request(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v   public.document_signatures%rowtype;
  o   public.orders%rowtype;
  q   public.quotations%rowtype;
  doc jsonb := '{}'::jsonb;
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

  if v.document_type = 'quote' then
    select * into q from public.quotations where id::text = v.document_id;
    if found then
      doc := jsonb_build_object(
        'document_no', q.id::text,
        'customer',    q.customer,
        'from_city',   q.from_city,
        'to_city',     q.to_city,
        'items',       coalesce(q.items, '[]'::jsonb),
        'subtotal',    q.subtotal,
        'gst_pct',     q.gst_pct,
        'gst_amount',  q.gst_amount,
        'total',       q.total
      );
    end if;
  else
    -- order_id first (written since 7 Sept 2026), document_id as the
    -- fallback so every row created before that still resolves.
    select * into o from public.orders
     where id = coalesce(v.order_id, v.document_id);
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
        -- The invoice's own total. See the header note.
        'total',       o.amount
      );
    end if;
  end if;

  return jsonb_build_object(
    'ok',            true,
    'vendor_name',   (select org.name from public.organizations org
                       where org.id = v.org_id),
    'customer_name', v.customer_name,
    'document_type', v.document_type,
    'document_id',   v.document_id
  ) || doc;
end;
$function$;

do $post$
declare
  v_src text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'public_get_signature_request';

  if v_src is null or v_src not like '%document_no%' then
    raise exception 'POSTFLIGHT: public_get_signature_request does not return document_no.';
  end if;

  if v_src not like '%vendor_name%' then
    raise exception 'POSTFLIGHT: the vendor_name added on 6 Sept was lost by this replace.';
  end if;

  -- Anything that would turn a disclosure fix into a disclosure LEAK.
  if v_src like '%margin_pct%'
     or v_src like '%commission_pct%'
     or v_src like '%cost_%' then
    raise exception
      'POSTFLIGHT: a margin/commission/cost field reached the public signature payload.';
  end if;

  if not has_function_privilege('anon',
        'public.public_get_signature_request(text)', 'execute') then
    raise exception 'POSTFLIGHT: anon lost execute - the sign page cannot call it.';
  end if;

  if not (select prosecdef
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'public_get_signature_request') then
    raise exception 'POSTFLIGHT: public_get_signature_request is no longer SECURITY DEFINER.';
  end if;
end
$post$;
