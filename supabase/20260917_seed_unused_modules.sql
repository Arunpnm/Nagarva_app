-- =====================================================================
-- 20260917_seed_unused_modules.sql
--
-- SEED DATA for the seven modules that have never met a row.
-- HANDED OVER UNRUN. Read this header before running it.
--
-- WHY THIS EXISTS
-- ---------------
-- Seven modules are fully built, routed, permission-gated and reachable
-- from the drawer, and carry ZERO rows: Salary & advances, Crew sheet,
-- Trips, Vendors & bills, Contracts, Reviews, Insurance & claims.
-- A screen that has never rendered against data is not "done" — it is
-- unproven. Every real bug found this month was code that had never met
-- data. This file gives each of those screens one row to render.
--
-- It is NOT a test of correctness. It cannot be: it runs as `postgres`
-- in the SQL editor, which BYPASSES RLS, so a write that the app itself
-- would be refused still succeeds here. What it does is put a row on
-- each screen so the screens can be opened on a device and looked at.
--
-- WHAT IT DELIBERATELY DOES NOT DO
-- --------------------------------
-- It does not work around the Trips finding. Section B inserts the trip
-- with EXACTLY the column set `lib/trips_page/trips_page_widget.dart:143`
-- sends — which omits `branch`. That row is therefore created with
-- branch NULL, and Section B's postflight demonstrates the consequence
-- instead of papering over it. See "THE TRIPS FINDING" below.
--
-- MONEY
-- -----
-- Per the standing rule, no figure here is a suggestion of what anything
-- should cost. Every amount is a round arbitrary number chosen only
-- because the row structurally requires one, and each is marked
-- `-- arbitrary` at its site. Where a column can be left at its default
-- without making the screen meaningless (contract_value, trip
-- hire_amount, TDS, A/C), it is left alone rather than invented.
--
-- EVERY ROW IS OBVIOUSLY TEST DATA
-- --------------------------------
-- Every seeded row carries the literal token
--     ZZZ-SEED-20260917
-- in a human-visible text column, and every seeded name begins with
-- "ZZZ SEED". Nothing here can be mistaken on a screen for a real
-- vendor, customer, claim or trip.
--
-- The one exception is `order_staff`, which has NO free-text column at
-- all (id, order_id, staff_id, salary_amount, is_half_day, team_type,
-- org_id, created_at, is_driver, ac_units, ac_rate, ac_amount). So the
-- seed writes that row's (order_id, staff_id) pair into the seeded
-- TRIP's notes as `[crew=<order_id>|<staff_id>]`, and cleanup reads it
-- back from there before deleting anything.
--
-- It deliberately does NOT find that row by `is_driver = true`, even
-- though that is unambiguous today (zero such rows exist). This seed
-- exists so that you will go and USE the Crew Sheet, and the Crew Sheet
-- writes driver-flagged rows — so that check is correct now and
-- guaranteed to become wrong for exactly the reason the file was
-- written, at which point it would delete a real crew row. Stated here
-- because "one predicate deletes everything" is not quite true for that
-- one table, and a cleanup you believe is complete and is not is worse
-- than one you know is partial.
--
-- CLEANUP: the block at the very bottom of this file. One paste, and it
-- asserts its own result — it raises if anything it meant to remove
-- survives, rather than reporting success over a partial delete.
--
-- ONE ADDITION BEYOND THE SEVEN
-- -----------------------------
-- Section C also seeds ONE `claim_items` row. A claim with no items
-- renders an empty list, which proves the list widget was reached and
-- nothing else. Delete the two marked lines if you want it strictly to
-- the list; everything else still works.
--
-- SAFETY
-- ------
-- The whole thing is a single DO block, so it is one statement and one
-- transaction: any raise anywhere rolls back everything and leaves the
-- database exactly as it was. There is no partial-application state.
-- Preflight refuses rather than skips, and refuses rather than
-- double-seeding if the token is already present.
-- =====================================================================

