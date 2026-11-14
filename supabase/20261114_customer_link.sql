-- ============================================================
-- 20261114_customer_link.sql  (14 Nov 2026)
--
-- Batch 3: the customer's tracking link (list items 26, 28, 29, 31, 32).
--
--  * MOVING-DAY DETAILS (28): the supervisor's name and phone once one is
--    assigned, the vehicle number and the crew size, and a simple step
--    for the progress bar. The driver's name still follows the vendor's
--    "show crew on tracking" setting.
--  * PAY FROM THE LINK (29): the amount still due and the vendor's UPI ID,
--    so the page can open the customer's UPI app. "I have paid" tells
--    the vendor (an alert); it never marks anything paid - the vendor
--    confirms the money and records it in the app, exactly as today.
--  * PHOTOS IN A COMPLAINT (31): up to 3 small photos (the page shrinks
--    them) stored with the complaint.
--  * LINK LIFETIME (32): a link keeps working while the order is open and
--    for 90 days after it is closed. After that it says so, and the
--    vendor can send the customer what they need.
--
-- Run once in the Supabase SQL editor. Nothing is deleted.
-- ============================================================

begin;

alter table public.complaints add column if not exists photos jsonb not null default '[]'::jsonb;

-- What the customer still owes, by the same money rule the app uses.
create or replace function public.public_order_due(o public.orders)
returns numeric language sql stable security definer set search_path = public as $$
  select greatest(0, round(coalesce(public.order_total_due(o.id), o.amount, 0)
                           - coalesce(o.paid_total, 0)));
$$;
revoke all on function public.public_order_due(public.orders) from public, anon, authenticated;

create or replace function public.public_get_order_documents_impl(p_token text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  o     public.orders%rowtype;
  v_org public.organizations%rowtype;
  v_show_crew boolean;
  v_review public.reviews%rowtype;
  v_sup  public.staff%rowtype;
  v_crew int;
  v_step int;
  v_due  numeric;
  v_closed_at timestamptz;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  select * into o from public.orders
   where tracking_token = p_token and deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  -- 90 days after closing (list item 32).
  if lower(coalesce(o.status, '')) in ('closed', 'cancelled') then
    v_closed_at := coalesce(o.closed_at,
      (select max(h.changed_at) from public.order_status_history h
        where h.order_id = o.id and h.org_id = o.org_id
          and lower(h.status) in ('closed', 'cancelled')));
    if v_closed_at is not null and v_closed_at < now() - interval '90 days' then
      return jsonb_build_object('ok', false, 'reason', 'expired',
        'vendor_name', (select name from public.organizations where id = o.org_id),
        'vendor_phone', (select phone from public.organizations where id = o.org_id));
    end if;
  end if;

  select * into v_org from public.organizations where id = o.org_id;

  select coalesce((s.value #>> '{}') in ('true', '1'), false) into v_show_crew
    from public.settings s
   where s.org_id = o.org_id and s.key = 'tracking_show_crew';
  v_show_crew := coalesce(v_show_crew, false);

  select * into v_review from public.reviews
   where order_id = o.id and org_id = o.org_id limit 1;

  if o.supervisor_id is not null then
    select * into v_sup from public.staff
     where id::text = o.supervisor_id::text and org_id = o.org_id;
  end if;

  v_crew := case when jsonb_typeof(o.job_team) = 'array'
                 then jsonb_array_length(o.job_team) end;
  if coalesce(v_crew, 0) = 0 then
    v_crew := coalesce(o.chosen_crew, o.suggested_crew);
  end if;

  -- 1 Confirmed, 2 Crew assigned, 3 Packing, 4 On the way, 5 Delivered.
  v_step := case
    when lower(coalesce(o.status, '')) in ('delivered', 'closed') or o.job_end_time is not null then 5
    when lower(coalesce(o.status, '')) in ('transit', 'in_transit', 'arrived', 'unloading')
         or lower(coalesce(o.tracking_status, '')) like '%transit%' then 4
    when o.job_start_time is not null
         or lower(coalesce(o.status, '')) in ('packing', 'loading', 'loaded') then 3
    when o.supervisor_id is not null then 2
    else 1 end;

  v_due := public.public_order_due(o);

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
    'step',          v_step,
    'can_review',    (o.status in ('delivered', 'closed')),
    'my_rating',     v_review.rating,
    'my_comment',    v_review.comment,
    'show_crew',     v_show_crew,
    'vehicle_no',    o.vehicle_no,
    'driver_name',   case when v_show_crew then o.driver_name end,
    'supervisor_name',  case when lower(coalesce(o.status, '')) not in ('closed', 'cancelled') then v_sup.name end,
    'supervisor_phone', case when lower(coalesce(o.status, '')) not in ('closed', 'cancelled') then v_sup.phone end,
    'crew_count',    v_crew,
    'amount_due',    v_due,
    'paid_total',    coalesce(o.paid_total, 0),
    'upi_id',        case when v_due > 0 then nullif(trim(coalesce(v_org.upi_id, '')), '') end,
    'upi_name',      coalesce(nullif(trim(coalesce(v_org.beneficiary_name, '')), ''), v_org.name),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
               'status', h.status, 'note', h.note, 'changed_at', h.changed_at)
             order by h.changed_at)
        from public.order_status_history h
       where h.order_id = o.id and h.org_id = o.org_id
    ), '[]'::jsonb),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
               'doc_type', d.doc_type,
               'file_name', d.file_name,
               'size_bytes', d.size_bytes,
               'issued_at', d.created_at,
               'url', 'https://hqqcapifefsaqvotqvlt.supabase.co/storage/'
                      || 'v1/object/public/order-documents/' || d.storage_path)
             order by d.created_at)
        from public.documents d
       where d.org_id = o.org_id
         and d.deleted_at is null
         and coalesce(d.is_sensitive, false) = false
         and ((d.entity_type = 'order' and d.entity_id = o.id)
           or (d.entity_type = 'quotation' and o.quotation_id is not null
               and d.entity_id = o.quotation_id::text))
    ), '[]'::jsonb)
  );
