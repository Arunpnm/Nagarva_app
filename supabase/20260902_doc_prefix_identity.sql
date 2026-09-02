-- Document numbering identity: per-org prefixes, enforced unique, FY-scoped.
--
-- BACKGROUND. seed_org_number_series() gave every org the identical
-- calendar-year prefix ('2026/') at last_number 0, so every org's first
-- invoice rendered as the same string. Counters were isolated; the printed
-- number was not. Rule 46(b) permits a consecutive serial "in one or
-- multiple series" unique within a financial year, so multiple series
-- under one GSTIN are fine -- the defect was two orgs printing the SAME
-- number, not the number of series.
--
-- This migration does four things:
--   1. widens the prefix budget to 12 chars so an FY segment fits
--   2. makes a branding prefix unique across orgs, by trigger
--   3. makes the SEEDED default per-org, so uniqueness cannot block signup
--   4. moves the year segment from calendar year to financial year
--
-- PREFIX BUDGET, and why 12. Rule 46(b) caps the whole document number at
-- 16 characters. padding is 4, so the prefix may use at most 12:
--
--     BLR/2026-27/0001   = 16 exactly
--     ABC/2026-27/       = 12 exactly
--
-- The old CHECK allowed 10, which fits a calendar year ('BLR/2026/') but
-- not an FY. 12 is the statutory ceiling, not a round number.

begin;

-- ---------------------------------------------------------------- 1 ----
-- A CHECK cannot be replaced in place; drop then add, inside this
-- transaction so there is no window where the column is unconstrained.
alter table public.number_series
  drop constraint if exists number_series_prefix_format;
alter table public.number_series
  add constraint number_series_prefix_format
  check (prefix is not null and prefix ~ '^[A-Za-z0-9/-]{1,12}$');

-- ---------------------------------------------------------------- 2 ----
-- Which doc types carry the vendor's branding. The rest ('LR', 'CLM-',
-- 'PO-', 'GRN-', 'PS-', 'CTR-', 'STG-') are semantic abbreviations that
-- every org shares BY DESIGN, so they are exempt from uniqueness -- an
-- LR is an LR at every company.
create or replace function public.branding_doc_types()
returns text[] language sql immutable as $fn$
  select array['invoice','proforma','receipt','quotation',
               'voucher','credit_note','debit_note']::text[]
$fn$;

-- Prefixes held for an org that does not exist yet, so a branch planned
-- for next quarter cannot have its identity taken by a signup this week.
-- A row with org_id null is reserved and unclaimed: blocked for everyone
-- until claimed by setting org_id.
create table if not exists public.doc_prefix_reservations (
  prefix       text primary key
               check (prefix ~ '^[A-Za-z0-9/-]{1,12}$'),
  reserved_for text not null,
  org_id       uuid references public.organizations(id) on delete set null,
  created_at   timestamptz not null default now()
);

-- RLS on, no policies: platform-owned, reached only through the
-- SECURITY DEFINER functions below. Same convention as invite_codes.
alter table public.doc_prefix_reservations enable row level security;

comment on table public.doc_prefix_reservations is
  'Document prefixes held for organizations not yet created. Consulted by doc_prefix_conflict(); claim one by setting org_id when the org exists.';

-- Returns a human-readable reason the prefix is unavailable, or null.
-- SECURITY DEFINER because number_series is RLS-scoped per org -- a caller
-- cannot see another tenant's prefixes, which is exactly why this check
-- cannot live in the client.
create or replace function public.doc_prefix_conflict(
  p_prefix text, p_org_id uuid)
returns text
language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_other uuid;
  v_name  text;
  v_res   record;
begin
  if p_prefix is null then
    return null;
  end if;

  select ns.org_id into v_other
    from public.number_series ns
   where ns.prefix = p_prefix
     and ns.doc_type = any(public.branding_doc_types())
     and ns.org_id is distinct from p_org_id
   limit 1;

  if v_other is not null then
    select o.name into v_name from public.organizations o where o.id = v_other;
    -- Names the holder deliberately: for a multi-org owner "already used
    -- by APC Bengaluru" is actionable where "already in use" is not.
    return format('Prefix "%s" is already used by %s.',
                  p_prefix, coalesce(v_name, 'another organization'));
  end if;

  select * into v_res
    from public.doc_prefix_reservations r
   where r.prefix = p_prefix
     and r.org_id is distinct from p_org_id;
  if found then
    return format('Prefix "%s" is reserved for %s.',
                  p_prefix, v_res.reserved_for);
  end if;

  return null;
