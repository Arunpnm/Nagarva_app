-- The customer's link should show their QUOTE too.
--
-- Arun, 7 Sept 2026: "and money receipt and also add quote then other
-- were missing".
--
-- A quotation belongs to a QUOTATION, not an order — at quote time the
-- order does not exist, which is the whole point of a quote. So the PDF
-- is stored with entity_type='quotation', and this teaches the reader to
-- pick it up through the order's own `quotation_id` once the lead
-- converts.
--
-- Consequence, stated rather than discovered: a quote sent to somebody
-- who never books is stored but never surfaced. That is correct — there
-- is no order, so there is no tracking link to hang it on.
--
-- MONEY RECEIPT needed no change and never did. It is already wired with
-- docType 'receipt'; it produced nothing on the test order because that
-- order has zero payment_entries and paid_total 0, so there was nothing
-- to receipt. Checked in the data before assuming a fault.

do $pre$
begin
  if to_regprocedure('public.public_get_order_documents(text)') is null then
    raise exception
      'public_get_order_documents is missing. Run the document hub migration first.';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='orders'
                    and column_name='quotation_id') then
    raise exception
      'orders.quotation_id does not exist - this migration joins the quote through it.';
  end if;
end
$pre$;

create or replace function public.public_get_order_documents(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  o     public.orders%rowtype;
  v_org public.organizations%rowtype;
  v_show_crew boolean;
  v_review public.reviews%rowtype;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  select * into o
    from public.orders
   where tracking_token = p_token
     and deleted_at is null;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  select * into v_org from public.organizations where id = o.org_id;

  select coalesce((s.value #>> '{}') in ('true', '1'), false)
    into v_show_crew
    from public.settings s
   where s.org_id = o.org_id and s.key = 'tracking_show_crew';
  v_show_crew := coalesce(v_show_crew, false);

  select * into v_review
    from public.reviews
   where order_id = o.id and org_id = o.org_id
   limit 1;

  return jsonb_build_object(
    'ok',            true,
    'vendor_name',   v_org.name,
    'vendor_phone',  v_org.phone,
    'order_ref',     o.id,
    'customer_name', o.customer,
    'from_city',     o.from_city,
    'to_city',       o.to_city,
    'move_date',     o.move_date,
    'status',        o.status,
    'tracking_status', o.tracking_status,
    'invoice_no',    o.invoice_no,
    'can_review',    (o.status in ('delivered', 'closed')),
    'my_rating',     v_review.rating,
    'my_comment',    v_review.comment,
    'show_crew',     v_show_crew,
    'vehicle_no',    case when v_show_crew then o.vehicle_no end,
    'driver_name',   case when v_show_crew then o.driver_name end,
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
               'status', h.status,
               'note', h.note,
               'changed_at', h.changed_at)
             order by h.changed_at)
        from public.order_status_history h
       where h.order_id = o.id and h.org_id = o.org_id
    ), '[]'::jsonb),
    -- This order's own documents, PLUS the quotation it came from.
    -- Still org-scoped, still excluding deleted and sensitive rows.
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
               'doc_type', d.doc_type,
               'file_name', d.file_name,
               'size_bytes', d.size_bytes,
               'issued_at', d.created_at,
               'url', 'https://hqqcapifefsaqvotqvlt.supabase.co/storage/'
                      || 'v1/object/public/order-documents/'
                      || d.storage_path)
             order by d.created_at)
        from public.documents d
       where d.org_id = o.org_id
         and d.deleted_at is null
         and coalesce(d.is_sensitive, false) = false
         and (
              (d.entity_type = 'order' and d.entity_id = o.id)
           or (d.entity_type = 'quotation'
               and o.quotation_id is not null
               and d.entity_id = o.quotation_id::text)
         )
    ), '[]'::jsonb)
  );
end;
$function$;

do $post$
declare
  v_src text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'public_get_order_documents';

  if v_src is null or v_src not like '%quotation_id%' then
    raise exception 'POSTFLIGHT: the reader does not join the quotation.';
  end if;

  -- Everything this function already promised must survive the replace.
  if v_src not like '%vendor_name%' or v_src not like '%can_review%'
     or v_src not like '%history%' then
    raise exception 'POSTFLIGHT: this replace dropped a field the page reads.';
  end if;

  if v_src like '%margin_pct%' or v_src like '%commission_pct%'
     or v_src like '%cost_%' or v_src like '%paid_total%' then
    raise exception
      'POSTFLIGHT: a margin/commission/cost field reached the public payload.';
  end if;

  if not has_function_privilege('anon',
        'public.public_get_order_documents(text)', 'execute') then
    raise exception 'POSTFLIGHT: anon lost execute - the track page is dead.';
  end if;
end
$post$;