do $$
declare
  k_token      constant text := 'ZZZ-SEED-20260917';
  k_org_slug   constant text := 'arun-packers-and-couriers';

  v_org          uuid;
  v_order_crew   text;   -- an order with no crew yet (driver index safety)
  v_order_claim  text;   -- a delivered/closed order, for policy + claim
  v_order_review text;   -- a closed order with a customer, for the review
  v_staff        uuid;
  v_staff_name   text;
  v_customer     uuid;
  v_order_branch text;

  v_vendor_id  uuid;
  v_bill_id    uuid;
  v_policy_id  uuid;
  v_claim_id   uuid;
  v_trip_id    uuid;

  v_bill_total   numeric;
  v_pay_amount   numeric;
  v_trip_branch  text;
  v_branch_default text;
  v_n            bigint;
  v_line         text;
begin
  -- ===================================================================
  -- PREFLIGHT. Every check RAISES; none of them skips.
  -- ===================================================================

  -- (1) The org. Named explicitly rather than "the first org", because
  --     seeding test data into the wrong tenant is not recoverable by
  --     the cleanup block alone once someone has looked at it.
  select id into v_org from public.organizations where slug = k_org_slug;
  if v_org is null then
    raise exception
      'PREFLIGHT: no organization with slug %. Change k_org_slug at the top of this file to the org you want seeded.',
      k_org_slug;
  end if;

  -- (2) The org must be writable. `vendors`, `vendor_bills` and `trips`
  --     carry a BEFORE INSERT `enforce_org_writable` trigger (Item 32b),
  --     so a lapsed trial fails this script halfway through with a
  --     billing message about a table nobody was thinking about. Fail
  --     up front with the real reason instead.
  perform public.assert_org_writable(v_org);

  -- (3) Refuse to double-seed. Running this twice would leave two of
  --     everything and make the cleanup block's own count assertions
  --     read as failures. This returns a DIFFERENT result before and
  --     after a seed, which is the whole point of it.
  select count(*) into v_n from public.vendors
   where org_id = v_org and name like '%' || k_token || '%';
  if v_n > 0 then
    raise exception
      'PREFLIGHT: % already seeded (% vendor row(s) carry the token). Run the CLEANUP block at the bottom of this file first.',
      k_token, v_n;
  end if;

  -- (4) THE TRIPS FINDING'S OWN PRECONDITION, re-proven at run time.
  --     The finding is that nothing fills `trips.branch`. That was true
  --     on 17 Sept 2026 (no column default, not generated, no rules,
  --     two triggers neither of which names `branch`). If a default has
  --     appeared since, the finding is STALE and Section B's
  --     demonstration would be a lie — so refuse loudly rather than
  --     demonstrate something that is no longer true.
  select column_default into v_branch_default
    from information_schema.columns
   where table_schema = 'public' and table_name = 'trips' and column_name = 'branch';
  if v_branch_default is not null then
    raise exception
      'PREFLIGHT: trips.branch now has a DEFAULT (%). The Trips finding this file demonstrates is stale — re-audit before seeding.',
      v_branch_default;
  end if;

  -- (5) Anchors. Each one names what is missing rather than failing
  --     later on a null.
  select o.id into v_order_crew
    from public.orders o
   where o.org_id = v_org
     and not exists (select 1 from public.order_staff os where os.order_id = o.id)
   order by o.id
   limit 1;
  if v_order_crew is null then
    raise exception 'PREFLIGHT: no order in % without existing crew — needed so the one-driver-per-order unique index is not pre-occupied.', k_org_slug;
  end if;

  select o.id into v_order_claim
    from public.orders o
   where o.org_id = v_org and o.status in ('delivered', 'closed')
   order by o.id desc
   limit 1;
  if v_order_claim is null then
    raise exception 'PREFLIGHT: no delivered/closed order in % to hang an insurance policy and claim on.', k_org_slug;
  end if;

  select o.id, o.customer_id, o.branch
    into v_order_review, v_customer, v_order_branch
    from public.orders o
   where o.org_id = v_org and o.status = 'closed' and o.customer_id is not null
   order by o.id
   limit 1;
  if v_order_review is null then
    raise exception 'PREFLIGHT: no closed order with a customer_id in % to attach a review to.', k_org_slug;
  end if;

  -- The review's branch comes from its order, exactly as
  -- `reviews_page_widget.dart:131` does. `reviews` carries the same
  -- RESTRICTIVE branch_isolation policy as `trips`; the difference is
  -- that the Reviews page actually passes a branch and the Trips page
  -- does not. If this order has none, say so rather than seeding a row
  -- that only the owner can ever see.
  if v_order_branch is null then
    raise exception 'PREFLIGHT: order % has a NULL branch, so the seeded review would be owner-only under reviews.branch_isolation. Pick another order.', v_order_review;
  end if;

  select s.id, s.name into v_staff, v_staff_name
    from public.staff s
   where s.org_id = v_org and coalesce(s.active, true)
   order by s.name
   limit 1;
  if v_staff is null then
    raise exception 'PREFLIGHT: no active staff row in % — needed for the advance and the crew row.', k_org_slug;
  end if;

  if v_customer is null then
    raise exception 'PREFLIGHT: could not resolve a customer for the contract.';
  end if;

  raise notice '--- PREFLIGHT OK. org=% order_crew=% order_claim=% order_review=% staff=% (%)',
    k_org_slug, v_order_crew, v_order_claim, v_order_review, v_staff_name, v_staff;

  -- ===================================================================
  -- SECTION A — Vendors & bills:  one vendor + one bill + one payment
  -- ===================================================================
  insert into public.vendors (org_id, name, vendor_type, phone, contact_person, notes)
  values (v_org,
          'ZZZ SEED Transporter — ' || k_token,
          'transporter',
          '9000000001',
          'ZZZ SEED contact',
          k_token || ' — delete me')
  returning id into v_vendor_id;

  -- Bill arithmetic mirrors vendor_detail_page_widget.dart:319-322 exactly:
  --   gst_amount = taxable * gst_pct / 100
  --   total      = taxable + gst_amount          (TDS is NOT deducted here)
  -- 10000 / 18% are arbitrary round numbers, chosen only because a bill
  -- needs an amount. TDS is left at 0 rather than invented — a TDS rate
  -- is a vendor's tax position, not something a seed should assert.
  v_bill_total := 10000 + (10000 * 18 / 100);   -- = 11800, arbitrary

  insert into public.vendor_bills (
    org_id, vendor_id, bill_no, bill_date,
    taxable_amount, gst_mode, gst_pct, gst_amount, tds_amount,
    total_amount, paid_amount, status, notes)
  values (v_org, v_vendor_id,
          'ZZZ-BILL-' || k_token,
          current_date,
          10000,          -- arbitrary
          'cgst_sgst',
          18,             -- arbitrary
          1800,           -- arbitrary, = 10000 * 18%
          0,              -- TDS deliberately not invented
          v_bill_total,
          0,
          'unpaid',
          k_token || ' — delete me')
  returning id into v_bill_id;

  -- A PART payment, so the bill lands on 'partial' rather than 'paid'.
  -- The partial branch is the one worth having on screen: a fully-paid
  -- bill and an unpaid one both render trivially.
  v_pay_amount := 5000;   -- arbitrary

  insert into public.vendor_payments (
    org_id, vendor_id, bill_id, amount, mode, reference, paid_at, note)
  values (v_org, v_vendor_id, v_bill_id,
          v_pay_amount,
          'upi',
          'ZZZ-REF-' || k_token,
          now(),
          k_token || ' — delete me');

  -- THE BILL'S PAID STATE IS MAINTAINED BY DART, NOT BY THE DATABASE.
  -- Verified 17 Sept 2026: `vendor_payments` has NO triggers at all
  -- (pg_trigger, non-internal, count = 0), unlike `payment_entries`,
  -- which has `sync_order_paid_total`. So inserting a payment does not
  -- move the bill — the app does that itself at
  -- vendor_detail_page_widget.dart:592-602, and this mirrors it byte
  -- for byte so the seeded state is a state the app could have produced.
  -- (That asymmetry is itself worth knowing: any vendor payment written
  -- outside the app leaves `vendor_bills.paid_amount` stale, with no
  -- backstop. Two sources for one value.)
  update public.vendor_bills
     set paid_amount = v_pay_amount,
         status = case
                    when (v_bill_total - 0 - v_pay_amount) <= 0.01 then 'paid'
                    when v_pay_amount > 0 then 'partial'
                    else 'unpaid'
                  end,
         updated_at = now()
   where id = v_bill_id;

  -- ===================================================================
  -- SECTION B — Trips:  ONE trip, created the way the APP creates it
  -- ===================================================================
  --
  -- THE TRIPS FINDING.
  --
  -- `trips` carries a RESTRICTIVE policy `branch_isolation`, whose qual
  -- AND with_check are both:
  --
  --     current_staff_branch_or_owner(org_id, branch)
  --
  -- and that function is:
  --
  --     is_org_owner(p_org_id)
  --     or exists (select 1 from staff
  --                 where auth_user_id = auth.uid()
  --                   and org_id = p_org_id
  --                   and branch  = p_branch)
  --
  -- `branch = p_branch` with a NULL on either side is NULL, never true.
  -- So a trip whose branch is NULL is admitted to NOBODY except the
  -- owner — for SELECT and, because with_check carries the same
  -- expression, for INSERT.
  --
  -- The column list below is exactly what trips_page_widget.dart:143-156
  -- sends. `branch` is absent there, and this file does not add it.
  -- The row therefore lands with branch NULL, which is the finding.
  --
  -- This INSERT succeeds here only because the SQL editor runs as
  -- `postgres` and bypasses RLS. Through the app:
  --   * a manager or supervisor gets
  --     "new row violates row-level security policy" on Save, every time;
  --   * the owner saves fine and then the trip is invisible to every
  --     staff session, permanently.
  --
  -- trip_type 'outstation' rather than 'hired', so is_hired is false and
  -- hire_amount stays at its default 0 — no money is invented here at all.
  insert into public.trips (
    org_id, trip_no, trip_type, is_hired,
    vehicle_no, driver_name, driver_phone,
    from_loc, to_loc, start_date, status, notes)
  values (v_org,
          'ZZZ-TRIP-' || k_token,
          'outstation',
          false,
          'ZZZ-SEED-0001',
          'ZZZ SEED driver',
          '9000000002',
          'ZZZ SEED origin',
          'ZZZ SEED destination',
          current_date,
          'planned',
          k_token || ' — delete me. Created with branch NULL, exactly as the app does.'
            -- Machine-readable pointer to the crew row, which has no text
            -- column of its own. Cleanup reads it back from here. See the
            -- header's note on order_staff.
            || ' [crew=' || v_order_crew || '|' || v_staff::text || ']')
  returning id, branch into v_trip_id, v_trip_branch;

  -- Discriminating assertion: this is TRUE in the broken state and
  -- FALSE once the app (or a default, or a trigger) starts supplying a
  -- branch. It is not a formality — if the finding is ever fixed and
  -- this file is re-run, it should stop claiming a bug that is gone.
  if v_trip_branch is not null then
    raise exception
      'POSTFLIGHT B: the seeded trip came back with branch = %. Something now supplies it — the Trips finding is fixed or stale, and this section no longer demonstrates anything.',
      v_trip_branch;
  end if;

  raise notice '--- TRIPS FINDING, demonstrated on the seeded row -------------';
  raise notice '    trip % has branch = NULL (as the app creates it)', v_trip_id;
  for v_line in
    select format(
             '    staff %-18s branch=%-14s ->  (trip.branch = staff.branch) is %s',
             s.name,
             coalesce(s.branch, '<null>'),
             coalesce((v_trip_branch = s.branch)::text, 'NULL  <-- not true, so denied')
           )
      from public.staff s
     where s.org_id = v_org and coalesce(s.active, true)
     order by s.name
  loop
    raise notice '%', v_line;
  end loop;
  raise notice '    For comparison, had the app sent a branch:';
  for v_line in
    select format(
             '    staff %-18s branch=%-14s ->  (''%s'' = staff.branch) is %s',
             s.name, coalesce(s.branch, '<null>'), v_order_branch,
             coalesce((v_order_branch = s.branch)::text, 'NULL')
           )
      from public.staff s
     where s.org_id = v_org and coalesce(s.active, true)
     order by s.name
  loop
    raise notice '%', v_line;
  end loop;
  raise notice '    NOTE: staff.auth_user_id is NULL until a person completes';
  raise notice '    their first PIN login, and the exists() above needs it. So';
  raise notice '    today every staff session is denied for that reason FIRST,';
  raise notice '    and the branch reason takes over once it is populated.';
  raise notice '    Fixing one does not reveal the other as fixed.';
  raise notice '---------------------------------------------------------------';

  -- ===================================================================
  -- SECTION C — Insurance & claims:  one policy + one claim (+1 item)
  -- ===================================================================
  -- Figures mirror insurance_claims_page_widget.dart:169-190's own
  -- arithmetic (premium = declared * pct/100; gst = premium * 18%).
  -- 100000 declared and 1% premium are arbitrary round numbers.
  insert into public.insurance_policies (
    org_id, order_id, customer_id, policy_type, insurer_name, policy_no,
    declared_value, premium_pct, premium_amount, gst_on_premium, total_premium,
    coverage_start, coverage_end, excess_amount, status, notes)
  values (v_org, v_order_claim,
          (select customer_id from public.orders where id = v_order_claim),
          'declared_value',
          'ZZZ SEED Insurer',
          'ZZZ-POL-' || k_token,
          100000,   -- arbitrary
          1,        -- arbitrary
          1000,     -- arbitrary, = 100000 * 1%
          180,      -- arbitrary, = 1000 * 18%
          1180,
          current_date,
          current_date + 30,
          0,        -- excess deliberately not invented
          'active',
          k_token || ' — delete me')
  returning id into v_policy_id;

  insert into public.claims (
    org_id, claim_no, order_id, policy_id, customer_id,
    claim_type, intimated_at, incident_date, description,
    claimed_amount, status, notes)
  values (v_org,
          'ZZZ-CLM-' || k_token,
          v_order_claim,
          v_policy_id,
          (select customer_id from public.orders where id = v_order_claim),
          'damage',
          now(),
          current_date,
          'ZZZ SEED — test claim, not a real incident.',
          5000,     -- arbitrary
          'intimated',
          k_token || ' — delete me')
  returning id into v_claim_id;

  -- vvv THE ONE ADDITION BEYOND THE SEVEN — delete these lines to skip.
  insert into public.claim_items (
    org_id, claim_id, item_name, description, quantity,
    declared_value, claimed_amount, damage_type)
  values (v_org, v_claim_id,
          'ZZZ SEED item — ' || k_token,
          k_token || ' — delete me',
          1,
          5000,     -- arbitrary
          5000,     -- arbitrary
          'damaged');
  -- ^^^ end of the addition.

  -- ===================================================================
  -- SECTION D — Salary & advances:  one PENDING advance
  -- ===================================================================
  -- Pending, not settled, so the ledger sheet's "ADVANCE BALANCE" chip
  -- renders non-zero and the Settle button is enabled.
  --
  -- Note `staff_advances.staff_id` is TEXT while `staff.id` is UUID, and
  -- the table has ZERO foreign keys — so this cast is the only thing
  -- linking the two, and nothing in the database enforces it.
  insert into public.staff_advances (
    org_id, staff_id, amount, advance_date, status, note)
  values (v_org,
          v_staff::text,
          5000,     -- arbitrary
          current_date,
          'pending',
          k_token || ' — delete me');
  -- `balance`, `recovery_per_month`, `recovered_amount` and `closed_at`
  -- are left at their defaults ON PURPOSE: no Dart code reads or writes
  -- any of the four, so seeding them would put figures on screen that
  -- no screen can show and no code can change.

  -- ===================================================================
  -- SECTION E — Contracts:  one contract
  -- ===================================================================
  -- There is no Contracts page, no route and no generated Dart class.
  -- This row exists so the table is not empty when that module is
  -- built, and so `contracts_no_uniq` gets exercised at least once.
  -- `contract_value` is left at its default 0 rather than invented.
  insert into public.contracts (
    org_id, contract_no, customer_id, title, contract_type,
    start_date, end_date, status, notes)
  values (v_org,
          'ZZZ-CTR-' || k_token,
          v_customer,
          'ZZZ SEED contract — ' || k_token,
          'annual',
          current_date,
          current_date + 365,
          'draft',
          k_token || ' — delete me');

  -- ===================================================================
  -- SECTION F — Reviews:  one COLLECTED review
  -- ===================================================================
  -- `branch` is taken from the order, which is what
  -- reviews_page_widget.dart:131 does. Preflight already refused a
  -- NULL-branch order, so this row is visible to that branch's staff
  -- rather than owner-only.
  --
  -- Rated rather than merely requested: a requested-but-unrated row
  -- renders as a pending chip, a rated one renders the actual card.
  insert into public.reviews (
    org_id, order_id, customer_id, rating, comment, channel,
    requested_at, responded_at, branch)
  values (v_org, v_order_review,
          (select customer_id from public.orders where id = v_order_review),
          5,
          'ZZZ SEED review — ' || k_token || ' — delete me',
          'whatsapp',
          now() - interval '1 day',
          now(),
          v_order_branch);

  -- ===================================================================
  -- SECTION G — Crew sheet:  one crew row, WITH a driver
  -- ===================================================================
  -- The crew sheet refuses to save without a driver, and
  -- `order_staff_one_driver_per_order` (partial unique on order_id
  -- where is_driver) enforces at most one. Preflight picked an order
  -- with no existing crew, so this cannot collide.
  --
  -- The 8 order_staff rows that exist today have is_driver = false on
  -- all 8, which is how we know none of them came from the crew sheet.
  -- This is the first driver-flagged row in the database.
  --
  -- team_type 'labour' is what the crew sheet itself writes.
  --
  -- **`ac_amount` IS NOT WRITABLE AND MUST NOT APPEAR HERE.** It is
  -- `GENERATED ALWAYS AS ((ac_units)::numeric * ac_rate) STORED`, so any
  -- INSERT naming it raises 428C9 *cannot insert a non-DEFAULT value into
  -- column "ac_amount"* — which is exactly how the first run of this file
  -- failed, and exactly why the CREW SHEET HAS NEVER SAVED:
  -- `crew_sheet_page_widget.dart:507` puts `'ac_amount'` in its upsert
  -- payload, so every save it has ever attempted raised 428C9.
  --
  -- `ac_units` and `ac_rate` are the real inputs, NOT NULL DEFAULT 0, and
  -- are LEFT AT THEIR DEFAULTS here rather than seeded: A/C is a real
  -- charge the vendor enters, so inventing units and a rate would be the
  -- suggested-money failure in a new place. The generated `ac_amount`
  -- therefore computes 0, which is the truth — no A/C on this job.
  --
  -- The audit that preceded this file had it BACKWARDS, and the reason is
  -- worth keeping: an `information_schema.columns` read of
  -- `data_type, is_nullable, column_default` shows `ac_amount` as
  -- nullable with no default, which is indistinguishable from an ordinary
  -- optional column. `is_generated` is the discriminating field.
  insert into public.order_staff (
    org_id, order_id, staff_id, salary_amount, is_driver, team_type)
  values (v_org, v_order_crew, v_staff,
          600,      -- arbitrary. NB: the app itself opens this at 0 by
                    -- design ("No suggested money") — 600 here is the
                    -- operator supplying data, not the app suggesting it.
          true,
          'labour');

  -- ===================================================================
  -- POSTFLIGHT. Asserts the CONSTRUCT, not a printed row. Token-scoped
  -- counts only — no dated global literals that go stale.
  -- ===================================================================
  select count(*) into v_n from public.vendors where org_id=v_org and name like '%'||k_token||'%';
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected 1 seeded vendor, got %', v_n; end if;

  select count(*) into v_n from public.vendor_bills where org_id=v_org and notes like '%'||k_token||'%';
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected 1 seeded vendor bill, got %', v_n; end if;

  select count(*) into v_n from public.vendor_payments where org_id=v_org and note like '%'||k_token||'%';
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected 1 seeded vendor payment, got %', v_n; end if;

  -- The bill must actually read 'partial'. If this ever comes back
  -- 'paid' or 'unpaid', the mirrored recompute has drifted from the
  -- Dart it is copying, which is the thing worth catching.
  select count(*) into v_n from public.vendor_bills
   where id = v_bill_id and status = 'partial' and paid_amount = v_pay_amount;
  if v_n <> 1 then
    raise exception 'POSTFLIGHT: seeded bill did not land on partial/% — check vendor_detail_page_widget.dart:592-602 against this file.', v_pay_amount;
  end if;

  select count(*) into v_n from public.trips where org_id=v_org and notes like '%'||k_token||'%';
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected 1 seeded trip, got %', v_n; end if;

  select count(*) into v_n from public.insurance_policies where org_id=v_org and notes like '%'||k_token||'%';
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected 1 seeded policy, got %', v_n; end if;

  select count(*) into v_n from public.claims where org_id=v_org and notes like '%'||k_token||'%';
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected 1 seeded claim, got %', v_n; end if;

  select count(*) into v_n from public.staff_advances
   where org_id=v_org and note like '%'||k_token||'%' and status='pending';
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected 1 seeded PENDING advance, got %', v_n; end if;

  select count(*) into v_n from public.contracts where org_id=v_org and notes like '%'||k_token||'%';
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected 1 seeded contract, got %', v_n; end if;

  select count(*) into v_n from public.reviews where org_id=v_org and comment like '%'||k_token||'%';
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected 1 seeded review, got %', v_n; end if;

  -- The crew row has no token column, so it is asserted by its key and
  -- by the property that matters: exactly one driver on that order.
  select count(*) into v_n from public.order_staff
   where order_id = v_order_crew and staff_id = v_staff and is_driver;
  if v_n <> 1 then raise exception 'POSTFLIGHT: expected exactly 1 driver-flagged crew row on %, got %', v_order_crew, v_n; end if;

  raise notice '=== SEED COMPLETE. 11 rows + 1 bill update, all carrying % ===', k_token;
  raise notice '    Crew row is on order % for staff % — it has no text', v_order_crew, v_staff_name;
  raise notice '    column, so cleanup finds it by that key pair.';
  raise notice '    Now open, on a device: Trips, Vendors, Insurance & Claims,';
  raise notice '    Salary (tap the staff card), Reviews, and the Crew Sheet';
  raise notice '    from order %.', v_order_crew;
