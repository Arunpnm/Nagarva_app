-- ============================================================
-- 20261112_push_notifications.sql  (12 Nov 2026)
--
-- Phone push notifications (Firebase Cloud Messaging), so an alert
-- (quote accepted, advance paid, new lead, job assigned ...) reaches the
-- phone with sound even when the app is closed. Arun, 12 Nov 2026.
--
-- How it works:
--   1. The app registers each phone's push address (FCM token) through
--      register_push_token(), tied to the logged-in person.
--   2. Every new row in `notifications` (the bell's table, already
--      written by existing triggers) fires notify_push(), which asks the
--      `push-send` Edge Function to deliver it. pg_net sends that request
--      AFTER the insert commits, so a slow or failed push can never block
--      or roll back the thing that created the alert.
--   3. push-send claims the row once (notifications.pushed_at) and sends
--      to the right phones: the named staff member, or, for alerts with
--      no staff recipient, the company's owners. The request carries only
--      the notification id, so nobody can send their own text through it,
--      and a repeated call cannot push the same alert twice.
--
-- Needs, BEFORE running: nothing. AFTER running: deploy push-send
--   npx supabase functions deploy push-send --no-verify-jwt --project-ref hqqcapifefsaqvotqvlt
-- and the Supabase secret FCM_SERVICE_ACCOUNT (Firebase service account
-- JSON). Until push-send is deployed, notify_push's requests simply fail
-- in the background; the bell keeps working exactly as before.
-- ============================================================

begin;

-- ---------- preflight ------------------------------------------------
do $pre$
begin
  if to_regclass('public.notification_tokens') is null
     or to_regclass('public.notifications') is null then
    raise exception 'notification_tokens / notifications are missing. This project expects both.';
  end if;
  if not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise exception 'pg_net is not available on this database. Enable it under Database -> Extensions first.';
  end if;
end $pre$;

create extension if not exists pg_net with schema extensions;

-- ---------- tokens belong to a person -------------------------------
alter table public.notification_tokens
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

-- One row per phone token; a phone that changes hands (owner, then a
-- staff PIN login on the same device) moves its row to the new person.
create unique index if not exists notification_tokens_token_uniq
  on public.notification_tokens (token);

-- Each person sees only their own phones. Writes go through the
-- functions below, never straight from the app.
drop policy if exists org_isolation on public.notification_tokens;
drop policy if exists notification_tokens_own on public.notification_tokens;
create policy notification_tokens_own on public.notification_tokens
  for select using (user_id = auth.uid());
revoke insert, update, delete on public.notification_tokens from anon, authenticated;

alter table public.notifications
  add column if not exists pushed_at timestamptz;

-- ---------- register / unregister -----------------------------------
create or replace function public.register_push_token(
  p_org_id      uuid,
  p_token       text,
  p_platform    text default 'android',
  p_device_name text default null,
  p_app_version text default null
) returns text
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid   uuid := auth.uid();
  v_staff uuid;
begin
  if v_uid is null then
    raise exception 'Please log in again.';
  end if;
  if p_token is null or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'register_push_token: not a push token';
  end if;
  if not exists (select 1 from org_members
                  where user_id = v_uid and org_id = p_org_id) then
    raise exception 'register_push_token: not a member of this company';
  end if;
  select id into v_staff from staff
   where auth_user_id = v_uid and org_id = p_org_id
   limit 1;

  insert into notification_tokens
    (org_id, staff_id, user_id, token, platform, device_name, app_version,
     active, last_used_at)
  values
    (p_org_id, v_staff, v_uid, p_token, left(coalesce(p_platform, 'android'), 20),
     left(p_device_name, 100), left(p_app_version, 40), true, now())
  on conflict (token) do update
     set org_id       = excluded.org_id,
         staff_id     = excluded.staff_id,
         user_id      = excluded.user_id,
         platform     = excluded.platform,
         device_name  = coalesce(excluded.device_name, notification_tokens.device_name),
         app_version  = coalesce(excluded.app_version, notification_tokens.app_version),
         active       = true,
         last_used_at = now();
  return 'ok';
end $$;

create or replace function public.unregister_push_token(p_token text)
returns text
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  update notification_tokens
     set active = false
   where token = p_token
     and user_id = auth.uid();
  return 'ok';
end $$;

revoke all on function public.register_push_token(uuid, text, text, text, text) from public, anon;
revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.register_push_token(uuid, text, text, text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ---------- every new alert asks push-send to deliver it ------------
create or replace function public.notify_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
begin
  begin
    perform net.http_post(
      url     := 'https://hqqcapifefsaqvotqvlt.supabase.co/functions/v1/push-send',
      body    := jsonb_build_object('id', new.id),
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 5000
    );
  exception when others then
    -- A push is a courtesy. Never let it stop the alert being saved.
    raise warning 'notify_push: %', sqlerrm;
  end;
  return new;
end $$;

revoke all on function public.notify_push() from public, anon, authenticated;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push
  after insert on public.notifications
  for each row execute function public.notify_push();

-- ---------- postflight ------------------------------------------------
do $post$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise exception 'postflight: pg_net is not installed';
  end if;
  -- notify_push calls it with named arguments; check those names exist.
  if not exists (select 1 from pg_proc p
                  where p.pronamespace = 'net'::regnamespace
                    and p.proname = 'http_post'
                    and p.proargnames @> array['url', 'body', 'headers', 'timeout_milliseconds']) then
    raise exception 'postflight: net.http_post(url, body, headers, timeout_milliseconds) not found';
  end if;
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.notifications'::regclass
                    and tgname = 'notifications_push' and tgenabled = 'O') then
    raise exception 'postflight: notifications_push trigger missing or disabled';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'notification_tokens'
                    and column_name = 'user_id')
     or not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'notifications'
                    and column_name = 'pushed_at') then
    raise exception 'postflight: new columns missing';
  end if;
  if not exists (select 1 from pg_index ix join pg_class i on i.oid = ix.indexrelid
                  where ix.indrelid = 'public.notification_tokens'::regclass
                    and ix.indisunique and i.relname = 'notification_tokens_token_uniq') then
    raise exception 'postflight: token unique index missing';
  end if;
  if has_table_privilege('authenticated', 'public.notification_tokens', 'insert')
     or has_table_privilege('authenticated', 'public.notification_tokens', 'update')
     or exists (select 1 from pg_policy where polrelid = 'public.notification_tokens'::regclass
                 and polname = 'org_isolation') then
    raise exception 'postflight: notification_tokens is still writable from the app';
  end if;
  if has_function_privilege('anon', 'public.register_push_token(uuid,text,text,text,text)', 'execute') then
    raise exception 'postflight: register_push_token is callable without login';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.notification_tokens'::regclass) then
    raise exception 'postflight: RLS is off on notification_tokens';
  end if;
end $post$;

commit;
