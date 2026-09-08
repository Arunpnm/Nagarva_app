-- Two gaps on the customer-facing surface, found 8 Sept 2026.
--
-- Arun asked what happens to a customer's link when a vendor never pays
-- or lapses. Verified live: NONE of the seven `public_*` functions check
-- plan, trial or active status, and `surveys`/`document_signatures` carry
-- no write guard.
--
-- 1. A SUSPENDED vendor's customer-facing links keep serving. Suspension
--    (`organizations.active = false`) is a deliberate platform-admin act
--    for abuse, fraud or a legal problem — not the automatic end of a
--    trial. Continuing to serve that tenant's customer infrastructure is
--    continuing to operate them.
--
-- 2. A read-only (lapsed) vendor can still MINT new survey and signature
--    links, because those two tables were never given the
--    `enforce_org_writable` trigger the other nine got.
--
-- ==========================================================================
-- WHAT THIS DELIBERATELY DOES NOT DO
-- ==========================================================================
--
-- **It does not gate on plan_status or trial_ends_at. Ever.** A customer
-- is not party to the vendor's billing. Someone holding a money receipt
-- for money they actually paid must not lose it because their mover did
-- not renew — the same principle already in this product, where payments
-- stay recordable under lock and reads work forever by construction. The
-- lever for non-payment is CREATION, which already bites: a lapsed vendor
-- cannot create orders, quotes or leads, so the pipeline starves on its
-- own. Only `active` is read here.
--
-- **The customer is never told why.** The reason code is `unavailable`.
-- Telling a customer their mover is suspended would have the platform
-- defaming a vendor to their own customer, on the strength of an internal
-- flag. The pages render it as "This link isn't available — please
-- contact your moving company".
--
-- **Part 3 blocks INSERT only, and that is the whole point.** Both
-- customer submissions are UPDATEs on a row the vendor already created
-- (`public_submit_survey` updates `surveys`, `public_submit_signature`
-- updates `document_signatures` — checked, not assumed). So a BEFORE
-- INSERT guard stops a lapsed vendor MINTING a new link while leaving a
-- customer free to finish one already sent to them. Making it INSERT OR
-- UPDATE would strand a customer mid-signature over their mover's
-- invoice, which is the exact harm this file exists to avoid.
--
-- ==========================================================================
-- WHY WRAPPERS RATHER THAN EDITED BODIES
-- ==========================================================================
--
-- Each `public_*` function is rewritten as a thin gate that delegates to
-- the original, renamed `_impl`. No SECURITY DEFINER body is retyped, so
-- this migration cannot introduce a transcription error into
-- security-critical code that it has no way to test. It is also trivially
-- reversible (see the bottom of this file).
--
-- The `_impl` functions have their anon/authenticated EXECUTE revoked.
-- Grants FOLLOW a renamed function, so without that revoke the gate would
-- be bypassable by calling `public_get_survey_impl` directly — which is
-- the whole gate defeated by anyone who reads this file.

begin;

-- ==========================================================================
-- PREFLIGHT — raises, never skips
-- ==========================================================================
do $pre$
declare
  v_missing text;
begin
  -- Every function this migration wraps must exist with the exact
  -- signature used below, or the ALTERs fail halfway.
  select string_agg(sig, ', ') into v_missing
    from (values
      ('public.public_get_survey(text)'),
      ('public.public_get_signature_request(text)'),
      ('public.public_get_order_documents(text)'),
      ('public.public_submit_survey(text,jsonb,text)'),
      ('public.public_submit_signature(text,text,text)'),
      ('public.public_submit_review(text,integer,text)'),
      ('public.public_submit_complaint(text,text,text)')
    ) as t(sig)
   where to_regprocedure(sig) is null;

  if v_missing is not null then
    raise exception
      'PREFLIGHT: missing public function(s): %. Nothing was changed.', v_missing;
  end if;

  -- Re-running this would rename an already-wrapped function and produce
  -- an infinite delegation. Refuse rather than corrupt.
  if to_regprocedure('public.public_get_survey_impl(text)') is not null then
    raise exception
      'PREFLIGHT: public_get_survey_impl already exists - this migration has already run.';
  end if;

  -- The gate compares `active` directly. If the column ever becomes
  -- nullable, a NULL would read as "not false" and silently fail OPEN,
  -- which is the failure mode nobody notices.
  if (select is_nullable from information_schema.columns
       where table_schema='public' and table_name='organizations'
         and column_name='active') <> 'NO' then
    raise exception
      'PREFLIGHT: organizations.active is nullable - the suspension gate would fail open.';
  end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='enforce_org_writable') then
    raise exception
      'PREFLIGHT: enforce_org_writable() is missing. Run the Item 32b migration first.';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='surveys' and column_name='org_id')
     or not exists (select 1 from information_schema.columns
                     where table_schema='public' and table_name='document_signatures'
                       and column_name='org_id') then
    raise exception
      'PREFLIGHT: surveys/document_signatures need org_id for the write guard.';
  end if;
end
$pre$;

-- ==========================================================================
-- PART 1 — the two helpers
-- ==========================================================================

