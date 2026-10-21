-- ============================================================
-- 20261021_vendor_signup_approval.sql
--
-- Vendor self-signup, approval first (Claude Design handoff, 21 Oct 2026,
-- App screen 'signup' + Admin › Approvals › "New vendor signups").
-- Arun's calls, 21 Oct 2026:
--   * mobile number + SMS OTP (Supabase Auth phone sign-in),
--   * the account goes live only after the Nagarva team approves it,
--   * an approved vendor chooses "Start 30-day Pro trial" or "Stay on
--     Free"; an expired Pro trial falls back to Free, it does NOT lock.
--
-- HANDED OVER, NOT RUN. Run the whole file in the SQL editor; it is one
-- transaction and its postflight raises (rolling everything back) if any
-- construct is missing.
--
-- What it adds:
--   1. subscription_plans row 'free' (3 users, 20 orders/month, no
--      WhatsApp/reports/multi-branch; gst_invoice is never gated).
--   2. organizations.trial_fallback_plan_id — the plan an expired trial
--      drops to. NULL on every existing org, so their behaviour is
--      byte-for-byte unchanged (expired trial -> grace -> read-only).
--   3. org_effective_plan(): when the trial has ended AND a fallback is
--      set, report the fallback plan and NOT locked. org_limit,
--      org_has_feature and assert_org_writable all read through this one
--      function (checked live 21 Oct), so the fallback is enforced
--      everywhere at once.
--   4. vendor_signups — one application per auth user. RLS: applicant
--      reads own row, platform admins read all; NO write policies —
--      every write goes through the three functions below.
--   5. Storage bucket 'vendor-docs' (private): applicant writes/reads
--      under '<auth.uid()>/', platform admins read all.
--   6. submit_vendor_signup(), review_vendor_signup(),
--      choose_signup_plan() — SECURITY DEFINER, PUBLIC/anon revoked.
--   7. platform_settings 'signup_requires_approval' = true, read by the
--      create-org Edge Function so the old email signup cannot create an
--      org around the approval step. That function change ships in the
--      same commit and must be DEPLOYED AFTER this file runs.
--
-- PREREQUISITE OUTSIDE SQL: Authentication › Providers › Phone must be
-- enabled with an SMS provider (MSG91 / Twilio). Until then
-- signInWithOtp(phone:) fails and the signup screen says so.
-- ============================================================

begin;
set local search_path = public, extensions;

-- ---------- preflight ----------
do $$
begin
  if to_regprocedure('public.org_effective_plan(uuid)') is null then
    raise exception 'org_effective_plan(uuid) is missing — run Item 32 (20260818_item32_plan_enforcement.sql) first';
  end if;
  if to_regprocedure('public.create_org_with_owner(uuid,text,text,text,text,text)') is null then
    raise exception 'create_org_with_owner(uuid,text,text,text,text,text) is missing — run 20260812_owner_name_persistence.sql first';
  end if;
  if to_regprocedure('public.is_platform_admin()') is null then
    raise exception 'is_platform_admin() is missing';
  end if;
  if to_regclass('public.platform_settings') is null then
    raise exception 'platform_settings is missing — run 20260816_invite_codes.sql first';
  end if;
  if not exists (select 1 from subscription_plans where code = 'pro') then
    raise exception 'No subscription_plans row with code ''pro'' — the trial needs one';
  end if;
end $$;

-- ---------- 1. Free plan ----------
insert into subscription_plans
  (code, name, price_inr, billing_period, is_default_trial, active,
   trial_days, grace_days, limits, features)
values
  ('free', 'Free', 0, 'monthly', false, true, 0, 0,
   '{"max_users":3,"max_orders_per_month":20,"max_whatsapp_per_month":0}'::jsonb,
   '{"reports":false,"whatsapp":false,"gst_invoice":true,"multi_branch":false}'::jsonb)
on conflict (code) do nothing;

-- ---------- 2. trial fallback column ----------
alter table organizations
  add column if not exists trial_fallback_plan_id uuid
  references subscription_plans(id);

comment on column organizations.trial_fallback_plan_id is
  'Plan an expired trial drops to (vendor signup, 21 Oct 2026). NULL = old behaviour: expired trial -> grace -> read-only.';

