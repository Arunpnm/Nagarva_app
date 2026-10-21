-- 20261021_whatsapp_cloud_api.sql
--
-- WhatsApp through Meta's Cloud API, per vendor (Arun, 21 Oct 2026:
-- "as of Nagarva it's a SaaS product so we give the template they will
-- fill accordingly").
--
-- THE MODEL
--   * Each vendor connects THEIR OWN WhatsApp Business number: phone
--     number ID, WhatsApp Business Account (WABA) ID and a permanent
--     access token from their Meta app. Messages go out under the
--     vendor's number and name; Meta bills the vendor.
--   * Nagarva supplies the wording: wa_template_library holds eight
--     utility templates. On connect, the vendor gets a copy of each in
--     wa_templates, which the app submits to Meta on the vendor's WABA.
--     Meta approves or rejects each one; nothing is sent until it is
--     approved.
--   * The vendor's business name is a template VARIABLE, filled from
--     organizations.name at send time, so one wording serves every
--     tenant and the platform's name never reaches a customer.
--
-- SECRETS NEVER TOUCH A TABLE THE APP CAN READ
--   The access token (and the Meta app secret, used to verify inbound
--   webhooks) go into Supabase Vault. wa_accounts holds only the vault
--   ids. wa_vault_put / wa_vault_get are executable by service_role ONLY,
--   i.e. by the `whatsapp` Edge Function, never by a client.
--
-- WHO WRITES WHAT
--   wa_accounts, wa_templates (except `enabled`): the Edge Function, with
--   the service role. The app can read them; it cannot insert, update or
--   delete them. The one column the app may write is
--   wa_templates.enabled — the Auto WhatsApp switch — and only an
--   owner/admin/manager. Column grants and row policy both enforce it,
--   because a column REVOKE is a no-op while table-level UPDATE is held
--   (21 Oct 2026, Tier B lockdown).
--
-- Plan gating already exists: features.whatsapp and
-- limits.max_whatsapp_per_month on subscription_plans. The Edge Function
-- enforces both at send time (CLAUDE.md, Item 32: "the whatsapp gate
-- belongs at the send Edge Function").
--
-- Handed over unrun.

begin;

set local search_path = public, extensions;

-- ---------------------------------------------------------------- preflight
do $$
begin
  if to_regclass('public.wa_contacts') is null or to_regclass('public.wa_messages') is null then
    raise exception 'wa_contacts / wa_messages missing — wrong database?';
  end if;
  if not exists (select 1 from pg_extension where extname = 'supabase_vault') then
    raise exception 'supabase_vault is not installed; enable Vault in the dashboard first.';
  end if;
  if to_regprocedure('public.is_org_manager(uuid)') is null then
    raise exception 'is_org_manager(uuid) missing — run the Tier A RLS migration first.';
  end if;
  if to_regclass('public.wa_accounts') is not null then
    raise exception 'wa_accounts already exists — this migration has already run.';
  end if;
end $$;

-- ---------------------------------------------------------------- library
create table public.wa_template_library (
  key        text primary key,
  label      text not null,                 -- shown in the app
  name       text not null unique,          -- Meta template name
  category   text not null default 'UTILITY',
  language   text not null default 'en',
  body       text not null,                 -- {{1}}, {{2}} … placeholders
  params     text[] not null,               -- what fills {{1}}, {{2}} …
  example    text[] not null,               -- sample values Meta requires
  sort_order int not null default 0,
  check (array_length(params, 1) = array_length(example, 1))
);

alter table public.wa_template_library enable row level security;
create policy wa_template_library_read on public.wa_template_library
  for select to authenticated using (true);
revoke all on public.wa_template_library from anon, authenticated;
grant select on public.wa_template_library to authenticated;

-- Utility wording. Rules Meta enforces and these follow: no variable at
-- the very start or end, a sample for every variable, no promotional
-- language. No money is invented: amounts are always the order's own.
insert into public.wa_template_library (key, label, name, body, params, example, sort_order) values
('enquiry_received', 'New enquiry', 'mv_enquiry_received',
 'Hi {{1}}, thank you for contacting {{2}}. We have received your moving enquiry and our team will call you shortly.',
 array['customer_name','business_name'], array['Ramesh','Sri Packers'], 10),
('survey_link', 'Survey link', 'mv_survey_link',
 'Hi {{1}}, this is {{2}}. Please list the items you are moving using this link: {{3}} It takes about five minutes.',
 array['customer_name','business_name','survey_link'], array['Ramesh','Sri Packers','https://example.com/s/abc'], 20),
('quote_shared', 'Quote shared', 'mv_quote_shared',
 'Hi {{1}}, your moving quote {{2}} from {{3}} is ready. The total is Rs {{4}}. Reply to this message if you have any questions.',
 array['customer_name','quote_no','business_name','amount'], array['Ramesh','QT-0061','Sri Packers','31,500'], 30),
('order_confirmed', 'Order confirmed', 'mv_order_confirmed',
 'Hi {{1}}, your move on {{2}} is confirmed with {{3}}. Your order number is {{4}}. We will share the crew details before the move.',
 array['customer_name','move_date','business_name','order_no'], array['Ramesh','24 Oct 2026','Sri Packers','SRI-1004'], 40),
('move_started', 'Move started', 'mv_move_started',
 'Hi {{1}}, your move (order {{2}}) has started. You can follow it here: {{3}} Thank you for choosing {{4}} for your move.',
 array['customer_name','order_no','track_link','business_name'], array['Ramesh','SRI-1004','https://example.com/t/abc','Sri Packers'], 50),
('delivered', 'Delivered', 'mv_delivered',
 'Hi {{1}}, your move (order {{2}}) has been delivered. Thank you for choosing {{3}}. We would be glad to hear how it went.',
 array['customer_name','order_no','business_name'], array['Ramesh','SRI-1004','Sri Packers'], 60),
('payment_received', 'Payment received', 'mv_payment_received',
 'Hi {{1}}, we have received Rs {{2}} for order {{3}}. Thank you. This message is from {{4}} for your records.',
 array['customer_name','amount','order_no','business_name'], array['Ramesh','5,000','SRI-1004','Sri Packers'], 70),
('balance_reminder', 'Balance reminder', 'mv_balance_reminder',
 'Hi {{1}}, a balance of Rs {{2}} is due for order {{3}}. Please contact {{4}} if you have already paid.',
 array['customer_name','amount','order_no','business_name'], array['Ramesh','12,000','SRI-1004','Sri Packers'], 80);

-- ---------------------------------------------------------------- accounts
create table public.wa_accounts (
  org_id               uuid primary key references public.organizations(id) on delete cascade,
  phone_number_id      text not null,
  waba_id              text not null,
  display_phone        text,
  verified_name        text,
  token_secret_id      uuid,               -- vault.secrets.id
  app_secret_id        uuid,               -- vault.secrets.id, for inbound webhooks
  webhook_verify_token text not null default encode(extensions.gen_random_bytes(18), 'hex'),
  status               text not null default 'connected'
                       check (status in ('connected','error','disconnected')),
  last_error           text,
  connected_at         timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create unique index wa_accounts_phone_uniq on public.wa_accounts (phone_number_id);

alter table public.wa_accounts enable row level security;
-- Owner/admin/manager only: the verify token is not for every staff phone.
create policy wa_accounts_read on public.wa_accounts
  for select to authenticated using (coalesce(public.is_org_manager(org_id), false));
revoke all on public.wa_accounts from anon, authenticated;
grant select on public.wa_accounts to authenticated;

-- ---------------------------------------------------------------- templates
create table public.wa_templates (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations(id) on delete cascade,
  key              text not null references public.wa_template_library(key),
  name             text not null,
  language         text not null default 'en',
  status           text not null default 'draft'
                   check (status in ('draft','pending','approved','rejected','paused','disabled')),
  meta_template_id text,
  rejected_reason  text,
  enabled          boolean not null default false,  -- the Auto WhatsApp switch
  updated_at       timestamptz not null default now(),
  unique (org_id, key)
);

alter table public.wa_templates enable row level security;
create policy wa_templates_read on public.wa_templates
  for select to authenticated using (org_id in (select public.current_org_ids()));
create policy wa_templates_toggle on public.wa_templates
  for update to authenticated
  using (coalesce(public.is_org_manager(org_id), false))
  with check (coalesce(public.is_org_manager(org_id), false));
revoke all on public.wa_templates from anon, authenticated;
grant select on public.wa_templates to authenticated;
grant update (enabled) on public.wa_templates to authenticated;

-- ---------------------------------------------------------------- messages
alter table public.wa_messages
  add column if not exists template_key  text,
  add column if not exists entity_type   text,
  add column if not exists entity_id     text,
  add column if not exists error_message text;

-- ---------------------------------------------------------------- vault access
-- service_role only. p_kind is 'token' or 'app_secret'.
create function public.wa_vault_put(p_org uuid, p_kind text, p_value text)
returns uuid
language plpgsql
security definer
set search_path = public, vault
as $fn$
declare
  v_col text;
  v_id  uuid;
begin
  if p_kind not in ('token','app_secret') then
    raise exception 'unknown secret kind %', p_kind;
  end if;
  v_col := case p_kind when 'token' then 'token_secret_id' else 'app_secret_id' end;
  execute format('select %I from public.wa_accounts where org_id = $1', v_col)
     into v_id using p_org;
  if p_value is null or p_value = '' then
    if v_id is not null then
      delete from vault.secrets where id = v_id;
      execute format('update public.wa_accounts set %I = null where org_id = $1', v_col) using p_org;
    end if;
    return null;
  end if;
  if v_id is null then
    v_id := vault.create_secret(p_value, 'wa_' || p_kind || '_' || p_org::text,
                                'WhatsApp Cloud API ' || p_kind);
    execute format('update public.wa_accounts set %I = $2 where org_id = $1', v_col)
      using p_org, v_id;
  else
    perform vault.update_secret(v_id, p_value);
  end if;
  return v_id;
end;
$fn$;

create function public.wa_vault_get(p_org uuid, p_kind text)
returns text
language sql
security definer
stable
set search_path = public, vault
as $fn$
  select d.decrypted_secret
    from public.wa_accounts a
    join vault.decrypted_secrets d
      on d.id = case p_kind when 'token' then a.token_secret_id
                            when 'app_secret' then a.app_secret_id end
   where a.org_id = p_org;
$fn$;

revoke all on function public.wa_vault_put(uuid, text, text) from public, anon, authenticated;
revoke all on function public.wa_vault_get(uuid, text)       from public, anon, authenticated;
grant execute on function public.wa_vault_put(uuid, text, text) to service_role;
grant execute on function public.wa_vault_get(uuid, text)       to service_role;

-- ---------------------------------------------------------------- postflight
do $$
declare
  v_bad text;
begin
  -- 1. Vault wrappers: nobody but service_role (and the owner) may call them.
  select string_agg(p.oid::regprocedure::text || ' -> ' ||
                    coalesce(nullif(a.grantee, 0)::regrole::text, 'PUBLIC'), ', ')
    into v_bad
    from pg_proc p, aclexplode(p.proacl) a
   where p.oid in ('public.wa_vault_put(uuid,text,text)'::regprocedure,
                   'public.wa_vault_get(uuid,text)'::regprocedure)
     and a.privilege_type = 'EXECUTE'
     and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole));
  if v_bad is not null then
    raise exception 'vault wrappers callable by a client: %', v_bad;
  end if;
  if not has_function_privilege('service_role', 'public.wa_vault_get(uuid,text)', 'EXECUTE') then
    raise exception 'service_role cannot call wa_vault_get';
  end if;

  -- 2. RLS on all three new tables.
  if exists (select 1 from pg_class
              where oid in ('public.wa_template_library'::regclass,
                            'public.wa_accounts'::regclass,
                            'public.wa_templates'::regclass)
                and not relrowsecurity) then
    raise exception 'a new WhatsApp table has RLS off';
  end if;

  -- 3. The app can write exactly one thing: wa_templates.enabled.
  if has_table_privilege('authenticated', 'public.wa_accounts', 'INSERT')
     or has_table_privilege('authenticated', 'public.wa_accounts', 'UPDATE')
     or has_table_privilege('authenticated', 'public.wa_accounts', 'DELETE')
     or has_table_privilege('authenticated', 'public.wa_templates', 'INSERT')
     or has_table_privilege('authenticated', 'public.wa_templates', 'DELETE')
     or has_table_privilege('authenticated', 'public.wa_template_library', 'INSERT')
     or has_column_privilege('authenticated', 'public.wa_templates', 'status', 'UPDATE')
     or has_column_privilege('authenticated', 'public.wa_templates', 'name', 'UPDATE')
     or has_column_privilege('anon', 'public.wa_templates', 'enabled', 'UPDATE') then
    raise exception 'a client holds a write it must not have';
  end if;
  if not has_column_privilege('authenticated', 'public.wa_templates', 'enabled', 'UPDATE') then
    raise exception 'authenticated cannot toggle wa_templates.enabled';
  end if;
  if has_table_privilege('anon', 'public.wa_accounts', 'SELECT')
     or has_table_privilege('anon', 'public.wa_templates', 'SELECT') then
    raise exception 'anon can read WhatsApp tables';
  end if;

  -- 4. The library is complete and every body has as many {{n}} as params.
  if (select count(*) from public.wa_template_library) <> 8 then
    raise exception 'template library should hold 8 rows';
  end if;
  select string_agg(key, ', ') into v_bad
    from public.wa_template_library l
   where (select count(*) from regexp_matches(l.body, '\{\{\d+\}\}', 'g'))
         <> array_length(l.params, 1)
      or l.body ~ '^\{\{' or l.body ~ '\{\{\d+\}\}\s*$';
  if v_bad is not null then
    raise exception 'template bodies do not match their params, or start/end with a variable: %', v_bad;
  end if;

  -- 5. Still nothing in public without RLS.
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity) then
    raise exception 'a table in public has RLS off';
  end if;
end $$;

commit;
