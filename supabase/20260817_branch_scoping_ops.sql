-- ============================================================
-- supabase/20260817_branch_scoping_ops.sql
--
-- Item 30, first real migration — branch-scoped RLS for the 7 "ops"
-- tables, using the shared claim mechanism ("Option B": two lookup
-- functions reading `staff` live via auth.uid(), no JWT claims, no new
-- infrastructure — settled in this session's Item 30 options analysis).
-- staff-login/pin-login were already deployed separately (17 Aug 2026,
-- earlier in this session) with staff_role moved to app_metadata; that
-- deploy is what makes a staff PIN session's auth.uid() usable here at
-- all — this migration adds nothing to the login path itself.
--
-- SCOPE — IN (7 tables, this migration):
--   orders, leads, customers, tasks, trips, attendance, reviews
--
-- SCOPE — DELIBERATELY EXCLUDED, so nobody adds these later assuming
-- an oversight:
--   - rate_cards, materials, stock_movements — checked live 17 Aug 2026.
--     rate_cards: both live rows are org-wide defaults (is_default=true,
--     branch=null) — the schema supports a branch-specific override but
--     zero such rows exist; fail-closed branch-scoping would hide the
--     only two rate cards from every branch manager. materials/
--     stock_movements: `branch` is a free-text UI field that nothing in
--     the app reads back — no page filters or groups by it, so the code
--     doesn't express a per-branch inventory model today (5 rows across
--     3 branches on materials, confirmed not real usage). Scoping any of
--     the three now would enforce a distinction the business isn't
--     making. Real per-branch rate cards or inventory later is its own
--     data-model decision, not an accidental side effect of an RLS pass.
--   - journal_entries, journal_lines, bank_accounts, grn,
--     marketing_spend, payroll_runs, purchase_orders — "books" tables,
--     agreed to get their own migration later, not bundled with ops.
--   - number_series, lr_series — never (sequence/counter tables, branch
--     column there is metadata for the numbering scheme, not a
--     visibility boundary).
--   - warehouses — skipped (no page in `lib/` queries it yet).
--   - lr_register — has a live `branch` column but was NEVER assigned a
--     category (ops/books/never/skip) in this session's scoping pass.
--     Not included here. Flagging rather than guessing — an LR is a
--     legal document (see CLAUDE.md's soft-delete section on why it's
--     permanently non-deletable), so its branch-visibility rules may
--     want the same care, not a default copy-paste of the ops shape.
--   - staff itself — a branch manager's own visibility into OTHER
--     branches' staff records is a related but distinct question from
--     these 7 tables and was not addressed this pass.
--
-- DESIGN DECISIONS (all confirmed explicitly before writing this):
--   - Fail-closed on NULL branch. A row with branch IS NULL is visible
--     to the owner only, invisible to every staff session — this falls
--     out naturally from `=` returning NULL (not true) when either side
--     is null, so no special-casing was needed in the helper.
--     NULL-branch counts were checked live before this file was
--     written: orders 0/25, leads 0/15, customers 1/30 (backfilled
--     below), attendance 13/13 (backfilled below, 100% coverage via
--     staff_id), tasks/trips/reviews currently 0 rows each. No hidden
--     backfill debt on the 7 in-scope tables.
--   - Owner bypass, no manager bypass. `current_staff_branch_or_owner`
--     ORs in `is_org_owner()` only — a manager role gets no special
--     branch-crossing privilege from this function. If a manager needs
--     cross-branch visibility later, that's a deliberate widening of
--     this function (or a new one), not assumed here.
--   - `staff.auth_user_id` already has a unique partial index
--     (`staff_auth_user_id_key`, WHERE auth_user_id IS NOT NULL) —
--     confirmed live before writing this, no new index needed.
--   - Added as a RESTRICTIVE policy alongside each table's existing
--     PERMISSIVE `org_isolation` policy (from 20260715_rls_v1.sql),
--     not a replacement. Postgres ANDs restrictive policies against the
--     permissive set, so this can only narrow what org_isolation
--     already allows — org isolation itself is untouched, lowering the
--     risk of this migration relative to rewriting org_isolation in
--     place.
--
-- Run order: this file is self-contained and can run standalone. Run
-- alongside the security_invoker ALTER handed over in the same session
-- (branch_kpis_view / gstr1_b2b_view / low_stock_view) — unrelated bug,
-- bundled by the owner's own choice, not a dependency between them.
--
-- ACCEPANCE TEST (do not start until Arun has created the Chennai
-- manager row himself with real data): create a Branch Manager staff
-- row, branch = 'Chennai', log in via pin-login, confirm the session
-- sees Chennai orders/leads/customers/tasks/trips/attendance/reviews
-- only — not Bengaluru's or Coimbatore's — via both the app UI and a
-- direct PostgREST call with that session's access token. Then confirm
-- an owner session still sees all three branches unchanged.
-- ============================================================

