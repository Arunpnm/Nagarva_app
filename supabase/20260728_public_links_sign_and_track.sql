-- ============================================================================
-- 20260728_public_links_sign_and_track.sql
--
-- Live-test fix brief #2, items 3 (customer signature) and 6 (customer
-- order tracking). Both are the same shape as the existing survey/quote
-- public links, so they share one migration.
--
-- SECURITY POSTURE — the whole point of this design:
--   Neither of these opens anon RLS on `quotations`, `orders`, or any
--   other real table. The token is the credential, and it is only ever
--   dereferenced inside a SECURITY DEFINER function that the anon role
--   cannot call directly. The Edge Functions (sign-document, track-order)
--   run as service_role and are the only callers. This mirrors the
--   staff-PIN pattern already used by verify_staff_pin / verify_org_pin.
--
-- Idempotent — safe to re-run.
--
-- NOTE ON orders.id: it is TEXT ('NGV-1007'), not uuid. Every reference
-- to it below is text, and any join back to it needs no cast because both
-- sides are already text. document_signatures.document_id is text for
-- exactly this reason — it holds either a quotations.id (uuid-as-text) or
-- an orders.id (NGV-XXXX), so it cannot be typed uuid.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Item 3 — document_signatures
-- ---------------------------------------------------------------------------
create table if not exists public.document_signatures (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  document_type text not null check (document_type in ('quote', 'invoice')),
  -- text, not uuid: holds a quotations.id OR an orders.id (NGV-XXXX).
  document_id text not null,
  sign_token text not null unique
    default encode(extensions.gen_random_bytes(24), 'hex'),
  customer_name text,
  -- base64 PNG from the signature pad. Kept in-row rather than in Storage
  -- so it comes back with the row and needs no second signed-URL round
  -- trip; these are a few KB of monochrome PNG.
  signature_data text,
  signed_at timestamptz,
  signer_ip text,
  status text not null default 'pending'
    check (status in ('pending', 'signed', 'declined')),
  created_at timestamptz not null default now()
);

-- One live signature request per document. Re-sending the link for the
-- same document reuses the row rather than minting a second token, so an
-- old link can't be signed after a new one was issued.
create unique index if not exists document_signatures_doc_key
  on public.document_signatures (org_id, document_type, document_id);

create index if not exists document_signatures_org_idx
  on public.document_signatures (org_id);

alter table public.document_signatures enable row level security;
drop policy if exists org_isolation on public.document_signatures;
create policy org_isolation on public.document_signatures
  for all to authenticated
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- ---------------------------------------------------------------------------
-- Item 6 — order tracking token + status history
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists tracking_token text;

-- Backfill existing orders so every order has a shareable link, then make
-- the column unique. Partial-unique so rows that somehow end up null
-- don't collide with each other.
update public.orders
   set tracking_token = encode(extensions.gen_random_bytes(24), 'hex')
 where tracking_token is null;

alter table public.orders
  alter column tracking_token
  set default encode(extensions.gen_random_bytes(24), 'hex');

create unique index if not exists orders_tracking_token_key
  on public.orders (tracking_token)
  where tracking_token is not null;

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  -- text to match orders.id (NGV-XXXX).
  order_id text not null references public.orders(id) on delete cascade,
  status text not null,
  note text,
  changed_at timestamptz not null default now(),
  changed_by uuid
);

create index if not exists order_status_history_order_idx
  on public.order_status_history (order_id, changed_at desc);

alter table public.order_status_history enable row level security;
drop policy if exists org_isolation on public.order_status_history;
create policy org_isolation on public.order_status_history
  for all to authenticated
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- ---------------------------------------------------------------------------
-- Token-keyed accessors. SECURITY DEFINER, granted to service_role ONLY —
-- the Edge Functions are the sole callers. Explicit DROPs first, per
-- CLAUDE.md's convention, so a later change to the return shape can't hit
-- a 42P13.
-- ---------------------------------------------------------------------------

drop function if exists public.get_signature_request(text);

create or replace function public.get_signature_request(p_token text)
returns table (
  signature_id uuid,
  doc_type text,
  doc_id text,
  sig_status text,
  sig_customer_name text,
  sig_signed_at timestamptz,
  org_name text,
  payload jsonb
)
language plpgsql
security definer
set search_path = public, extensions
stable
as $$
begin
  -- Column aliases throughout (s_*/o_*) rather than bare names: this
  -- function's OUT parameters are implicitly declared plpgsql variables,
  -- and a bare column reference matching one of them is ambiguous
  -- (42702). Same class of bug that bit verify_org_pin() live.
  return query
  select ds.id,
         ds.document_type,
         ds.document_id,
         ds.status,
         ds.customer_name,
         ds.signed_at,
         o.name,
         case ds.document_type
           when 'quote' then (
             select to_jsonb(q) - 'org_id'
             from public.quotations q
             where q.id = ds.document_id and q.org_id = ds.org_id
           )
           else (
             select to_jsonb(ord) - 'org_id' - 'job_otp'
             from public.orders ord
             where ord.id = ds.document_id and ord.org_id = ds.org_id
           )
         end
  from public.document_signatures ds
  join public.organizations o on o.id = ds.org_id
  where ds.sign_token = p_token
  limit 1;