-- ---------- 3. org_effective_plan with fallback ----------
create or replace function public.org_effective_plan(p_org_id uuid)
returns table(plan_code text, limits jsonb, features jsonb, is_locked boolean)
language sql
stable security definer
set search_path to 'public'
as $function$
  -- A trial that has ended and names a fallback plan reports the
  -- fallback, unlocked: "after 30 days you move to the Free plan
  -- automatically. Your data stays." Everything else is unchanged.
  with o as (
    select o.*,
           (o.plan_status = 'trial'
            and o.trial_ends_at is not null
            and o.trial_ends_at < now()
            and o.trial_fallback_plan_id is not null) as fell_back
      from organizations o
     where o.id = p_org_id
  )
  select
    sp.code,
    coalesce(sp.limits, '{}'::jsonb),
    coalesce(sp.features, '{}'::jsonb),
    (not o.fell_back
      and o.plan_status = 'trial'
      and o.trial_ends_at is not null
      and o.trial_ends_at + make_interval(days => coalesce(sp.grace_days, 0)) < now())
    or not coalesce(o.active, true)
  from o
  left join subscription_plans sp
    on sp.id = case when o.fell_back then o.trial_fallback_plan_id else o.plan_id end
$function$;

-- ---------- 4. vendor_signups ----------
create table if not exists vendor_signups (
  id             uuid primary key default gen_random_uuid(),
  app_no         text not null unique,
  auth_user_id   uuid not null unique references auth.users(id) on delete cascade,
  phone          text not null,
  business_name  text not null,
  owner_name     text not null,
  email          text,
  city           text not null,
  business_type  text not null check (business_type in ('packers_movers','transport','both')),
  gstin          text check (gstin is null or length(gstin) = 15),
  referral_code  text,
  docs           jsonb not null default '{}'::jsonb,
  status         text not null default 'pending'
                   check (status in ('pending','approved','rejected')),
  reason         text,
  org_id         uuid references organizations(id),
  reviewed_by    uuid references auth.users(id),
  reviewed_at    timestamptz,
  plan_choice    text check (plan_choice in ('trial','free')),
  plan_chosen_at timestamptz,
  terms_accepted_at timestamptz not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create sequence if not exists vendor_signup_no_seq start 3101;
revoke all on sequence vendor_signup_no_seq from public, anon, authenticated;

alter table vendor_signups enable row level security;

drop policy if exists vendor_signups_select on vendor_signups;
create policy vendor_signups_select on vendor_signups
  for select to authenticated
  using (auth_user_id = auth.uid() or is_platform_admin());
-- No insert/update/delete policy on purpose: writes go through the
-- SECURITY DEFINER functions below, which validate and decide status.

revoke all on vendor_signups from anon;
revoke insert, update, delete, truncate on vendor_signups from authenticated;
grant select on vendor_signups to authenticated;

-- ---------- 5. documents bucket ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vendor-docs', 'vendor-docs', false, 10485760,
        array['image/jpeg','image/png','image/webp','image/heic','application/pdf'])
on conflict (id) do nothing;

drop policy if exists vendor_docs_own_insert on storage.objects;
create policy vendor_docs_own_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'vendor-docs'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists vendor_docs_own_select on storage.objects;
create policy vendor_docs_own_select on storage.objects
  for select to authenticated
  using (bucket_id = 'vendor-docs'
         and ((storage.foldername(name))[1] = auth.uid()::text
              or public.is_platform_admin()));

drop policy if exists vendor_docs_own_delete on storage.objects;
create policy vendor_docs_own_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'vendor-docs'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------- 6a. submit (applicant) ----------
create or replace function public.submit_vendor_signup(
  p_business_name text,
  p_owner_name    text,
  p_city          text,
  p_business_type text,
  p_email         text default null,
  p_gstin         text default null,
  p_referral_code text default null,
  p_docs          jsonb default '{}'::jsonb
)
returns vendor_signups
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  v_phone text;
  v_row   vendor_signups;
  v_gst   text := nullif(upper(trim(coalesce(p_gstin, ''))), '');
  v_email text := nullif(trim(coalesce(p_email, '')), '');
