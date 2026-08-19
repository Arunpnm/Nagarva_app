-- ============================================================
-- supabase/20260818_seed_new_org_series_and_docsettings.sql
--
-- Fixes the gap found while re-examining the invite-code gate (17 Aug
-- 2026): `create_org_with_owner()` seeds `pricing_config` but nothing
-- else, so a real tenant signs up with no `number_series` and no
-- `app_settings` rows.
--
-- Evidence this is live, not hypothetical: "Ponci Packers And Movers"
-- (slug ponci-packers-and-movers, created 2026-08-16 via the real
-- create-org path) has pricing_config 1 row, number_series 0,
-- app_settings 0. APC has 19/8, TEST 1 has 14/8.
--
-- CONSEQUENCE BEING FIXED: `next_doc_number()` RAISES (errcode P0001,
-- 'No active number series configured for org=...') when no row matches.
-- With zero rows, that org cannot generate an invoice, LR, receipt,
-- quotation, proforma, voucher, payslip, PO, GRN, claim, contract or
-- storage job — every numbered document in the product. Nothing in the
-- Flutter app can create a number_series row either (grepped: every
-- reference in lib/ is a read or an error comment), so the tenant has no
-- self-service way out. They hit a raw Postgres exception.
--
-- Deliberately NOT included, per Arun: per-tenant charge heads
-- (`kDefaultChargeFields` is a Dart const, so a vendor can't add e.g.
-- "Toll & Parking" as a billable line). Agreed to wait.
--
-- Run order: standalone, no dependency on the Item 12C migration.
-- Safe to re-run — every insert is ON CONFLICT DO NOTHING against the
-- existing unique indexes (number_series_uniq / app_settings_uniq), and
-- the function replacements are idempotent by nature.
-- ============================================================

begin;

-- ---- 1. The financial year, computed — never a literal --------------
--
-- The seed MUST derive the FY. Hardcoding '2026-27' would reproduce the
-- exact bug this migration fixes, just delayed: an org created on or
-- after 1 Apr 2027 would get rows tagged to a year `next_doc_number()`
-- never looks up, and would be just as unable to invoice as Ponci is
-- today.
--
-- Format matches OrderDetailPage.currentFy() in Dart exactly
-- ('YYYY-YY', April-March). That agreement is load-bearing — an earlier
-- mismatch ('2627' vs '2026-27') is why APC-1006's invoice went out as
-- a bare '0001' instead of '2026/0001' (see the 12 Aug 2026 numbering
-- audit). Asia/Kolkata rather than UTC so the two agree across the
-- midnight-to-05:30 window on 1 April, when a UTC clock is still in the
-- previous FY but every device in India is not.
create or replace function public.current_fy_ist()
returns text
language sql
stable
as $$
  select case
    when extract(month from (now() at time zone 'Asia/Kolkata')) >= 4
      then to_char((now() at time zone 'Asia/Kolkata'), 'YYYY') || '-' ||
           to_char((now() at time zone 'Asia/Kolkata') + interval '1 year', 'YY')
    else to_char((now() at time zone 'Asia/Kolkata') - interval '1 year', 'YYYY') || '-' ||
         to_char((now() at time zone 'Asia/Kolkata'), 'YY')
  end
$$;

comment on function public.current_fy_ist() is
  'Indian financial year as ''YYYY-YY'' (April-March), IST. Must stay '
  'byte-identical to OrderDetailPage.currentFy() in Dart — number_series '
  'rows are looked up by this exact string.';

-- ---- 2. Number series seed -----------------------------------------
--
-- 14 doc types, matching TEST 1's clean set exactly (APC has the same 14
-- plus 5 legacy inactive branch-scoped rows from before the numbering
-- audit — those are history, not the template).
--
-- Two prefix styles, both taken from what migration 009 actually wrote:
--   - calendar-year '<YYYY>/' for the customer-facing money documents
--     (invoice, proforma, receipt, quotation, voucher, credit/debit note)
--     — matches APC's real '2026/0013' format.
--   - a short static code for internal documents (CLM-, CTR-, GRN-, LR,
--     PS-, PO-, STG-).
--
-- last_number starts at 0 because the stored value is the LAST ISSUED
-- number, not the next one — so the first document issued is 0001. This
-- convention has been mis-set once before (inv_seq_2627 briefly seeded
-- to 1, which would have skipped 001); see CLAUDE.md's settings section.
create or replace function public.seed_org_number_series(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fy text := public.current_fy_ist();
  v_year text := split_part(v_fy, '-', 1);
begin
  insert into public.number_series (org_id, doc_type, branch, fy, prefix, padding, last_number, active)
  select p_org_id, d.doc_type, null, v_fy,
         case when d.calendar_prefix then v_year || '/' else d.prefix end,
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
    ) as d(doc_type, calendar_prefix, prefix)
  on conflict (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''))
  do nothing;