end $$;


-- =====================================================================
-- CLEANUP — run this to remove everything the seed created.
--
-- One paste. It asserts its own result: if anything it meant to remove
-- survives, it RAISES and rolls back rather than reporting success over
-- a partial delete. Uncomment to use.
--
-- Order matters: claim_items before claims (FK), vendor_payments before
-- vendor_bills before vendors.
-- =====================================================================
/*
do $$
declare
  k_token    constant text := 'ZZZ-SEED-20260917';
  k_org_slug constant text := 'arun-packers-and-couriers';
  v_org uuid;
  v_order_crew text;
  v_staff uuid;
  v_n bigint;
begin
  select id into v_org from public.organizations where slug = k_org_slug;
  if v_org is null then
    raise exception 'CLEANUP: no organization with slug %.', k_org_slug;
  end if;

  -- FIRST, before anything is deleted: recover the crew row's key pair
  -- from the seeded trip's notes, where the seed wrote it.
  --
  -- WHY NOT "the row with is_driver = true": because the seed exists so
  -- that you will go and USE the Crew Sheet, and the Crew Sheet writes
  -- driver-flagged rows. Resolving by is_driver is correct today (there
  -- are zero such rows) and is guaranteed to become wrong precisely
  -- because of what this seed is for — at which point cleanup would
  -- delete a real crew row you had just entered. It fails safe instead:
  -- no trip row, no crew delete.
  select substring(t.notes from '\[crew=([^|]+)\|'),
         substring(t.notes from '\[crew=[^|]+\|([^\]]+)\]')::uuid
    into v_order_crew, v_staff
    from public.trips t
   where t.org_id = v_org and t.notes like '%'||k_token||'%'
   limit 1;

  delete from public.claim_items
   where org_id = v_org
     and claim_id in (select id from public.claims where org_id = v_org and notes like '%'||k_token||'%');
  delete from public.claims             where org_id = v_org and notes   like '%'||k_token||'%';
  delete from public.insurance_policies where org_id = v_org and notes   like '%'||k_token||'%';
  delete from public.reviews            where org_id = v_org and comment like '%'||k_token||'%';
  delete from public.contracts          where org_id = v_org and notes   like '%'||k_token||'%';
  delete from public.staff_advances     where org_id = v_org and note    like '%'||k_token||'%';
  delete from public.trips              where org_id = v_org and notes   like '%'||k_token||'%';
  delete from public.vendor_payments
   where org_id = v_org
     and (note like '%'||k_token||'%'
          or bill_id in (select id from public.vendor_bills where org_id = v_org and notes like '%'||k_token||'%'));
  delete from public.vendor_bills       where org_id = v_org and notes   like '%'||k_token||'%';
  delete from public.vendors            where org_id = v_org and name    like '%'||k_token||'%';

  -- Now delete exactly the crew row the seed created, by the key pair
  -- recovered above. Never a broader predicate.
  if v_order_crew is not null and v_staff is not null then
    delete from public.order_staff
     where org_id = v_org and order_id = v_order_crew and staff_id = v_staff;
    raise notice 'CLEANUP: removed the seeded crew row on % (staff %).', v_order_crew, v_staff;
  else
    raise notice 'CLEANUP: no seeded trip row carrying a [crew=...] pointer — the crew row was NOT touched.';
    raise notice '         If the seed ran and the trip was deleted separately, remove the crew row by hand.';
  end if;

  -- Assert the removal actually happened, per table.
  select (select count(*) from public.vendors            where org_id=v_org and name    like '%'||k_token||'%')
       + (select count(*) from public.vendor_bills       where org_id=v_org and notes   like '%'||k_token||'%')
       + (select count(*) from public.vendor_payments    where org_id=v_org and note    like '%'||k_token||'%')
       + (select count(*) from public.trips              where org_id=v_org and notes   like '%'||k_token||'%')
       + (select count(*) from public.insurance_policies where org_id=v_org and notes   like '%'||k_token||'%')
       + (select count(*) from public.claims             where org_id=v_org and notes   like '%'||k_token||'%')
       + (select count(*) from public.contracts          where org_id=v_org and notes   like '%'||k_token||'%')
       + (select count(*) from public.staff_advances     where org_id=v_org and note    like '%'||k_token||'%')
       + (select count(*) from public.reviews            where org_id=v_org and comment like '%'||k_token||'%')
    into v_n;
  if v_n <> 0 then
    raise exception 'CLEANUP: % seeded row(s) survived. Nothing was deleted (this block rolled back).', v_n;
  end if;

  raise notice '=== CLEANUP COMPLETE. No rows carrying % remain. ===', k_token;
end $$;
*/

