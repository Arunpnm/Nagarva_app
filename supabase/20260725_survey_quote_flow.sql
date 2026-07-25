-- ============================================================================
-- 20260725_survey_quote_flow.sql
-- Item 8 (CORE V1, NAGARVA_STATUS.md): Survey -> Quotation -> Order flow.
--
-- READY TO RUN — NOT YET EXECUTED. Paste into the Supabase SQL editor
-- when convenient. Idempotent — safe to re-run.
--
-- SCOPE ASSUMPTION (no product spec was available for this pass — this is
-- a deliberate, documented default rather than a stall):
--   1. Vendor requests a survey for a lead -> gets a shareable link with a
--      random token. No customer login anywhere in this flow.
--   2. Customer opens the link, fills a structured move-details form
--      (rooms/items, addresses, move date, notes), submits via
--      submit_survey(token, ...) - a public (anon-callable) RPC that only
--      touches the one row matching that exact token.
--   3. Vendor reviews the submission and builds a quote using the existing
--      `quotations` table (already has items/charges/subtotal/gst/total -
--      this migration only adds what's missing: a share token and
--      acceptance tracking). Vendor shares a second link.
--   4. Customer opens the quote link, views it via
--      get_quotation_by_token(token) (public, read-only), and accepts by
--      typing their name (e-sign = typed name + timestamp, not a drawn
--      signature - no signature-pad dependency needed for v1).
--   5. Vendor converts an accepted quotation to a real order (app-side,
--      reuses the same insert pattern lead_detail_page_widget.dart already
--      uses for lead->order conversion).
--
-- Security model: all three customer-facing RPCs are `security definer`
-- and granted to `anon`, bypassing RLS entirely - each is scoped so a
-- caller can only ever affect/read the ONE row matching the exact token
-- they were given (never a list/browse operation). Tokens are
-- gen_random_uuid()::text (122 bits of entropy) so they are not
-- guessable/enumerable. This is the same trust model as any "share link"
-- feature (Google Docs, Dropbox, etc.) - anyone with the link can act on
-- that one record, nothing else.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- 1. surveys table -----------------------------------------------------------
create table if not exists public.surveys (
  id uuid primary key default extensions.gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  lead_id text references public.leads(id),
  token text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  customer_name text,
  customer_phone text,
  from_address text,
  to_address text,
  move_date date,
  -- Flexible room/item breakdown: [{"room": "Bedroom 1", "items": "Bed, 2 almirahs, ..."}]
  rooms jsonb not null default '[]'::jsonb,
  special_instructions text,
  status text not null default 'pending' check (status in ('pending', 'submitted')),
  submitted_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists surveys_org_id_idx on public.surveys (org_id);
create index if not exists surveys_lead_id_idx on public.surveys (lead_id);

alter table public.surveys enable row level security;

drop policy if exists surveys_org_isolation on public.surveys;
create policy surveys_org_isolation on public.surveys
  for all
  using (org_id = any (current_org_ids()))
  with check (org_id = any (current_org_ids()));

-- 2. quotations: token + acceptance tracking ---------------------------------
alter table public.quotations add column if not exists token text unique
  default encode(extensions.gen_random_bytes(24), 'hex');
alter table public.quotations add column if not exists survey_id uuid
  references public.surveys(id);
alter table public.quotations add column if not exists accepted_at timestamptz;
alter table public.quotations add column if not exists accepted_by_name text;
-- Backfill tokens for any pre-existing quotation rows (the default above
-- only applies to new rows).
update public.quotations set token = encode(extensions.gen_random_bytes(24), 'hex')
  where token is null;

-- 3. get_survey_by_token — public, read-only --------------------------------
-- Lets the public survey page show "already submitted" / "invalid link"
-- before rendering the form, and pre-fill from the lead if the vendor
-- already had customer_name/phone on file when the survey was created.
create or replace function public.get_survey_by_token(p_token text)
returns table (
  id uuid,
  status text,
  customer_name text,
  customer_phone text,
  org_name text
)
language sql
security definer
set search_path = public, extensions
as $$
  select s.id, s.status, s.customer_name, s.customer_phone, o.name as org_name
  from public.surveys s
  join public.organizations o on o.id = s.org_id
  where s.token = p_token;
$$;

revoke all on function public.get_survey_by_token(text) from public;
grant execute on function public.get_survey_by_token(text) to anon;

-- 5. submit_survey — public, one-row-only write ------------------------------
create or replace function public.submit_survey(
  p_token text,
  p_customer_name text,
  p_customer_phone text,
  p_from_address text,
  p_to_address text,
  p_move_date date,
  p_rooms jsonb,
  p_special_instructions text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.surveys
    set customer_name = p_customer_name,
        customer_phone = p_customer_phone,
        from_address = p_from_address,
        to_address = p_to_address,
        move_date = p_move_date,
        rooms = coalesce(p_rooms, '[]'::jsonb),
        special_instructions = p_special_instructions,
        status = 'submitted',
        submitted_at = now()
    where token = p_token
      and status = 'pending';
  return found;
end;
$$;

revoke all on function public.submit_survey(text, text, text, text, text, date, jsonb, text) from public;
grant execute on function public.submit_survey(text, text, text, text, text, date, jsonb, text) to anon;

-- 6. get_quotation_by_token — public, read-only ------------------------------
create or replace function public.get_quotation_by_token(p_token text)
returns table (
  id text,
  customer text,
  phone text,
  from_address text,
  to_address text,
  from_floor int,
  to_floor int,
  items jsonb,
  charges jsonb,
  subtotal numeric,
  gst_pct numeric,
  gst_amount numeric,
  total numeric,
  status text,
  accepted_at timestamptz,
  org_name text
)
language sql
security definer
set search_path = public, extensions
as $$
  select
    q.id, q.customer, q.phone, q.from_address, q.to_address,
    q.from_floor, q.to_floor, q.items, q.charges, q.subtotal,
    q.gst_pct, q.gst_amount, q.total, q.status, q.accepted_at,
    o.name as org_name
  from public.quotations q
  join public.organizations o on o.id = q.org_id
  where q.token = p_token;
$$;

revoke all on function public.get_quotation_by_token(text) from public;
grant execute on function public.get_quotation_by_token(text) to anon;

-- 7. accept_quotation — public, one-row-only write ---------------------------
create or replace function public.accept_quotation(p_token text, p_signature_name text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.quotations
    set status = 'accepted',
        accepted_at = now(),
        accepted_by_name = p_signature_name
    where token = p_token
      and status <> 'accepted';
  return found;
end;
$$;

revoke all on function public.accept_quotation(text, text) from public;
grant execute on function public.accept_quotation(text, text) to anon;