end;
$$;

-- ---- 3. Document boilerplate seed ----------------------------------
--
-- app_settings category 'documents' — the six text blocks and two
-- demurrage numbers that PdfBranding.DocumentBoilerplate reads. Values
-- are copied from what APC and TEST 1 already carry (identical between
-- them). Checked before copying: none of these contain APC's name,
-- address, GSTIN or branding — they're industry boilerplate (goods
-- description, LR notice under the Carriage by Road Act, standard
-- quotation terms), which is why they're safe as a cross-tenant default.
-- Anything genuinely APC-specific lives in `organizations`, not here.
--
-- Without these the documents still generate (PdfBranding falls back),
-- but a quotation goes out with no terms and an LR with no notice text —
-- on the customer-facing artifact.
create or replace function public.seed_org_document_settings(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_settings (org_id, category, key, value)
  values
    (p_org_id, 'documents', 'doc_footer_text',
      to_jsonb('This is a computer-generated document. SAVE PAPER - SAVE TREES | BE DIGITAL - GO GREEN'::text)),
    (p_org_id, 'documents', 'goods_description_default',
      to_jsonb('Old and Used Household Goods For Personal Usage Only, Not For Sale'::text)),
    (p_org_id, 'documents', 'invoice_note',
      to_jsonb('Please keep your Cash/Jewellery and all important documents in your Custody/Lock. Carrying Liquor, Gas Cylinder, Acid of any type of Liquids (like Ghee Tin, Oil etc.) is totally prohibited.'::text)),
    (p_org_id, 'documents', 'lr_notice_text',
      to_jsonb('The consignment by the lorry receipt shall be stored at the destination under the control of the transport operator and shall be delivered to the order of the consignee whose name is mentioned in the lorry receipt. It will under no circumstances be delivered to anyone without written authorization from the consignee on its order.'::text)),
    (p_org_id, 'documents', 'demurrage_text',
      to_jsonb('Demurrage charge after more than {days} day(s) @ Rs.{rate} per day + handling & local transportation charges.'::text)),
    (p_org_id, 'documents', 'demurrage_free_days', to_jsonb(5)),
    (p_org_id, 'documents', 'demurrage_rate_per_day', to_jsonb(500)),
    (p_org_id, 'documents', 'quotation_terms',
      to_jsonb($terms$We do not undertake Electrical, Carpentry & Plumber Job.
Vehicle transportation charges are based on the present prevailing market rate.
We or our agent shall be exempted from any kind of loss or damage due to accident, pilferage, fire, rain, collision or any other road hazard or natural calamity. To avoid loss or damage we advise you to insure your consignment covering all risk.
We request 80% advance on total amount along with your purchase order, balance on completion at loading point. Insurance premium to be paid at loading point before departure.
If required we also provide storage facility at nominal charge.
Kindly give prior intimation of 4-5 days in advance to start packing.
Extra payment will be charged for wooden packing on moving date.
We are not responsible for Gold & Cash. Please keep in your custody lock.
Interest will be charged @24% per annum if payment is not made within 15 days.
Payment to be made in favour of the company by Cash/Cheque.$terms$::text))
  on conflict (org_id, category, key) do nothing;
end;
$$;

-- ---- 4. Wire both into signup --------------------------------------
--
-- Only the tail of create_org_with_owner() changes: two seeding calls
-- added next to the existing pricing_config insert. The return type is
-- unchanged, so CREATE OR REPLACE is enough — no DROP needed (that rule
-- applies to changing a function's return shape; see CLAUDE.md).
--
-- The full body is reproduced verbatim from the live definition
-- (pg_get_functiondef, 18 Aug 2026) with ONLY that addition, so nothing
-- else about signup behaviour moves.
create or replace function public.create_org_with_owner(
  p_user_id uuid,
  p_org_name text,
  p_phone text default null::text,
  p_gstin text default null::text,
  p_owner_name text default null::text)
returns table(is_new boolean, org_id uuid, org_name text, org_slug text,
              plan_id uuid, plan_name text, plan_status text,
              plan_limits jsonb, plan_features jsonb,
              trial_ends_at timestamp with time zone, org_active boolean,
              caller_role text)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_existing record;
  v_base_slug text;
  v_slug text;
  v_org record;
  v_plan record;
  v_attempt int := 0;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required' using errcode = '22004';
  end if;
  if p_org_name is null or length(trim(p_org_name)) = 0 then
    raise exception 'p_org_name is required' using errcode = '22004';
  end if;

  select om.org_id, om.role into v_existing
    from public.org_members om
   where om.user_id = p_user_id
   order by om.created_at asc
   limit 1;

  if found then
    return query
    select false, o.id, o.name, o.slug, o.plan_id, sp.name, o.plan_status,
           coalesce(sp.limits, '{}'::jsonb), coalesce(sp.features, '{}'::jsonb),
           o.trial_ends_at, o.active,
           lower(v_existing.role)
      from public.organizations o
      left join public.subscription_plans sp on sp.id = o.plan_id
     where o.id = v_existing.org_id;
    return;
  end if;

  v_base_slug := trim(both '-' from
                   regexp_replace(lower(p_org_name), '[^a-z0-9]+', '-', 'g'));
  if v_base_slug = '' then
    v_base_slug := 'org';
  end if;
  v_slug := v_base_slug;

  loop
    v_attempt := v_attempt + 1;
    begin
      select sp.id, sp.name, sp.limits, sp.features
        into v_plan
        from public.subscription_plans sp
       where sp.is_default_trial = true
       order by sp.id
       limit 1;
      if not found then
        raise exception 'No default trial plan configured (subscription_plans.is_default_trial)'
          using errcode = 'P0001';
      end if;

      insert into public.organizations
        (name, slug, phone, gstin, signatory_name, plan_id, plan_status, trial_ends_at, active)
      values
        (trim(p_org_name), v_slug,
         nullif(trim(coalesce(p_phone, '')), ''),
         nullif(trim(coalesce(p_gstin, '')), ''),
         nullif(trim(coalesce(p_owner_name, '')), ''),
         v_plan.id, 'trial', now() + interval '7 days', true)
      returning organizations.id, organizations.name, organizations.slug,
                organizations.plan_id, organizations.plan_status,
                organizations.trial_ends_at, organizations.active
        into v_org;

      exit;
    exception
      when unique_violation then
        if v_attempt >= 3 then
          raise exception 'Could not generate a unique slug for "%"', p_org_name
            using errcode = 'P0001';
        end if;
        v_slug := case v_attempt
                    when 1 then v_base_slug || '-' || substr(replace(p_user_id::text, '-', ''), 1, 4)
                    else v_base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4)
                  end;
    end;
  end loop;

  insert into public.org_members (org_id, user_id, role)
  values (v_org.id, p_user_id, 'owner');

  insert into public.pricing_config (org_id, config)
  values (v_org.id, public.default_pricing_config())
  on conflict do nothing;

  -- NEW (18 Aug 2026): without these a brand-new tenant cannot issue a
  -- single numbered document. See this migration's header.
  perform public.seed_org_number_series(v_org.id);
  perform public.seed_org_document_settings(v_org.id);

  return query
  select true, v_org.id, v_org.name, v_org.slug, v_org.plan_id, v_plan.name,
         v_org.plan_status, coalesce(v_plan.limits, '{}'::jsonb),
         coalesce(v_plan.features, '{}'::jsonb), v_org.trial_ends_at,
         v_org.active, 'owner'::text;
end;
$function$;

-- ---- 5. Backfill every existing org --------------------------------
--
-- Ponci Packers And Movers is the one actually broken today, but this
-- runs for all orgs deliberately: the seeding functions are ON CONFLICT
-- DO NOTHING, so APC and TEST 1 keep every row and every counter value
-- they already have — including APC's live receipt counter at 5 — and
-- only genuinely missing rows get created. Targeting Ponci by id would
-- have left the same hole open for any org created between now and
-- whenever this ran.
do $$
declare r record;
begin
  for r in select id, name from public.organizations loop
    perform public.seed_org_number_series(r.id);
    perform public.seed_org_document_settings(r.id);
  end loop;
end $$;

commit;

-- ============================================================
-- VERIFY (read-only — run after, expect every org to have 14+ / 8)
--
--   select o.name,
--     (select count(*) from number_series n
--       where n.org_id = o.id and n.active) as active_series,
--     (select count(*) from app_settings a
--       where a.org_id = o.id and a.category = 'documents') as doc_settings
--   from organizations o order by o.created_at;
--
-- ============================================================
-- SEPARATE, PRE-EXISTING TIME BOMB — NOT FIXED HERE, FLAGGING IT
--
-- number_series rows are FY-scoped, and every org (APC included) has
-- rows for 2026-27 only. next_doc_number() raises when no row matches
-- the requested fy. So on 1 April 2027, currentFy() starts returning
-- '2027-28', no row matches for ANY org, and every numbered document
-- in the product stops working on the same morning.
--
-- This already exists in production today — it is not introduced by
-- this migration, and this migration does not fix it (it seeds the
-- CURRENT FY only). Do NOT fix it by making next_doc_number()
-- auto-insert a missing series: it used to do exactly that, and that
-- silent insert is why APC's real invoices went out as bare '0001'
-- instead of '2026/0001' (12 Aug 2026 numbering audit). The safe fixes
-- are a scheduled job calling seed_org_number_series() for every org at
-- FY rollover, or a "roll over my numbering" action in Settings. Worth
-- deciding before March.
-- ============================================================
