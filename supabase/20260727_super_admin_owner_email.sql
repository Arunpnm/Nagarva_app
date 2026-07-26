-- ============================================================================
-- 20260727_super_admin_owner_email.sql
-- Super-admin console, Step 2 (tenant detail view): owner email.
--
-- NOT YET RUN — paste into the Supabase SQL editor when convenient.
-- Idempotent — safe to re-run.
--
-- Why this needs an RPC instead of a direct query: the owner's email lives
-- in auth.users, which PostgREST does not expose to the public/authenticated
-- roles by default (only the `public` schema is exposed) — org_members has
-- no email column of its own. This function bridges the two schemas inside
-- a single security-definer call, gated on is_platform_admin() so a normal
-- vendor/staff session (which is still `authenticated`, just not a platform
-- admin) can't call it to enumerate other tenants' owner emails. Granted to
-- `authenticated`, not `anon` — this is admin console data, not public.
-- ============================================================================

create or replace function public.get_org_owner_email(p_org_id uuid)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not is_platform_admin() then
    raise exception 'not authorized';
  end if;

  return (
    select u.email
    from public.org_members m
    join auth.users u on u.id = m.user_id
    where m.org_id = p_org_id and m.role = 'owner'
    order by m.created_at
    limit 1
  );
end;
$$;

revoke all on function public.get_org_owner_email(uuid) from public;
grant execute on function public.get_org_owner_email(uuid) to authenticated;

-- ============================================================================
-- POST-RUN VERIFICATION:
--   select get_org_owner_email('<a real org id>'::uuid);
-- run as the platform-admin-seeded owner account (via the app, or by
-- setting role to that user in the SQL editor) - should return a real
-- email. Run as any other authenticated user - should raise "not authorized".
-- ============================================================================
