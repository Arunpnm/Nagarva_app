-- =============================================================================
-- 20261031_admin_panel.sql — Nagarva Admin: team & roles, support tickets,
-- coupons, in-app broadcasts and a chained audit log
-- =============================================================================
-- HANDED OVER, NOT RUN. One transaction; preflight refuses, postflight
-- asserts the constructs and probes the behaviour (all undone).
--
-- Design handoff, Nagarva Admin: Admin team, Support tickets, Coupons,
-- Broadcasts, Audit log. What each part is, and what it deliberately is not:
--
-- 1. ADMIN ROLES. platform_admins gains name, email, role (super | sales |
--    support | marketing) and active. The one existing admin becomes
--    'super'. is_platform_admin() now also requires active, so switching
--    someone off takes effect at once. Team changes go through
--    platform_admin_add / platform_admin_update (super only, and the last
--    active super admin cannot be demoted or switched off).
-- 2. SUPPORT TICKETS. A vendor raises one from Help & support; the vendor
--    and Nagarva reply on it. Vendors see only their own org's tickets.
--    Status: open (waiting on Nagarva) -> waiting (on the vendor) ->
--    resolved, moved by replies; admins (super, support) set priority,
--    assignee and resolve.
-- 3. COUPONS. Created and paused by super / marketing. NOT redeemable yet:
--    there is no checkout until subscription billing is decided (Item 31,
--    on hold). used_count is not app-writable; checkout will own it.
-- 4. BROADCASTS. In-app only. WhatsApp to vendors needs Nagarva's own
--    WhatsApp Business number, which does not exist yet (CLAUDE.md:
--    kNagarvaSupportPhone is empty on purpose), so the channel CHECK allows
--    'in_app' alone until it does. Recipients are fixed at send time, so a
--    vendor who joins later does not see old messages and the count shown
--    is the count sent.
-- 5. AUDIT LOG. platform_audit is append-only (no UPDATE/DELETE grant or
--    policy) and hash-chained: each row's hash covers the previous row's
--    hash, so editing or removing a row with the service key breaks the
--    chain, which platform_audit_verify() reports. Written by triggers:
--    team changes, plan edits, coupons, broadcasts, ticket status, and
--    every billing_events row (plan change, suspend, trial extension,
--    owner password reset, already written by the admin Edge Functions).
--    Vendors can read the rows about their own org.
--
-- Not here: Approvals for discounts and trial extensions above a role's
-- limit. Discounts need billing (Item 31), and extensions go through the
-- admin-update-org Edge Function, which would have to learn the limits;
-- both are their own change.
-- =============================================================================

begin;

set local search_path = public, extensions;

do $preflight$
begin
  if to_regclass('public.platform_admins') is null
     or to_regprocedure('public.is_platform_admin()') is null
     or to_regprocedure('public.current_org_ids()') is null then
    raise exception 'PREFLIGHT FAILED: platform_admins / is_platform_admin() / current_org_ids() missing';
  end if;
  if to_regclass('public.billing_events') is null or to_regclass('public.subscription_plans') is null then
    raise exception 'PREFLIGHT FAILED: billing_events or subscription_plans missing';
  end if;
  if to_regclass('public.support_tickets') is not null
     or to_regclass('public.platform_audit') is not null then
    raise exception 'PREFLIGHT FAILED: support_tickets or platform_audit already exists; this migration has run before';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where p.proname = 'digest' and n.nspname = 'extensions') then
    raise exception 'PREFLIGHT FAILED: pgcrypto digest() not found in schema extensions';
  end if;
  if (select count(*) from platform_admins) = 0 then
    raise exception 'PREFLIGHT FAILED: no platform admin exists; nobody would be super admin';
  end if;
end
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Admin roles
-- ---------------------------------------------------------------------------
alter table public.platform_admins
  add column name   text,
  add column email  text,
  add column role   text not null default 'super'
    check (role in ('super','sales','support','marketing')),
  add column active boolean not null default true;

update public.platform_admins pa
   set email = u.email
  from auth.users u
 where u.id = pa.user_id and pa.email is null;