-- =====================================================================
-- "DID IT LAND?" — a read-only check you can run any time, before or
-- after. Returns one row per module with its seeded count.
-- =====================================================================
/*
with org as (select id from public.organizations where slug = 'arun-packers-and-couriers')
select 'vendors'            m, count(*) n from public.vendors,            org where vendors.org_id=org.id            and name    like '%ZZZ-SEED-20260917%'
union all select 'vendor_bills',       count(*) from public.vendor_bills,       org where vendor_bills.org_id=org.id       and notes   like '%ZZZ-SEED-20260917%'
union all select 'vendor_payments',    count(*) from public.vendor_payments,    org where vendor_payments.org_id=org.id    and note    like '%ZZZ-SEED-20260917%'
union all select 'trips',              count(*) from public.trips,              org where trips.org_id=org.id              and notes   like '%ZZZ-SEED-20260917%'
union all select 'insurance_policies', count(*) from public.insurance_policies, org where insurance_policies.org_id=org.id and notes   like '%ZZZ-SEED-20260917%'
union all select 'claims',             count(*) from public.claims,             org where claims.org_id=org.id             and notes   like '%ZZZ-SEED-20260917%'
union all select 'claim_items',        count(*) from public.claim_items,        org where claim_items.org_id=org.id        and description like '%ZZZ-SEED-20260917%'
union all select 'contracts',          count(*) from public.contracts,          org where contracts.org_id=org.id          and notes   like '%ZZZ-SEED-20260917%'
union all select 'staff_advances',     count(*) from public.staff_advances,     org where staff_advances.org_id=org.id     and note    like '%ZZZ-SEED-20260917%'
union all select 'reviews',            count(*) from public.reviews,            org where reviews.org_id=org.id            and comment like '%ZZZ-SEED-20260917%'
-- order_staff has no token column; it is counted via the pointer the seed
-- wrote into the trip's notes, so a crew row YOU create on the device is
-- never mistaken for the seeded one.
union all select 'order_staff(seeded)', (
  select count(*) from public.order_staff os
   where os.org_id = (select id from org)
     and (os.order_id, os.staff_id) in (
       select substring(t.notes from '\[crew=([^|]+)\|'),
              substring(t.notes from '\[crew=[^|]+\|([^\]]+)\]')::uuid
         from public.trips t
        where t.org_id = (select id from org) and t.notes like '%ZZZ-SEED-20260917%'))
order by 1;
*/