-- ---- 1. Data fixes (run before the policies go live, so nothing that
-- should be visible today briefly isn't) -----------------------------

-- attendance: 100% coverage confirmed live — all 13 rows join cleanly
-- to a staff row with a populated branch (Chennai x8, Bengaluru x4,
-- Coimbatore x1). staff_id is stored as text on attendance, uuid on
-- staff, hence the cast.
update attendance a
set branch = s.branch
from staff s
where s.id::text = a.staff_id
  and a.branch is null
  and s.branch is not null;

-- customers: the one stray NULL-branch row (Ponmani, 9597056506,
-- created 2026-08-04) — set to Bengaluru per Arun.
update customers
set branch = 'Bengaluru'
where id = '6debf526-39e2-4faf-9225-36c305dfc6b7'
  and branch is null;

-- ---- 2. Shared claim helper -----------------------------------------

create or replace function current_staff_branch_or_owner(p_org_id uuid, p_branch text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    is_org_owner(p_org_id)
    or exists (
      select 1 from staff
      where auth_user_id = auth.uid()
        and org_id = p_org_id
        and branch = p_branch
    )
$$;

comment on function current_staff_branch_or_owner(uuid, text) is
  'Item 30 branch-scoping check: true for the org owner (any branch), '
  'or a staff session whose own staff.branch matches p_branch. NULL '
  'p_branch fails closed (owner-only) via plain = semantics — no '
  'special-casing needed. No manager bypass by design.';

-- ---- 3. Restrictive policies, one per in-scope table -----------------
-- Each is additive alongside the existing PERMISSIVE org_isolation
-- policy — restrictive policies AND against the permissive set, so
-- org_isolation's own behavior is unchanged; this can only narrow it
-- further by branch.

create policy branch_isolation on orders
  as restrictive
  for all
  using (current_staff_branch_or_owner(org_id, branch))
  with check (current_staff_branch_or_owner(org_id, branch));

create policy branch_isolation on leads
  as restrictive
  for all
  using (current_staff_branch_or_owner(org_id, branch))
  with check (current_staff_branch_or_owner(org_id, branch));

create policy branch_isolation on customers
  as restrictive
  for all
  using (current_staff_branch_or_owner(org_id, branch))
  with check (current_staff_branch_or_owner(org_id, branch));

create policy branch_isolation on tasks
  as restrictive
  for all
  using (current_staff_branch_or_owner(org_id, branch))
  with check (current_staff_branch_or_owner(org_id, branch));

create policy branch_isolation on trips
  as restrictive
  for all
  using (current_staff_branch_or_owner(org_id, branch))
  with check (current_staff_branch_or_owner(org_id, branch));

create policy branch_isolation on attendance
  as restrictive
  for all
  using (current_staff_branch_or_owner(org_id, branch))
  with check (current_staff_branch_or_owner(org_id, branch));

create policy branch_isolation on reviews
  as restrictive
  for all
  using (current_staff_branch_or_owner(org_id, branch))
  with check (current_staff_branch_or_owner(org_id, branch));

-- ---- Verify (read-only, safe to run after the above) -----------------
-- select tablename, policyname, permissive, cmd from pg_policies
-- where schemaname = 'public' and policyname = 'branch_isolation'
-- order by tablename;