end;
$fn$;

create or replace function public.enforce_doc_prefix_unique()
returns trigger
language plpgsql security definer set search_path to 'public' as $fn$
declare v_msg text;
begin
  if NEW.doc_type <> all(public.branding_doc_types()) then
    return NEW;
  end if;
  v_msg := public.doc_prefix_conflict(NEW.prefix, NEW.org_id);
  if v_msg is not null then
    raise exception '%', v_msg using errcode = 'P0001';
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists number_series_prefix_unique on public.number_series;
create trigger number_series_prefix_unique
  before insert or update of prefix on public.number_series
  for each row execute function public.enforce_doc_prefix_unique();

-- The UI pre-check. Returns null when free, else the reason to display.
-- Membership is verified so this cannot be used to probe prefixes for an
-- org the caller has nothing to do with.
create or replace function public.check_doc_prefix(
  p_prefix text, p_org_id uuid)
returns text
language plpgsql security definer set search_path to 'public' as $fn$
begin
  if p_prefix is null or btrim(p_prefix) = '' then
    return 'Enter an invoice prefix.';
  end if;
  if p_prefix !~ '^[A-Za-z0-9/-]{1,12}$' then
    return 'Prefix must be 1-12 characters: letters, numbers, / or - only.';
  end if;
  if not exists (select 1 from public.org_members m
                  where m.user_id = auth.uid() and m.org_id = p_org_id) then
    raise exception 'Not a member of that organization' using errcode = '42501';
  end if;
  return public.doc_prefix_conflict(p_prefix, p_org_id);
end;
$fn$;

grant execute on function public.check_doc_prefix(text, uuid) to authenticated;

-- ---------------------------------------------------------------- 3 ----
-- A per-org SEEDED default, so enforcing uniqueness cannot make signup
-- fail. Derived from the org's own slug (APC Bengaluru -> 'APC'), with a
-- numeric tail only on collision. Budget is tight and deliberate: 3 chars
-- + '/' + '2026-27' + '/' = 12, the statutory ceiling, so the code cannot
-- grow past 3 characters.
create or replace function public.seed_prefix_for_org(
  p_org_id uuid, p_fy text)
returns text
language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_slug text;
  v_base text;
  v_code text;
  v_try  int := 0;
begin
  select o.slug into v_slug from public.organizations o where o.id = p_org_id;
  v_base := upper(regexp_replace(coalesce(v_slug, 'org'), '[^a-zA-Z0-9]', '', 'g'));
  if length(v_base) = 0 then
    v_base := 'ORG';
  end if;
  v_base := substr(v_base, 1, 3);
  v_code := v_base;

  loop
    exit when public.doc_prefix_conflict(
                v_code || '/' || p_fy || '/', p_org_id) is null;
    v_try := v_try + 1;
    if v_try > 99 then
      raise exception 'Could not derive a free document prefix for org %',
        p_org_id using errcode = 'P0001';
    end if;
    -- Keep the total at 3 by trading base characters for digits.
    v_code := substr(v_base, 1, 3 - length(v_try::text)) || v_try::text;
  end loop;

  return v_code || '/' || p_fy || '/';
end;
$fn$;

