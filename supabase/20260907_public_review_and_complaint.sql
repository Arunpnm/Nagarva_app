-- Let the customer rate the move, and raise a problem, from their link.
--
-- Arun, 7 Sept 2026: "we add review and complaints in this".
--
-- Both tables already exist and fit without a schema change: `reviews`
-- carries rating/comment/channel/branch, `complaints` carries
-- type/description/status/resolution. Neither has ever had a customer-
-- facing writer — reviews were something the vendor recorded, which
-- means they were only ever as good as somebody remembering to ask.
--
-- THE CUSTOMER SUPPLIES NOTHING THAT IDENTIFIES ANYTHING. org_id,
-- order_id and branch are all derived from the tracking token inside
-- these functions. A public writer that accepted an org_id would let
-- anyone write a five-star review into any tenant, or file a complaint
-- against a competitor.

do $pre$
begin
  if to_regprocedure('public.public_get_order_documents(text)') is null then
    raise exception
      'public_get_order_documents is missing. Run 20260907_customer_document_hub.sql first.';
  end if;

  if not exists (select 1 from information_schema.tables
                  where table_schema='public' and table_name='reviews') then
    raise exception 'reviews table is missing.';
  end if;

  if not exists (select 1 from information_schema.tables
                  where table_schema='public' and table_name='complaints') then
    raise exception 'complaints table is missing.';
  end if;
end
$pre$;

-- ---------------------------------------------------------------------
-- Review. One per order, and only once the move has actually happened.
create or replace function public.public_submit_review(
  p_token   text,
  p_rating  int,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  o public.orders%rowtype;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  if p_rating is null or p_rating < 1 or p_rating > 5 then
    return jsonb_build_object('ok', false, 'reason', 'bad_rating');
  end if;

  select * into o from public.orders
   where tracking_token = p_token and deleted_at is null;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  -- A review of a job that has not happened is noise, and invites a
  -- rating written in frustration mid-move that outlives the move.
  if o.status not in ('delivered', 'closed') then
    return jsonb_build_object('ok', false, 'reason', 'too_early');
  end if;

  -- One per order. Without this the link is an unlimited rating writer:
  -- anyone holding it could push the vendor's average wherever they
  -- liked, one submission at a time.
  if exists (select 1 from public.reviews
              where order_id = o.id and org_id = o.org_id) then
    return jsonb_build_object('ok', false, 'reason', 'already_reviewed');
  end if;

  insert into public.reviews
    (org_id, order_id, rating, comment, channel, branch,
     requested_at, responded_at, created_at)
  values
    (o.org_id, o.id, p_rating,
     nullif(left(coalesce(p_comment, ''), 2000), ''),
     -- Says where it came from, so a vendor can tell a link review from
     -- one they typed in themselves.
     'track_link',
     o.branch,
     now(), now(), now());

  return jsonb_build_object('ok', true);
end;
$function$;

-- ---------------------------------------------------------------------
-- Complaint. Allowed at ANY stage, deliberately: the moment something is
-- wrong is exactly when the customer needs to say so, and a move still
-- in progress is when it can still be fixed.
create or replace function public.public_submit_complaint(
  p_token       text,
  p_type        text,
  p_description text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  o public.orders%rowtype;
  v_open int;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  if p_description is null or length(trim(p_description)) < 5 then
    return jsonb_build_object('ok', false, 'reason', 'too_short');
  end if;

  select * into o from public.orders
   where tracking_token = p_token and deleted_at is null;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  -- Not a rate limit on the customer so much as a floor under the
  -- vendor's inbox: five open complaints on one order is already a phone
  -- call, not a sixth form submission.
  select count(*) into v_open
    from public.complaints
   where order_id = o.id and org_id = o.org_id
     and coalesce(status, 'open') <> 'closed';

  if v_open >= 5 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;

  insert into public.complaints
    (org_id, order_id, type, description, status, reported_at)
  values
    (o.org_id, o.id,
     nullif(left(coalesce(p_type, ''), 60), ''),
     left(trim(p_description), 4000),
     'open', now());

  return jsonb_build_object('ok', true);
end;
$function$;

grant execute on function public.public_submit_review(text, int, text) to anon;
grant execute on function public.public_submit_complaint(text, text, text) to anon;

-- ---------------------------------------------------------------------
-- The read side learns to report what the customer has already said, so
-- the page can show "you rated this" instead of offering the form again.
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
    -- Whether a review is even offered. The page must not show a rating
    -- form on a move that has not happened, only to have the write
    -- refused with 'too_early' after the customer has picked five stars.
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

do $post$
declare
  v_src text;
begin
  for v_src in
    select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('public_submit_review', 'public_submit_complaint',
                         'public_get_order_documents')
  loop
    -- Same guard the rest of the public family carries.
    if v_src like '%margin_pct%' or v_src like '%commission_pct%'
       or v_src like '%cost_%' or v_src like '%paid_total%' then
      raise exception
        'POSTFLIGHT: a margin/commission/cost field reached a public function.';
    end if;
  end loop;

  if not has_function_privilege('anon',
        'public.public_submit_review(text, int, text)', 'execute')
     or not has_function_privilege('anon',
        'public.public_submit_complaint(text, text, text)', 'execute') then
    raise exception 'POSTFLIGHT: anon cannot execute the writers.';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='public'
         and p.proname in ('public_submit_review','public_submit_complaint')
         and p.prosecdef) <> 2 then
    raise exception 'POSTFLIGHT: a public writer is not SECURITY DEFINER.';
  end if;

  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='public_get_order_documents';
  if v_src not like '%can_review%' then
    raise exception 'POSTFLIGHT: the reader was not updated - the page cannot tell when to offer a review.';
  end if;
  if v_src not like '%vendor_name%' or v_src not like '%documents%' then
    raise exception 'POSTFLIGHT: this replace dropped vendor_name or documents.';
  end if;
end
$post$;
