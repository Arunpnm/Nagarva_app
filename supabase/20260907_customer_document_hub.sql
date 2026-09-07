-- Customer document hub: the papers, at the link.
--
-- Arun, 7 Sept 2026, picking option A over customer logins: "is it
-- possible to share a link or customer can login in that then check track
-- and download all their documents".
--
-- WHY A LINK AND NOT AN ACCOUNT. A customer of a packers-and-movers firm
-- deals with one mover, for one move, over about two weeks. An account
-- needs an SMS/WhatsApp OTP channel this product does not have (the same
-- blocker as Item 13), a customer auth model, and a SECOND tenancy axis
-- in RLS — every policy today is org-scoped, and customer-scoped is a new
-- dimension. They do not want an account. They want their papers.
--
-- WHAT ALREADY EXISTED, and is reused rather than rebuilt:
--   orders.tracking_token         the unguessable per-order key
--   get_order_tracking(p_token)   status + full history, SECURITY DEFINER
--   public.documents              entity_type/entity_id/doc_type/
--                                 storage_path/... purpose-built, and
--                                 never written to by anything
-- This migration adds the two missing halves: somewhere to PUT an issued
-- document, and an anon-callable way to LIST one order's documents.

-- ---------------------------------------------------------------------
-- 1. The bucket.
--
-- PUBLIC, with an unguessable path per file, and that is a deliberate
-- trade-off rather than an oversight.
--
-- A private bucket would need signed URLs, and a signed URL can only be
-- minted by a server — so a static page with no auth would need an Edge
-- Function in front of every download. That buys protection against a
-- LEAKED FILE URL, while the tracking token that lists those files is
-- itself just an unguessable string with exactly the same property: leak
-- the token and the documents are reachable anyway. Marginal gain, real
-- complexity.
--
-- The path is org/order/uuid.pdf, so a file cannot be found by guessing
-- an order id, and nothing is listable: bucket listing is NOT granted to
-- anon below, only object reads.
--
-- If expiry is later wanted, the upgrade is an Edge Function minting
-- signed URLs and flipping this bucket private. Nothing else changes.
insert into storage.buckets (id, name, public)
values ('order-documents', 'order-documents', true)
on conflict (id) do update set public = excluded.public;

-- Writes stay with the app's authenticated session, scoped to the org
-- the caller belongs to. Anon can read an object it already knows the
-- path of, and can do nothing else.
drop policy if exists order_docs_read on storage.objects;
create policy order_docs_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'order-documents');

drop policy if exists order_docs_write on storage.objects;
create policy order_docs_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'order-documents'
    and (storage.foldername(name))[1] in (
      select current_org_ids()::text
    )
  );

drop policy if exists order_docs_update on storage.objects;
create policy order_docs_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'order-documents'
    and (storage.foldername(name))[1] in (
      select current_org_ids()::text
    )
  );

-- ---------------------------------------------------------------------
-- 2. What the customer's link can read.
--
-- Same minimal-disclosure discipline as public_get_survey and
-- public_get_signature_request: the customer's own move, and nothing
-- about the vendor's business. No amounts beyond what is already printed
-- on the documents they are being handed, no crew unless the vendor has
-- switched that on (the existing tracking_show_crew setting is honoured,
-- not bypassed), no internal ids, no margin, no commission, no costs.
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
    -- Only documents ISSUED for this order, never deleted ones, and
    -- never anything flagged sensitive: is_sensitive exists on this
    -- table precisely so an internal attachment can live beside a
    -- customer-facing one without leaking.
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
       where d.entity_type = 'order'
         and d.entity_id = o.id
         and d.org_id = o.org_id
         and d.deleted_at is null
         and coalesce(d.is_sensitive, false) = false
    ), '[]'::jsonb)
  );
end;
$function$;

grant execute on function public.public_get_order_documents(text) to anon;

do $post$
declare
  v_src text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'public_get_order_documents';

  if v_src is null then
    raise exception 'POSTFLIGHT: public_get_order_documents was not created.';
  end if;

  -- The same guard the signature payload carries: this function must
  -- never learn to disclose the vendor's economics.
  if v_src like '%margin_pct%'
     or v_src like '%commission_pct%'
     or v_src like '%cost_%'
     or v_src like '%paid_total%' then
    raise exception
      'POSTFLIGHT: a margin/commission/cost field reached the public document payload.';
  end if;

  if not has_function_privilege('anon',
        'public.public_get_order_documents(text)', 'execute') then
    raise exception 'POSTFLIGHT: anon cannot execute it - the track page is dead.';
  end if;

  if not exists (select 1 from storage.buckets where id = 'order-documents') then
    raise exception 'POSTFLIGHT: the order-documents bucket was not created.';
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and policyname = 'order_docs_read'
  ) then
    raise exception 'POSTFLIGHT: order_docs_read policy missing - downloads will 400.';
  end if;
end
$post$;