-- ---------------------------------------------------------------- 4 ----
-- Seeding, now FY-scoped and per-org.
--
-- WHAT HAPPENS AT THE FINANCIAL-YEAR BOUNDARY (00:00 IST, 1 April 2027):
--
--   * current_fy_ist() begins returning '2027-28'.
--   * No number_series row exists for that fy, so next_doc_number()
--     raises P0001 and the document does NOT generate. It fails loudly
--     rather than allocating under the wrong year -- that is deliberate.
--   * Rolling over CLONES the org's active rows into the new fy with
--     last_number reset to 0 and the FY SEGMENT OF THE PREFIX ADVANCED
--     ('BLR/2026-27/' -> 'BLR/2027-28/'). The org's own code ('BLR') is
--     carried forward; it is never re-derived, or a vendor's identity
--     would change on its own at a year boundary.
--   * So the first document of 2027-28 is BLR/2027-28/0001, and the old
--     year's rows stay in place -- re-issuing a document dated in
--     2026-27 still allocates from the 2026-27 series.
--
-- The rollover routine itself is scheduled for March 2027 (see CLAUDE.md's
-- dated section). This comment states the contract it must satisfy; note
-- that moving the year into the prefix means a rollover MUST rewrite the
-- prefix, not only insert rows for the new fy.
create or replace function public.seed_org_number_series(p_org_id uuid)
returns void
language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_fy     text := public.current_fy_ist();
  v_prefix text;
begin
  v_prefix := public.seed_prefix_for_org(p_org_id, v_fy);

  insert into public.number_series
    (org_id, doc_type, branch, fy, prefix, padding, last_number, active)
  select p_org_id, d.doc_type, null, v_fy,
         case when d.branding then v_prefix else d.prefix end,
         4, 0, true
  from (values
      ('invoice',     true,  ''),
      ('proforma',    true,  ''),
      ('receipt',     true,  ''),
      ('quotation',   true,  ''),
      ('voucher',     true,  ''),
      ('credit_note', true,  ''),
      ('debit_note',  true,  ''),
      ('lr',          false, 'LR'),
      ('claim',       false, 'CLM-'),
      ('contract',    false, 'CTR-'),
      ('grn',         false, 'GRN-'),
      ('payslip',     false, 'PS-'),
      ('po',          false, 'PO-'),
      ('storage_job', false, 'STG-')
    ) as d(doc_type, branding, prefix)
  on conflict (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''))
  do nothing;
end;
$fn$;

-- ---------------------------------------------------------------- 5 ----
-- Move the two new orgs onto the FY format while their counters are 0.
-- APC is deliberately NOT touched: it has issued 2026/0001 and 2026/0002,
-- and rewriting a prefix mid-counter leaves the issued numbers under an
-- identity the series no longer carries.
update public.number_series ns
   set prefix = 'BLR/2026-27/'
  from public.organizations o
 where o.id = ns.org_id and o.slug = 'apc-bengaluru'
   and ns.last_number = 0
   and ns.doc_type = any(public.branding_doc_types());

update public.number_series ns
   set prefix = 'CBE/2026-27/'
  from public.organizations o
 where o.id = ns.org_id and o.slug = 'apc-coimbatore'
   and ns.last_number = 0
   and ns.doc_type = any(public.branding_doc_types());

-- ---------------------------------------------------------------- 6 ----
-- Reserve Andhra Pradesh before BLR and CBE start issuing.
insert into public.doc_prefix_reservations (prefix, reserved_for)
values ('AP/2026-27/', 'APC Andhra Pradesh (org not yet created)')
on conflict (prefix) do nothing;

-- When the AP org is created, claim the reservation and apply it in the
-- same transaction, while its counters are still 0:
--
--   update public.doc_prefix_reservations
--      set org_id = '<new-org-uuid>' where prefix = 'AP/2026-27/';
--   update public.number_series ns set prefix = 'AP/2026-27/'
--    where ns.org_id = '<new-org-uuid>' and ns.last_number = 0
--      and ns.doc_type = any(public.branding_doc_types());

-- ---------------------------------------------------------------- 7 ----
-- POSTFLIGHT. Every org must render a different first number.
select o.slug, ns.prefix, ns.last_number,
       ns.prefix || lpad((ns.last_number + 1)::text, ns.padding, '0')
         as next_invoice_would_be
  from public.number_series ns
  join public.organizations o on o.id = ns.org_id
 where ns.doc_type = 'invoice'
 order by o.slug;

-- Must return ZERO rows: no branding prefix shared across orgs.
select prefix, count(distinct org_id) as orgs
  from public.number_series
 where doc_type = any(public.branding_doc_types())
 group by prefix having count(distinct org_id) > 1;

commit;