begin
  if v_uid is null then
    raise exception 'Sign in with your mobile number first.' using errcode = 'P0001';
  end if;

  -- The phone is the verified one on the auth user, never a client value.
  select u.phone into v_phone from auth.users u where u.id = v_uid;
  if coalesce(v_phone, '') = '' then
    raise exception 'Verify your mobile number with the OTP before submitting.' using errcode = 'P0001';
  end if;

  if exists (select 1 from org_members m where m.user_id = v_uid) then
    raise exception 'This number already has a business account. Log in instead.' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_business_name), '') = '' or coalesce(trim(p_owner_name), '') = ''
     or coalesce(trim(p_city), '') = '' then
    raise exception 'Fill business name, owner name and city.' using errcode = 'P0001';
  end if;
  if p_business_type not in ('packers_movers','transport','both') then
    raise exception 'Pick what your business does.' using errcode = 'P0001';
  end if;
  if v_gst is not null and length(v_gst) <> 15 then
    raise exception 'GSTIN should be 15 characters.' using errcode = 'P0001';
  end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Check the email address.' using errcode = 'P0001';
  end if;
  if coalesce(p_docs->>'pan', '') = '' then
    raise exception 'Upload your PAN card.' using errcode = 'P0001';
  end if;
  if v_gst is not null and coalesce(p_docs->>'gstc', '') = '' then
    raise exception 'Upload the GST certificate or remove the GSTIN.' using errcode = 'P0001';
  end if;
  -- Every document path must sit in the caller's own folder.
  if exists (select 1 from jsonb_each_text(p_docs) d
              where d.value <> '' and split_part(d.value, '/', 1) <> v_uid::text) then
    raise exception 'Upload the documents again.' using errcode = 'P0001';
  end if;

  select * into v_row from vendor_signups s where s.auth_user_id = v_uid for update;
  if found then
    if v_row.status = 'approved' then
      raise exception 'Your account is already approved.' using errcode = 'P0001';
    end if;
    update vendor_signups s set
      phone = v_phone,
      business_name = trim(p_business_name), owner_name = trim(p_owner_name),
      city = trim(p_city), business_type = p_business_type,
      email = v_email, gstin = v_gst,
      referral_code = nullif(trim(coalesce(p_referral_code, '')), ''),
      docs = coalesce(p_docs, '{}'::jsonb),
      status = 'pending', reason = null, reviewed_by = null, reviewed_at = null,
      terms_accepted_at = now(), updated_at = now()
    where s.id = v_row.id
    returning * into v_row;
  else
    insert into vendor_signups
      (app_no, auth_user_id, phone, business_name, owner_name, email, city,
       business_type, gstin, referral_code, docs, terms_accepted_at)
    values
      ('AP-' || nextval('vendor_signup_no_seq'), v_uid, v_phone,
       trim(p_business_name), trim(p_owner_name), v_email, trim(p_city),
       p_business_type, v_gst, nullif(trim(coalesce(p_referral_code, '')), ''),
       coalesce(p_docs, '{}'::jsonb), now())
    returning * into v_row;
  end if;
  return v_row;
end;
$function$;

-- ---------- 6b. review (platform admin) ----------
create or replace function public.review_vendor_signup(
  p_signup_id uuid,
  p_approve   boolean,
  p_reason    text default null
)
returns vendor_signups
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_row vendor_signups;
  v_org uuid;
  v_free uuid;