create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from platform_admins where user_id = auth.uid() and active) $$;

-- The caller's admin role, or NULL when not an active admin.
create function public.platform_role()
returns text
language sql stable security definer set search_path = public
as $$ select role from platform_admins where user_id = auth.uid() and active $$;

-- Super admins pass every role check.
create function public.platform_has_role(variadic p_roles text[])
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(public.platform_role() = 'super'
                      or public.platform_role() = any (p_roles), false) $$;

create policy admins_select_team on public.platform_admins
  for select to authenticated using (public.is_platform_admin());
-- Team changes go only through the two functions below. Live, anon and
-- authenticated held table-level INSERT/UPDATE/DELETE here (blocked only by
-- the absence of a policy); now that the table carries roles, take them.
revoke insert, update, delete, truncate on public.platform_admins from public, anon, authenticated;
revoke all on public.platform_admins from anon;
grant select on public.platform_admins to authenticated;

-- Adds an existing account (it must have signed up) to the admin team.
create function public.platform_admin_add(p_email text, p_name text, p_role text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid;
begin
  if not public.platform_has_role('super') then
    raise exception 'Only a super admin can change the admin team.';
  end if;
  if p_role not in ('super','sales','support','marketing') then
    raise exception 'Unknown role %.', p_role;
  end if;
  if nullif(btrim(p_name), '') is null then
    raise exception 'Enter the person''s name.';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(btrim(p_email));
  if v_uid is null then
    raise exception 'No account uses %. Ask them to sign up first, then add them.', btrim(p_email);
  end if;
  if exists (select 1 from platform_admins where user_id = v_uid) then
    raise exception '% is already on the admin team.', btrim(p_email);
  end if;
  insert into platform_admins (user_id, name, email, role, active)
  values (v_uid, btrim(p_name), lower(btrim(p_email)), p_role, true);
  return v_uid;
end
$$;

create function public.platform_admin_update(p_user uuid, p_role text, p_active boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  cur platform_admins;
begin
  if not public.platform_has_role('super') then
    raise exception 'Only a super admin can change the admin team.';
  end if;
  if p_role not in ('super','sales','support','marketing') then
    raise exception 'Unknown role %.', p_role;
  end if;
  select * into cur from platform_admins where user_id = p_user for update;
  if cur.user_id is null then
    raise exception 'That person is not on the admin team.';
  end if;
  if cur.role = 'super' and cur.active and (p_role <> 'super' or not p_active)
     and (select count(*) from platform_admins where role = 'super' and active) = 1 then
    raise exception 'Keep at least one active super admin.';
  end if;
  update platform_admins set role = p_role, active = p_active where user_id = p_user;
end
$$;

-- ---------------------------------------------------------------------------
-- 5 (first, the others' triggers write to it). Audit log
-- ---------------------------------------------------------------------------
create table public.platform_audit (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  actor       uuid,
  actor_name  text,
  actor_role  text,
  org_id      uuid,
  action      text not null,
  detail      jsonb not null default '{}',
  prev_hash   text,
  hash        text not null
);
create index platform_audit_org_idx on public.platform_audit (org_id, at desc);

alter table public.platform_audit enable row level security;
create policy platform_audit_admin_read on public.platform_audit
  for select to authenticated using (public.is_platform_admin());
create policy platform_audit_vendor_read on public.platform_audit
  for select to authenticated using (org_id in (select public.current_org_ids()));
revoke all on public.platform_audit from public, anon, authenticated;
grant select on public.platform_audit to authenticated;

-- Fills prev_hash and hash. One writer at a time, so the chain is a line.
create function public.platform_audit_chain()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  perform pg_advisory_xact_lock(hashtext('platform_audit'));
  select hash into new.prev_hash from platform_audit order by id desc limit 1;
  new.hash := encode(digest(
      coalesce(new.prev_hash, '') || '|' || extract(epoch from new.at)::text || '|' ||
      coalesce(new.actor::text, '') || '|' || coalesce(new.org_id::text, '') || '|' ||
      new.action || '|' || new.detail::text, 'sha256'), 'hex');
  return new;
end
$$;
create trigger platform_audit_chain before insert on public.platform_audit
  for each row execute function public.platform_audit_chain();

-- Writes one audit row as the current user (or p_actor when given).
create function public.platform_log(p_action text, p_org uuid, p_detail jsonb, p_actor uuid default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_actor uuid := coalesce(p_actor, auth.uid());
  a platform_admins;
begin
  select * into a from platform_admins where user_id = v_actor;
  insert into platform_audit (actor, actor_name, actor_role, org_id, action, detail, hash)
  values (v_actor, coalesce(a.name, a.email), a.role, p_org, p_action,
          coalesce(p_detail, '{}'), '');
end
$$;

-- NULL when every row's hash matches; otherwise the first id that does not.
create function public.platform_audit_verify()
returns bigint
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  r platform_audit;
  v_prev text;
begin
  if not public.is_platform_admin() then
    raise exception 'Only Nagarva admins can verify the audit log.';
  end if;
  for r in select * from platform_audit order by id loop
    if r.prev_hash is distinct from v_prev
       or r.hash <> encode(digest(
            coalesce(r.prev_hash, '') || '|' || extract(epoch from r.at)::text || '|' ||
            coalesce(r.actor::text, '') || '|' || coalesce(r.org_id::text, '') || '|' ||
            r.action || '|' || r.detail::text, 'sha256'), 'hex') then
      return r.id;
    end if;
    v_prev := r.hash;
  end loop;
  return null;
end
$$;

-- billing_events -> audit. The admin Edge Functions put who did it in
-- detail.changed_by / detail.requested_by.
create function public.platform_audit_from_billing()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform public.platform_log(new.event_type, new.org_id, coalesce(new.detail, '{}'),
    coalesce(nullif(new.detail->>'changed_by', ''), nullif(new.detail->>'requested_by', ''))::uuid);
  return new;
end
$$;
create trigger platform_audit_from_billing after insert on public.billing_events
  for each row execute function public.platform_audit_from_billing();

create function public.platform_audit_team()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.platform_log('admin_added', null,
      jsonb_build_object('email', new.email, 'name', new.name, 'role', new.role));
  elsif (old.role, old.active) is distinct from (new.role, new.active) then
    perform public.platform_log('admin_changed', null,
      jsonb_build_object('email', new.email, 'name', new.name,
        'role', jsonb_build_object('from', old.role, 'to', new.role),
        'active', jsonb_build_object('from', old.active, 'to', new.active)));
  end if;
  return null;
end
$$;
create trigger platform_audit_team after insert or update on public.platform_admins
  for each row execute function public.platform_audit_team();

create function public.platform_audit_plans()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v jsonb := '{}';
  k text;
begin
  foreach k in array array['name','price_inr','billing_period','limits','features','active','trial_days','grace_days'] loop
    if to_jsonb(old) -> k is distinct from to_jsonb(new) -> k then
      v := v || jsonb_build_object(k, jsonb_build_object('from', to_jsonb(old) -> k, 'to', to_jsonb(new) -> k));
    end if;
  end loop;
  if v <> '{}' then
    perform public.platform_log('plan_edited', null, jsonb_build_object('plan', new.code) || v);
  end if;
  return null;
end
$$;
create trigger platform_audit_plans after update on public.subscription_plans
  for each row execute function public.platform_audit_plans();

-- ---------------------------------------------------------------------------
-- 2. Support tickets
-- ---------------------------------------------------------------------------
create table public.support_tickets (
  id             uuid primary key default gen_random_uuid(),
  ticket_no      bigint generated always as identity (start with 1001) unique,
  org_id         uuid not null references public.organizations(id) on delete cascade,
  raised_by      uuid default auth.uid(),
  raised_by_name text,
  subject        text not null check (length(btrim(subject)) between 3 and 200),
  body           text not null check (length(btrim(body)) between 1 and 4000),
  priority       text not null default 'normal' check (priority in ('normal','high')),
  status         text not null default 'open' check (status in ('open','waiting','resolved')),
  assigned_to    uuid references public.platform_admins(user_id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index support_tickets_org_idx on public.support_tickets (org_id, created_at desc);
create index support_tickets_status_idx on public.support_tickets (status, updated_at desc);

create table public.support_ticket_replies (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.support_tickets(id) on delete cascade,
  author      uuid default auth.uid(),
  author_name text,
  from_admin  boolean not null,
  body        text not null check (length(btrim(body)) between 1 and 4000),
  created_at  timestamptz not null default now()
);
create index support_ticket_replies_ticket_idx on public.support_ticket_replies (ticket_id, created_at);

alter table public.support_tickets enable row level security;
alter table public.support_ticket_replies enable row level security;

create policy support_tickets_vendor_read on public.support_tickets
  for select to authenticated using (org_id in (select public.current_org_ids()));
-- A vendor raises a ticket for their own org, as themselves, as a plain
-- open ticket: priority, status and assignee are Nagarva's to set.
create policy support_tickets_vendor_insert on public.support_tickets
  for insert to authenticated
  with check (org_id in (select public.current_org_ids())
              and raised_by = auth.uid()
              and priority = 'normal' and status = 'open' and assigned_to is null);
create policy support_tickets_admin_read on public.support_tickets
  for select to authenticated using (public.platform_has_role('support'));
create policy support_tickets_admin_update on public.support_tickets
  for update to authenticated
  using (public.platform_has_role('support')) with check (public.platform_has_role('support'));

create policy support_replies_read on public.support_ticket_replies
  for select to authenticated
  using (exists (select 1 from public.support_tickets t where t.id = ticket_id));
create policy support_replies_vendor_insert on public.support_ticket_replies
  for insert to authenticated
  with check (not from_admin and author = auth.uid()
              and exists (select 1 from public.support_tickets t
                           where t.id = ticket_id
                             and t.org_id in (select public.current_org_ids())));
create policy support_replies_admin_insert on public.support_ticket_replies
  for insert to authenticated
  with check (from_admin and author = auth.uid() and public.platform_has_role('support'));

revoke all on public.support_tickets, public.support_ticket_replies from public, anon, authenticated;
grant select on public.support_tickets, public.support_ticket_replies to authenticated;
grant insert (org_id, raised_by, raised_by_name, subject, body)
  on public.support_tickets to authenticated;
grant update (priority, status, assigned_to, updated_at)
  on public.support_tickets to authenticated;
grant insert (ticket_id, author, author_name, from_admin, body)
  on public.support_ticket_replies to authenticated;

-- A reply moves the ticket: Nagarva replying means it now waits on the
-- vendor; the vendor replying reopens it. A resolved ticket reopens when
-- the vendor writes again.
create function public.support_reply_moves_ticket()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  update support_tickets
     set status = case when new.from_admin
                       then case when status = 'resolved' then status else 'waiting' end
                       else 'open' end,
         updated_at = now()
   where id = new.ticket_id;
  return null;
end
$$;
create trigger support_reply_moves_ticket after insert on public.support_ticket_replies
  for each row execute function public.support_reply_moves_ticket();

create function public.platform_audit_tickets()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if (old.status, old.priority, old.assigned_to) is distinct from (new.status, new.priority, new.assigned_to)
     and public.is_platform_admin() then
    perform public.platform_log('ticket_changed', new.org_id,
      jsonb_build_object('ticket', 'T-' || new.ticket_no, 'subject', new.subject,
        'status', jsonb_build_object('from', old.status, 'to', new.status),
        'priority', jsonb_build_object('from', old.priority, 'to', new.priority)));
  end if;
  return null;
end
$$;
create trigger platform_audit_tickets after update on public.support_tickets
  for each row execute function public.platform_audit_tickets();

-- ---------------------------------------------------------------------------
-- 3. Coupons
-- ---------------------------------------------------------------------------
create table public.platform_coupons (
  code        text primary key check (code ~ '^[A-Z0-9]{3,20}$'),
  kind        text not null check (kind in ('pct','flat')),
  value       numeric not null check (value > 0),
  plan_codes  text[] not null check (cardinality(plan_codes) > 0),
  valid_until date not null,
  max_uses    int not null check (max_uses > 0),
  used_count  int not null default 0 check (used_count >= 0),
  active      boolean not null default true,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  check (kind <> 'pct' or value <= 100)
);
alter table public.platform_coupons enable row level security;
create policy platform_coupons_read on public.platform_coupons
  for select to authenticated using (public.platform_has_role('marketing', 'sales'));
create policy platform_coupons_insert on public.platform_coupons
  for insert to authenticated
  with check (public.platform_has_role('marketing') and created_by = auth.uid() and used_count = 0);
create policy platform_coupons_update on public.platform_coupons
  for update to authenticated
  using (public.platform_has_role('marketing')) with check (public.platform_has_role('marketing'));
revoke all on public.platform_coupons from public, anon, authenticated;
grant select on public.platform_coupons to authenticated;
grant insert (code, kind, value, plan_codes, valid_until, max_uses, active, created_by)
  on public.platform_coupons to authenticated;
grant update (active) on public.platform_coupons to authenticated;

create function public.platform_audit_coupons()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.platform_log('coupon_created', null,
      jsonb_build_object('code', new.code, 'kind', new.kind, 'value', new.value,
        'plans', new.plan_codes, 'valid_until', new.valid_until, 'max_uses', new.max_uses));
  elsif old.active is distinct from new.active then
    perform public.platform_log(case when new.active then 'coupon_resumed' else 'coupon_paused' end,
      null, jsonb_build_object('code', new.code));
  end if;
  return null;
end
$$;
create trigger platform_audit_coupons after insert or update on public.platform_coupons
  for each row execute function public.platform_audit_coupons();

-- ---------------------------------------------------------------------------
-- 4. Broadcasts (in-app)
-- ---------------------------------------------------------------------------
create table public.platform_broadcasts (
  id             uuid primary key default gen_random_uuid(),
  channel        text not null default 'in_app' check (channel in ('in_app')),
  audience       text not null check (audience in ('all','plan','city','trial','expiring')),
  audience_value text,
  body           text not null check (length(btrim(body)) between 1 and 1000),
  recipients     int not null default 0,
  created_by     uuid default auth.uid(),
  created_at     timestamptz not null default now(),
  check ((audience in ('plan','city')) = (nullif(btrim(audience_value), '') is not null))
);
create table public.platform_broadcast_recipients (
  broadcast_id uuid not null references public.platform_broadcasts(id) on delete cascade,
  org_id       uuid not null references public.organizations(id) on delete cascade,
  read_at      timestamptz,
  primary key (broadcast_id, org_id)
);
create index platform_broadcast_recipients_org_idx on public.platform_broadcast_recipients (org_id, read_at);

alter table public.platform_broadcasts enable row level security;
alter table public.platform_broadcast_recipients enable row level security;
create policy platform_broadcasts_admin_read on public.platform_broadcasts
  for select to authenticated using (public.platform_has_role('marketing'));
create policy platform_broadcasts_vendor_read on public.platform_broadcasts
  for select to authenticated
  using (exists (select 1 from public.platform_broadcast_recipients r
                  where r.broadcast_id = platform_broadcasts.id and r.org_id in (select public.current_org_ids())));
create policy platform_broadcasts_insert on public.platform_broadcasts
  for insert to authenticated
  with check (public.platform_has_role('marketing') and created_by = auth.uid() and recipients = 0);
create policy broadcast_recipients_vendor_read on public.platform_broadcast_recipients
  for select to authenticated using (org_id in (select public.current_org_ids()));
create policy broadcast_recipients_vendor_mark_read on public.platform_broadcast_recipients
  for update to authenticated
  using (org_id in (select public.current_org_ids()))
  with check (org_id in (select public.current_org_ids()));
revoke all on public.platform_broadcasts, public.platform_broadcast_recipients from public, anon, authenticated;
grant select on public.platform_broadcasts, public.platform_broadcast_recipients to authenticated;
grant insert (channel, audience, audience_value, body, created_by)
  on public.platform_broadcasts to authenticated;
grant update (read_at) on public.platform_broadcast_recipients to authenticated;

-- Which orgs an audience reaches today. Suspended orgs are skipped.
create function public.platform_audience_orgs(p_audience text, p_value text)
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select o.id
    from organizations o
    left join subscription_plans p on p.id = o.plan_id
   where coalesce(o.active, true)
     and case p_audience
           when 'all'      then true
           when 'plan'     then p.code = p_value
           when 'city'     then lower(btrim(o.city)) = lower(btrim(p_value))
           when 'trial'    then o.plan_status = 'trial'
           when 'expiring' then o.plan_status in ('trial','grace')
                                and o.trial_ends_at between now() and now() + interval '7 days'
           else false
         end
$$;

-- How many vendors a broadcast would reach, for the Send button.
create function public.platform_audience_count(p_audience text, p_value text)
returns int
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.platform_has_role('marketing') then
    raise exception 'Only super and marketing admins can send broadcasts.';
  end if;
  return (select count(*) from public.platform_audience_orgs(p_audience, p_value));
end
$$;

create function public.platform_broadcast_fanout()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_n int;
begin
  insert into platform_broadcast_recipients (broadcast_id, org_id)
  select new.id, x from public.platform_audience_orgs(new.audience, new.audience_value) x;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'This audience has no vendors, so nothing was sent.';
  end if;
  update platform_broadcasts set recipients = v_n where id = new.id;
  perform public.platform_log('broadcast_sent', null,
    jsonb_build_object('channel', new.channel, 'audience', new.audience,
      'audience_value', new.audience_value, 'recipients', v_n, 'body', new.body));
  return null;
end
$$;
create trigger platform_broadcast_fanout after insert on public.platform_broadcasts
  for each row execute function public.platform_broadcast_fanout();

-- ---------------------------------------------------------------------------
-- Function grants. Supabase grants new functions to anon and authenticated
-- by name, so every revoke names them (see 20261031_marketplace_addon_slabs).
-- ---------------------------------------------------------------------------
do $grants$
declare
  f text;
begin
  foreach f in array array[
    'public.platform_role()', 'public.platform_has_role(text[])',
    'public.platform_admin_add(text,text,text)', 'public.platform_admin_update(uuid,text,boolean)',
    'public.platform_audit_chain()', 'public.platform_log(text,uuid,jsonb,uuid)',
    'public.platform_audit_verify()', 'public.platform_audit_from_billing()',
    'public.platform_audit_team()', 'public.platform_audit_plans()',
    'public.support_reply_moves_ticket()', 'public.platform_audit_tickets()',
    'public.platform_audit_coupons()', 'public.platform_audience_orgs(text,text)',
    'public.platform_audience_count(text,text)', 'public.platform_broadcast_fanout()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  -- The ones the app calls. Each checks the caller's role itself.
  foreach f in array array[
    'public.platform_role()', 'public.platform_has_role(text[])',
    'public.platform_admin_add(text,text,text)', 'public.platform_admin_update(uuid,text,boolean)',
    'public.platform_audit_verify()', 'public.platform_audience_count(text,text)'] loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$grants$;

-- ---------------------------------------------------------------------------
-- Postflight
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_bad   int;
  v_t     text;
  v_admin uuid;
  v_org   uuid;
  v_tid   uuid;
  v_n     int;
  v_audit bigint;
begin
  -- RLS on, anon holds nothing on any new table.
  foreach v_t in array array['platform_audit','support_tickets','support_ticket_replies',
                             'platform_coupons','platform_broadcasts','platform_broadcast_recipients'] loop
    if not (select relrowsecurity from pg_class where oid = ('public.' || v_t)::regclass) then
      raise exception 'POSTFLIGHT: RLS off on %', v_t;
    end if;
    if has_table_privilege('anon', 'public.' || v_t, 'select')
       or has_table_privilege('anon', 'public.' || v_t, 'insert') then
      raise exception 'POSTFLIGHT: anon can reach %', v_t;
    end if;
  end loop;
  -- The audit log cannot be edited from the app, and used_count cannot be
  -- set by an admin.
  if has_table_privilege('authenticated', 'public.platform_audit', 'insert')
     or has_table_privilege('authenticated', 'public.platform_audit', 'update')
     or has_table_privilege('authenticated', 'public.platform_audit', 'delete') then
    raise exception 'POSTFLIGHT: the app can write platform_audit';
  end if;
  if has_column_privilege('authenticated', 'public.platform_coupons', 'used_count', 'update')
     or has_column_privilege('authenticated', 'public.platform_coupons', 'used_count', 'insert') then
    raise exception 'POSTFLIGHT: the app can set coupon used_count';
  end if;
  if has_table_privilege('authenticated', 'public.platform_admins', 'insert')
     or has_table_privilege('authenticated', 'public.platform_admins', 'update')
     or has_table_privilege('anon', 'public.platform_admins', 'select') then
    raise exception 'POSTFLIGHT: platform_admins is writable from the app, or readable by anon';
  end if;
  if has_column_privilege('authenticated', 'public.support_tickets', 'org_id', 'update') then
    raise exception 'POSTFLIGHT: a ticket can be moved to another org';
  end if;
  -- No PUBLIC or anon execute on any new function.
  select count(*) into v_bad
    from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like 'platform\_%' or p.proname like 'support\_%')
     and a.privilege_type = 'EXECUTE' and a.grantee in (0, 'anon'::regrole);
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: PUBLIC or anon can execute a new admin function';
  end if;
  -- Every existing admin is now an active super admin.
  if exists (select 1 from platform_admins where role <> 'super' or not active) then
    raise exception 'POSTFLIGHT: an existing admin did not become an active super admin';
  end if;

  -- Behaviour, all undone below: a broadcast reaches every active org and
  -- is logged; a reply moves a ticket; the chain verifies, then detects a
  -- tampered row.
  select user_id into v_admin from platform_admins limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  if public.platform_role() is distinct from 'super' then
    raise exception 'POSTFLIGHT: the admin does not read as super';
  end if;

  select count(*) into v_n from organizations where coalesce(active, true);
  insert into platform_broadcasts (audience, body, created_by)
  values ('all', 'postflight probe', v_admin);
  if (select recipients from platform_broadcasts where body = 'postflight probe') <> v_n then
    raise exception 'POSTFLIGHT: broadcast did not reach the % active vendors', v_n;
  end if;

  select id into v_org from organizations order by created_at limit 1;
  insert into support_tickets (org_id, raised_by, subject, body)
  values (v_org, v_admin, 'postflight probe', 'probe') returning id into v_tid;
  insert into support_ticket_replies (ticket_id, author, from_admin, body)
  values (v_tid, v_admin, true, 'probe reply');
  if (select status from support_tickets where id = v_tid) <> 'waiting' then
    raise exception 'POSTFLIGHT: a Nagarva reply did not move the ticket to waiting';
  end if;
  insert into support_ticket_replies (ticket_id, author, from_admin, body)
  values (v_tid, v_admin, false, 'probe vendor reply');
  if (select status from support_tickets where id = v_tid) <> 'open' then
    raise exception 'POSTFLIGHT: a vendor reply did not reopen the ticket';
  end if;

  if (select count(*) from platform_audit where action = 'broadcast_sent') <> 1 then
    raise exception 'POSTFLIGHT: the broadcast was not logged';
  end if;
  if public.platform_audit_verify() is not null then
    raise exception 'POSTFLIGHT: the audit chain does not verify';
  end if;
  select max(id) into v_audit from platform_audit;
  update platform_audit set detail = '{"tampered":true}' where id = v_audit;
  if public.platform_audit_verify() is distinct from v_audit then
    raise exception 'POSTFLIGHT: a tampered audit row was not detected';
  end if;

  -- Undo the probe.
  delete from support_tickets where id = v_tid;
  delete from platform_broadcasts where body = 'postflight probe';
  delete from platform_audit;
  perform set_config('request.jwt.claims', '', true);
end
$postflight$;

commit;