-- Which org owns this token?
--
-- The three token families live in three different tables, so this is the
-- one place that knows all of them. SECURITY DEFINER because the caller is
-- anon and every one of these tables is RLS-scoped.
--
-- Returns NULL for an unknown token, and the wrappers treat NULL as "let
-- the impl answer" — so a bad token still produces the impl's own
-- not_found/invalid reason rather than a misleading "unavailable".
create or replace function public.public_org_for_token(p_token text)
returns uuid
language sql
stable
security definer
set search_path to 'public'
as $function$
  select org_id from public.surveys             where token          = p_token
  union all
  select org_id from public.document_signatures where token          = p_token
  union all
  select org_id from public.orders              where tracking_token = p_token
  limit 1;
$function$;

-- Is this org's customer-facing surface still served?
--
-- `active` ONLY. Read the header before adding plan_status here.
create or replace function public.public_org_serviceable(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce((select active from public.organizations where id = p_org_id), true);
$function$;

revoke all on function public.public_org_for_token(text) from public, anon, authenticated;
revoke all on function public.public_org_serviceable(uuid) from public, anon, authenticated;

-- ==========================================================================
-- PART 2 — wrap the seven readers/submitters
-- ==========================================================================

alter function public.public_get_survey(text)                    rename to public_get_survey_impl;
alter function public.public_get_signature_request(text)         rename to public_get_signature_request_impl;
alter function public.public_get_order_documents(text)           rename to public_get_order_documents_impl;
alter function public.public_submit_survey(text,jsonb,text)      rename to public_submit_survey_impl;
alter function public.public_submit_signature(text,text,text)    rename to public_submit_signature_impl;
alter function public.public_submit_review(text,integer,text)    rename to public_submit_review_impl;
alter function public.public_submit_complaint(text,text,text)    rename to public_submit_complaint_impl;

-- Grants follow the rename. Without this the gate is bypassable.
revoke all on function public.public_get_survey_impl(text)                 from public, anon, authenticated;
revoke all on function public.public_get_signature_request_impl(text)      from public, anon, authenticated;
revoke all on function public.public_get_order_documents_impl(text)        from public, anon, authenticated;
revoke all on function public.public_submit_survey_impl(text,jsonb,text)   from public, anon, authenticated;
revoke all on function public.public_submit_signature_impl(text,text,text) from public, anon, authenticated;
revoke all on function public.public_submit_review_impl(text,integer,text) from public, anon, authenticated;
revoke all on function public.public_submit_complaint_impl(text,text,text) from public, anon, authenticated;

create or replace function public.public_get_survey(p_token text)
returns jsonb language plpgsql volatile security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_get_survey_impl(p_token);
end
$function$;

create or replace function public.public_get_signature_request(p_token text)
returns jsonb language plpgsql volatile security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_get_signature_request_impl(p_token);
end
$function$;

create or replace function public.public_get_order_documents(p_token text)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_get_order_documents_impl(p_token);
end
$function$;

create or replace function public.public_submit_survey(p_token text, p_rooms jsonb, p_instructions text)
returns jsonb language plpgsql volatile security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_submit_survey_impl(p_token, p_rooms, p_instructions);
end
$function$;

create or replace function public.public_submit_signature(p_token text, p_customer_name text, p_signature_data text)
returns jsonb language plpgsql volatile security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_submit_signature_impl(p_token, p_customer_name, p_signature_data);
end
$function$;

create or replace function public.public_submit_review(p_token text, p_rating integer, p_comment text)
returns jsonb language plpgsql volatile security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_submit_review_impl(p_token, p_rating, p_comment);
end
$function$;

create or replace function public.public_submit_complaint(p_token text, p_type text, p_description text)
returns jsonb language plpgsql volatile security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  v_org := public.public_org_for_token(p_token);
  if v_org is not null and not public.public_org_serviceable(v_org) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  return public.public_submit_complaint_impl(p_token, p_type, p_description);
end
$function$;

-- Restore exactly the grants the originals had (anon + authenticated +
-- service_role, verified live before writing this).
grant execute on function public.public_get_survey(text)                 to anon, authenticated, service_role;
grant execute on function public.public_get_signature_request(text)      to anon, authenticated, service_role;
grant execute on function public.public_get_order_documents(text)        to anon, authenticated, service_role;
grant execute on function public.public_submit_survey(text,jsonb,text)   to anon, authenticated, service_role;
grant execute on function public.public_submit_signature(text,text,text) to anon, authenticated, service_role;
grant execute on function public.public_submit_review(text,integer,text) to anon, authenticated, service_role;
grant execute on function public.public_submit_complaint(text,text,text) to anon, authenticated, service_role;

-- ==========================================================================
-- PART 3 — a lapsed vendor cannot mint new customer links
-- ==========================================================================
-- INSERT only. See the header: the customer's own submission is an UPDATE
-- and must keep working.

drop trigger if exists trg_org_writable on public.surveys;
create trigger trg_org_writable
  before insert on public.surveys
  for each row execute function public.enforce_org_writable();

drop trigger if exists trg_org_writable on public.document_signatures;
create trigger trg_org_writable
  before insert on public.document_signatures
  for each row execute function public.enforce_org_writable();

-- ==========================================================================
-- POSTFLIGHT — asserts the CONSTRUCT, and rolls back if it is not there
-- ==========================================================================
do $post$
declare
  v_bad text;
begin
  -- Every wrapper exists, is anon-callable, and actually consults the gate.
  select string_agg(name, ', ') into v_bad
    from (values
      ('public.public_get_survey(text)'),
      ('public.public_get_signature_request(text)'),
      ('public.public_get_order_documents(text)'),
      ('public.public_submit_survey(text,jsonb,text)'),
      ('public.public_submit_signature(text,text,text)'),
      ('public.public_submit_review(text,integer,text)'),
      ('public.public_submit_complaint(text,text,text)')
    ) as t(name)
   where to_regprocedure(name) is null
      or not has_function_privilege('anon', to_regprocedure(name), 'execute')
      or position('public_org_serviceable' in pg_get_functiondef(to_regprocedure(name)::oid)) = 0;

  if v_bad is not null then
    raise exception 'POSTFLIGHT: wrapper missing, not anon-callable, or not gated: %', v_bad;
  end if;

  -- The _impl functions must NOT be reachable by anon, or the gate is
  -- decorative.
  select string_agg(name, ', ') into v_bad
    from (values
      ('public.public_get_survey_impl(text)'),
      ('public.public_get_signature_request_impl(text)'),
      ('public.public_get_order_documents_impl(text)'),
      ('public.public_submit_survey_impl(text,jsonb,text)'),
      ('public.public_submit_signature_impl(text,text,text)'),
      ('public.public_submit_review_impl(text,integer,text)'),
      ('public.public_submit_complaint_impl(text,text,text)')
    ) as t(name)
   where has_function_privilege('anon', to_regprocedure(name), 'execute');

  if v_bad is not null then
    raise exception 'POSTFLIGHT: anon can still call the ungated impl: %', v_bad;
  end if;

  -- The gate must read `active` and must NOT have grown a plan check.
  if position('active' in pg_get_functiondef(
        to_regprocedure('public.public_org_serviceable(uuid)')::oid)) = 0 then
    raise exception 'POSTFLIGHT: public_org_serviceable does not read active.';
  end if;
  if pg_get_functiondef(to_regprocedure('public.public_org_serviceable(uuid)')::oid)
       ilike '%plan_status%' then
    raise exception
      'POSTFLIGHT: the gate reads plan_status. A customer must never be gated on billing.';
  end if;

  -- Both write guards exist, are enabled, and are INSERT-only.
  if (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
       where c.relname in ('surveys','document_signatures')
         and t.tgname = 'trg_org_writable'
         and not t.tgisinternal
         and t.tgenabled = 'O'
         and (t.tgtype & 4) = 4     -- BEFORE INSERT
         and (t.tgtype & 16) = 0    -- and NOT on UPDATE
      ) <> 2 then
    raise exception
      'POSTFLIGHT: the surveys/document_signatures write guards are missing, disabled, or not INSERT-only.';
  end if;
end
$post$;

commit;

-- ==========================================================================
-- ROLLBACK, if this ever needs undoing
-- ==========================================================================
-- begin;
--   drop trigger if exists trg_org_writable on public.surveys;
--   drop trigger if exists trg_org_writable on public.document_signatures;
--   drop function if exists public.public_get_survey(text);
--   drop function if exists public.public_get_signature_request(text);
--   drop function if exists public.public_get_order_documents(text);
--   drop function if exists public.public_submit_survey(text,jsonb,text);
--   drop function if exists public.public_submit_signature(text,text,text);
--   drop function if exists public.public_submit_review(text,integer,text);
--   drop function if exists public.public_submit_complaint(text,text,text);
--   alter function public.public_get_survey_impl(text)                 rename to public_get_survey;
--   alter function public.public_get_signature_request_impl(text)      rename to public_get_signature_request;
--   alter function public.public_get_order_documents_impl(text)        rename to public_get_order_documents;
--   alter function public.public_submit_survey_impl(text,jsonb,text)   rename to public_submit_survey;
--   alter function public.public_submit_signature_impl(text,text,text) rename to public_submit_signature;
--   alter function public.public_submit_review_impl(text,integer,text) rename to public_submit_review;
--   alter function public.public_submit_complaint_impl(text,text,text) rename to public_submit_complaint;
--   grant execute on function public.public_get_survey(text)                 to anon, authenticated, service_role;
--   grant execute on function public.public_get_signature_request(text)      to anon, authenticated, service_role;
--   grant execute on function public.public_get_order_documents(text)        to anon, authenticated, service_role;
--   grant execute on function public.public_submit_survey(text,jsonb,text)   to anon, authenticated, service_role;
--   grant execute on function public.public_submit_signature(text,text,text) to anon, authenticated, service_role;
--   grant execute on function public.public_submit_review(text,integer,text) to anon, authenticated, service_role;
--   grant execute on function public.public_submit_complaint(text,text,text) to anon, authenticated, service_role;
--   drop function if exists public.public_org_for_token(text);
--   drop function if exists public.public_org_serviceable(uuid);
-- commit;