begin
  if not coalesce(is_platform_admin(), false) then
    raise exception 'Only the Nagarva team can review signups.' using errcode = 'P0001';
  end if;
  select * into v_row from vendor_signups where id = p_signup_id for update;
  if not found then
    raise exception 'Application not found.' using errcode = 'P0001';
  end if;
  if v_row.status <> 'pending' then
    raise exception 'Application % is already %.', v_row.app_no, v_row.status using errcode = 'P0001';
  end if;

  if not p_approve then
    if coalesce(trim(p_reason), '') = '' then
      raise exception 'Pick a reason before sending back.' using errcode = 'P0001';
    end if;
    update vendor_signups set status = 'rejected', reason = trim(p_reason),
      reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
    where id = v_row.id returning * into v_row;
    return v_row;
  end if;

  select id into v_free from subscription_plans where code = 'free';
  if v_free is null then
    raise exception 'No Free plan configured.' using errcode = 'P0001';
  end if;

  -- 'recover' hands back an existing org instead of making a second one,
  -- so a double approve can never produce two tenants.
  select r.org_id into v_org
    from create_org_with_owner(v_row.auth_user_id, v_row.business_name,
                               v_row.phone, v_row.gstin, v_row.owner_name,
                               'recover') r;

  -- Every approved business starts on Free (handoff: "You start on the
  -- Free plan"); the Pro trial is the owner's own choice afterwards.
  update organizations set
    plan_id = v_free, plan_status = 'active', trial_ends_at = null,
    trial_fallback_plan_id = null,
    city = coalesce(city, v_row.city),
    business_type = coalesce(business_type, v_row.business_type)
  where id = v_org;

  update vendor_signups set status = 'approved', reason = null, org_id = v_org,
    reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  where id = v_row.id returning * into v_row;
  return v_row;
end;
$function$;

-- ---------- 6c. plan choice (approved applicant, once) ----------
create or replace function public.choose_signup_plan(p_trial boolean)
returns vendor_signups
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row  vendor_signups;
  v_pro  record;
  v_free uuid;
begin
  select * into v_row from vendor_signups where auth_user_id = auth.uid() for update;
  if not found or v_row.status <> 'approved' or v_row.org_id is null then
    raise exception 'Your account is not approved yet.' using errcode = 'P0001';
  end if;
  -- One choice per business: a second call must not hand out a second
  -- 30-day trial.
  if v_row.plan_choice is not null then
    return v_row;
  end if;

  if p_trial then
    select id, trial_days into v_pro from subscription_plans where code = 'pro';
    select id into v_free from subscription_plans where code = 'free';
    update organizations set
      plan_id = v_pro.id, plan_status = 'trial',
      trial_ends_at = now() + make_interval(days => coalesce(v_pro.trial_days, 30)),
      trial_fallback_plan_id = v_free
    where id = v_row.org_id;
  end if;

  update vendor_signups set plan_choice = case when p_trial then 'trial' else 'free' end,
    plan_chosen_at = now(), updated_at = now()
  where id = v_row.id returning * into v_row;
  return v_row;
end;
$function$;

revoke all on function public.submit_vendor_signup(text,text,text,text,text,text,text,jsonb) from public, anon;
revoke all on function public.review_vendor_signup(uuid,boolean,text) from public, anon;
revoke all on function public.choose_signup_plan(boolean) from public, anon;
grant execute on function public.submit_vendor_signup(text,text,text,text,text,text,text,jsonb) to authenticated;
grant execute on function public.review_vendor_signup(uuid,boolean,text) to authenticated;
grant execute on function public.choose_signup_plan(boolean) to authenticated;

-- ---------- 7. approval flag for create-org ----------
insert into platform_settings (key, value)
values ('signup_requires_approval', 'true'::jsonb)
on conflict (key) do nothing;

-- ---------- postflight ----------
do $$
declare
  v_free uuid;
  v_org  uuid;
  r      record;
begin
  select id into v_free from subscription_plans where code = 'free';
  if v_free is null then raise exception 'postflight: free plan missing'; end if;

  if (select relrowsecurity from pg_class where oid = 'public.vendor_signups'::regclass) is not true then
    raise exception 'postflight: RLS is off on vendor_signups';
  end if;

  -- Nobody but the functions may write the table.
  if exists (select 1 from pg_policy where polrelid = 'public.vendor_signups'::regclass and polcmd <> 'r') then
    raise exception 'postflight: vendor_signups has a write policy';
  end if;

  -- PUBLIC and anon must hold EXECUTE on none of the three writers.
  for r in
    select p.oid::regprocedure::text sig, a.grantee
      from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid in ('public.submit_vendor_signup(text,text,text,text,text,text,text,jsonb)'::regprocedure,
                     'public.review_vendor_signup(uuid,boolean,text)'::regprocedure,
                     'public.choose_signup_plan(boolean)'::regprocedure)
       and a.privilege_type = 'EXECUTE'
       and (a.grantee = 0 or a.grantee = 'anon'::regrole)
  loop
    raise exception 'postflight: % is executable by %', r.sig, r.grantee;
  end loop;

  if not exists (select 1 from storage.buckets where id = 'vendor-docs' and public = false) then
    raise exception 'postflight: vendor-docs bucket missing or public';
  end if;

  -- Behaviour, both directions, on a real org: set it to an expired
  -- trial WITH a fallback (must read Free, unlocked), then WITHOUT (must
  -- read locked, i.e. the old behaviour is untouched). This block has an
  -- exception handler, so it is a subtransaction: the final P0002 undoes
  -- the probe writes, while any real failure above (P0001) is NOT caught
  -- and aborts the whole migration.
  select id into v_org from organizations limit 1;
  if v_org is null then
    raise exception 'postflight: no organization to probe org_effective_plan with';
  end if;

  update organizations set plan_status = 'trial',
    trial_ends_at = now() - interval '60 days', trial_fallback_plan_id = v_free
  where id = v_org;
  select * into r from org_effective_plan(v_org);
  if r.plan_code <> 'free' or r.is_locked then
    raise exception 'postflight: expired trial with fallback read as % locked=%', r.plan_code, r.is_locked;
  end if;

  update organizations set trial_fallback_plan_id = null where id = v_org;
  select * into r from org_effective_plan(v_org);
  if not r.is_locked then
    raise exception 'postflight: expired trial WITHOUT fallback is no longer locked — old behaviour changed';
  end if;

  raise exception using errcode = 'P0002', message = 'probe-rollback';
exception
  when sqlstate 'P0002' then
    null;  -- probe passed; its writes are rolled back with this block
end $$;

commit;