end;
$$;

revoke all on function public.get_signature_request(text) from public;
revoke all on function public.get_signature_request(text) from anon;
revoke all on function public.get_signature_request(text) from authenticated;
grant execute on function public.get_signature_request(text) to service_role;

drop function if exists public.submit_signature(text, text, text, text);

create or replace function public.submit_signature(
  p_token text,
  p_signature_data text,
  p_customer_name text,
  p_signer_ip text
)
returns table (ok boolean, message text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row public.document_signatures%rowtype;
begin
  select * into v_row
  from public.document_signatures
  where sign_token = p_token;

  if not found then
    return query select false, 'Invalid or expired link'::text;
    return;
  end if;

  -- Already signed: succeed idempotently rather than erroring, so a
  -- double-tap or a refresh on the customer's phone doesn't look broken.
  if v_row.status = 'signed' then
    return query select true, 'Already signed'::text;
    return;
  end if;

  if p_signature_data is null or length(trim(p_signature_data)) = 0 then
    return query select false, 'Signature is required'::text;
    return;
  end if;

  update public.document_signatures
     set signature_data = p_signature_data,
         customer_name  = coalesce(nullif(trim(p_customer_name), ''),
                                   customer_name),
         signer_ip      = p_signer_ip,
         signed_at      = now(),
         status         = 'signed'
   where sign_token = p_token;

  return query select true, 'Signed'::text;
end;
$$;

revoke all on function
  public.submit_signature(text, text, text, text) from public;
revoke all on function
  public.submit_signature(text, text, text, text) from anon;
revoke all on function
  public.submit_signature(text, text, text, text) from authenticated;
grant execute on function
  public.submit_signature(text, text, text, text) to service_role;

drop function if exists public.get_order_tracking(text);

create or replace function public.get_order_tracking(p_token text)
returns table (
  order_ref text,
  cust_name text,
  from_city text,
  to_city text,
  move_date date,
  current_status text,
  tracking_stage text,
  org_name text,
  show_crew boolean,
  crew_vehicle text,
  crew_driver text,
  crew_phone text,
  history jsonb
)
language plpgsql
security definer
set search_path = public, extensions
stable
as $$
declare
  v_show_crew boolean;
  v_org uuid;
begin
  select ord.org_id into v_org
  from public.orders ord
  where ord.tracking_token = p_token;

  if v_org is null then
    return;  -- unknown token: zero rows, Edge Function turns that into 404
  end if;

  -- Crew details are opt-in per org (brief item 6.2: "only if org enables
  -- it in settings"). Absent setting = not shown.
  select coalesce((s.value #>> '{}') in ('true', '1'), false)
    into v_show_crew
  from public.settings s
  where s.org_id = v_org and s.key = 'tracking_show_crew';
  v_show_crew := coalesce(v_show_crew, false);

  return query
  select ord.id,
         ord.customer,
         ord.from_city,
         ord.to_city,
         ord.move_date::date,
         ord.status,
         ord.tracking_status,
         o.name,
         v_show_crew,
         case when v_show_crew then ord.vehicle_no end,
         case when v_show_crew then ord.driver_name end,
         -- Never expose a phone number unless crew display is enabled.
         case when v_show_crew then ord.phone end,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'status', h.status,
                    'note', h.note,
                    'changed_at', h.changed_at)
                  order by h.changed_at)
           from public.order_status_history h
           where h.order_id = ord.id and h.org_id = ord.org_id
         ), '[]'::jsonb)
  from public.orders ord
  join public.organizations o on o.id = ord.org_id
  where ord.tracking_token = p_token
  limit 1;
end;
$$;

revoke all on function public.get_order_tracking(text) from public;
revoke all on function public.get_order_tracking(text) from anon;
revoke all on function public.get_order_tracking(text) from authenticated;
grant execute on function public.get_order_tracking(text) to service_role;

commit;

-- Verify after running:
--   \d document_signatures
--   \d order_status_history
--   select count(*) filter (where tracking_token is null) as missing_token,
--          count(*) as total
--     from public.orders;                       -- expect missing_token = 0
--   select proname from pg_proc
--    where proname in ('get_signature_request','submit_signature',
--                      'get_order_tracking');   -- expect 3 rows
--   select relname, relrowsecurity from pg_class
--    where relname in ('document_signatures','order_status_history');