end;
$function$;

-- "I have paid" from the link: an alert for the vendor, nothing more.
create or replace function public.public_report_payment_impl(p_token text, p_amount numeric, p_ref text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare o public.orders%rowtype; v_ref text;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  select * into o from public.orders where tracking_token = p_token and deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000000 then
    return jsonb_build_object('ok', false, 'reason', 'bad_amount');
  end if;
  -- One alert per order per 10 minutes is plenty.
  if exists (select 1 from public.notifications n
              where n.org_id = o.org_id and n.type = 'order_payment_reported'
                and n.body like '%' || o.id || '%'
                and n.created_at > now() - interval '10 minutes') then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  v_ref := nullif(left(regexp_replace(coalesce(p_ref, ''), '[^A-Za-z0-9 /-]', '', 'g'), 40), '');
  insert into public.notifications (org_id, recipient_staff_id, type, title, body, ref_lead_id)
  values (o.org_id, null, 'order_payment_reported', 'Customer says they paid',
          coalesce(nullif(btrim(coalesce(o.customer, '')), ''), 'The customer')
            || ' says they paid ₹' || to_char(round(p_amount), 'FM99,99,99,999')
            || ' by UPI for order ' || o.id
            || coalesce(' (reference ' || v_ref || ')', '')
            || '. Check your account, then record the payment.',
          o.lead_id::text);
  return jsonb_build_object('ok', true);
end;
$function$;

-- Complaints with photos (data URLs, already shrunk by the page).
create or replace function public.public_submit_complaint_impl(p_token text, p_type text, p_description text, p_photos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  o public.orders%rowtype;
  v_open int;
  v_photos jsonb := '[]'::jsonb;
  v_el jsonb;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if p_description is null or length(trim(p_description)) < 5 then
    return jsonb_build_object('ok', false, 'reason', 'too_short');
  end if;
  select * into o from public.orders where tracking_token = p_token and deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  select count(*) into v_open from public.complaints
   where order_id = o.id and org_id = o.org_id and coalesce(status, 'open') <> 'closed';
  if v_open >= 5 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;

  if p_photos is not null and jsonb_typeof(p_photos) = 'array' then
    if jsonb_array_length(p_photos) > 3 then
      return jsonb_build_object('ok', false, 'reason', 'too_many_photos');
    end if;
    for v_el in select value from jsonb_array_elements(p_photos) loop
      if jsonb_typeof(v_el) <> 'string'
         or left(v_el #>> '{}', 15) <> 'data:image/jpeg'
         or length(v_el #>> '{}') > 600000 then
        return jsonb_build_object('ok', false, 'reason', 'bad_photo');
      end if;
      v_photos := v_photos || jsonb_build_array(v_el);
    end loop;
  end if;

  insert into public.complaints (org_id, order_id, type, description, status, reported_at, photos)
  values (o.org_id, o.id, nullif(left(coalesce(p_type, ''), 60), ''),
          left(trim(p_description), 4000), 'open', now(), v_photos);

  begin
    insert into public.notifications (org_id, recipient_staff_id, type, title, body, ref_lead_id)
    values (o.org_id, null, 'order_complaint', 'Customer reported a problem',
            coalesce(nullif(btrim(coalesce(o.customer, '')), ''), 'The customer')
              || ' reported a problem on order ' || o.id
              || coalesce(' (' || nullif(left(coalesce(p_type, ''), 60), '') || ')', '')
              || case when jsonb_array_length(v_photos) > 0
                      then ' with ' || jsonb_array_length(v_photos) || ' photo(s)' else '' end || '.',
            o.lead_id::text);
  exception when others then null;
  end;
  return jsonb_build_object('ok', true);
end;
$function$;

-- Public wrappers, same suspension gate as every other link function.
create or replace function public.public_report_payment(p_token text, p_amount numeric, p_ref text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_report_payment_impl(p_token, p_amount, p_ref);
end $$;

create or replace function public.public_submit_complaint(p_token text, p_type text, p_description text, p_photos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_submit_complaint_impl(p_token, p_type, p_description, p_photos);
end $$;

revoke all on function public.public_report_payment_impl(text, numeric, text) from public, anon, authenticated;
revoke all on function public.public_submit_complaint_impl(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.public_report_payment(text, numeric, text) to anon, authenticated, service_role;
grant execute on function public.public_submit_complaint(text, text, text, jsonb) to anon, authenticated, service_role;

commit;
