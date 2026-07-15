# ADDENDUM — Vendor Registration & Plan Flow (append to CLAUDE.md)

## Requirement (from owner, 12 Jul 2026)
The Flutter app must implement the SAME vendor flow as the Nagarva web app.
Nothing may be missed: registration, login, plan tiers, org creation, onboarding.

## The canonical flow
1. **Vendor signup** — Supabase Auth (email/phone + password), NOT the staff PIN.
   `auth.users` is the identity layer for vendors/owners.
2. **Organization creation** — on signup, create a row in `public.organizations`
   (name, slug, gstin, phone, active) and link the signing-up user as its owner.
3. **Plan assignment** — auto-assign the plan from `public.subscription_plans`
   where `is_default_trial = true` (plan catalog: e.g. 'trial', 'starter', 'pro';
   each has price_inr, billing_period, limits jsonb like {"max_users":5,
   "max_orders":200}, features jsonb like {"whatsapp":true,"reports":false}).
4. **Onboarding** — collect business settings (GST, invoice numbering, branding)
   into the per-org settings table.
5. **In-app staff login** — the existing phone+PIN staff login remains, but ONLY
   as the intra-tenant staff-level login. It must be scoped to the vendor's org
   and eventually enforced by RLS, not client-side filters.
6. **Plan enforcement** — feature gating and limits in the app must read the
   org's plan (limits/features jsonb). Upgrade path exists (Razorpay planned,
   not yet integrated — leave a clean seam).
7. **Platform admin** — `public.platform_admins` users (the owner) can read
   across all tenants for support/oversight.

## Source of truth
- The multi-tenant schema was authored in June 2026 as `nagarva_schema.sql`
  (platform layer + tenant core + RLS + helper functions + seeded plans).
  FIRST STEP: check which of these tables already exist in Supabase project
  `hqqcapifefsaqvotqvlt` (organizations, subscription_plans, platform_admins,
  org settings). Ask the owner to run in the SQL editor:
    select table_name from information_schema.tables
    where table_schema='public' order by 1;
  and paste the output. Build only what is missing; do not blindly re-run DDL.
- The Nagarva web app (React, App.jsx) is the behavioural reference for the
  registration screens and plan logic. When a detail is ambiguous, ask the
  owner or mirror the web app.

## Impact on the Flutter app (new pages/logic to build)
- SignupPage (vendor registration), OrgSetupPage (business details/onboarding),
  PlanPage (current plan, limits, upgrade CTA).
- LoginPage becomes two-path: vendor login (Supabase Auth) and staff login
  (phone+PIN within the org).
- App state needs: current auth user, currentOrgId (derived from membership,
  not just the staff row), current plan (limits/features).
- All Phase 0/1 RLS work must be designed around auth.uid() membership in an
  org, with the staff-PIN path issued through an Edge Function.
