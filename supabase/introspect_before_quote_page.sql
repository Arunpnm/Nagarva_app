-- ============================================================================
-- introspect_before_quote_page.sql — READ-ONLY. Nothing here writes.
--
-- Two jobs, both blocking work I will not do from guesswork:
--
--   PART A verifies the 29 Jul order-snapshot migration actually landed the
--          way the app now assumes. That migration's SQL was written from
--          the generated Dart mirror, not from live introspection, and the
--          app on main already reads those columns.
--
--   PART B dumps the `quotations` schema so the /quote public RPC can be
--          written against what is really there. The handoff brief says
--          this schema was not available last session — so it is not being
--          reconstructed from the Dart mirror, which is hand-maintained
--          and has been wrong before.
--
-- Paste the whole file into the Supabase SQL editor and send me the output.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- PART A — did the order snapshot migration land correctly?
-- ---------------------------------------------------------------------------

-- A1. The 11 snapshot columns and their REAL types.
--     Expect exactly 11 rows. A missing row means the migration did not run.
--     A row with an unexpected type is the dangerous case: the migration used
--     `add column if not exists`, which SILENTLY SKIPS a column that already
--     existed under a different type — and the app then writes the wrong
--     shape into it with no error.
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'orders'
   and column_name like 'quote\_%'
 order by column_name;
-- Expected:
--   quote_charges       jsonb
--   quote_gst_amount    numeric
--   quote_gst_mode      text
--   quote_gst_pct       numeric
--   quote_items         jsonb
--   quote_packing_type  text
--   quote_snapshot_at   timestamp with time zone
--   quote_subtotal      numeric
--   quote_total         numeric
--   quote_total_cft     numeric
--   quote_version       integer

-- A2. The CHECK constraint that stops 'auto' ever being stored as a GST mode.
select conname, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.orders'::regclass
   and conname = 'orders_quote_gst_mode_check';
-- Expect 1 row: CHECK (quote_gst_mode IS NULL OR quote_gst_mode IN
--   ('inter','intra'))

-- A3. Has anything actually been snapshotted yet, and does it look sane?
--     On a DB where no conversion has run since the migration this is
--     legitimately 0 — that is not a failure.
select count(*)                                   as orders_total,
       count(*) filter (where quote_snapshot_at is not null) as with_snapshot,
       count(*) filter (where quote_gst_mode is not null
                          and quote_gst_mode not in ('inter','intra'))
                                                   as bad_gst_mode,
       count(*) filter (where quote_snapshot_at is not null
                          and quotation_id is null) as snapshot_without_link
  from public.orders;
-- bad_gst_mode and snapshot_without_link must both be 0.


-- ---------------------------------------------------------------------------
-- PART B — the `quotations` schema, for the /quote public RPC
-- ---------------------------------------------------------------------------

-- B1. Full column list with types, nullability and defaults.
--     I need this to decide exactly which fields the customer-facing RPC
--     returns. Note the project rule: NO PRICING on public customer pages,
--     so this is as much about what to EXCLUDE as what to include.
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'quotations'
 order by ordinal_position;

-- B2. Constraints and indexes — specifically whether `token` is unique and
--     indexed, since the RPC looks up by it on every customer page load.
select i.relname as index_name,
       am.amname as method,
       idx.indisunique as is_unique,
       pg_get_indexdef(idx.indexrelid) as definition
  from pg_index idx
  join pg_class i on i.oid = idx.indexrelid
  join pg_class t on t.oid = idx.indrelid
  join pg_am am on am.oid = i.relam
 where t.relname = 'quotations' and t.relnamespace = 'public'::regnamespace
 order by i.relname;

-- B3. THE TOKEN DEFAULT BUG. The brief records that
--     `encode(gen_random_bytes(24),'hex')` does not come back populated on
--     insert for `quotations`, while the identical default on `surveys`
--     works — so the app generates the token client-side as a workaround
--     (_generateHexToken). This compares the two defaults side by side,
--     which is the first thing that would explain it.
select table_name, column_name, column_default, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and column_name = 'token'
   and table_name in ('quotations', 'surveys')
 order by table_name;

-- B4. How many existing quotations actually have a token. If the
--     client-side workaround is the only thing populating it, rows created
--     by any other path will be null — and those can never be shared.
select count(*)                                        as quotations_total,
       count(token)                                    as with_token,
       count(*) filter (where token is null)           as missing_token,
       count(distinct token)                           as distinct_tokens
  from public.quotations;
-- distinct_tokens should equal with_token. If it does not, tokens are
-- colliding and that is a security problem, not a cosmetic one.

-- B5. Does `quotations` already have expiry / soft-delete columns? The
--     /quote RPC needs to respect both, and I do not want to add a column
--     that is already there under a different name.
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'quotations'
   and column_name in ('expires_at','used_at','deleted_at','deleted_by',
                       'delete_reason','status','accepted_at',
                       'accepted_by_name','version','parent_quote_id')
 order by column_name;

-- B6. What `status` values are actually in use, so the RPC validates
--     against reality rather than against an assumed vocabulary. This is
--     the same check that caught the leads 'converted' vs 'confirmed'
--     split.
select status, count(*)
  from public.quotations
 group by status
 order by 2 desc;


-- ---------------------------------------------------------------------------
-- PART C — confirm the public RPCs from this session are as described
-- ---------------------------------------------------------------------------

-- C1. The 4 public RPCs, their exact signatures, and who can execute them.
--     `public_*` must be granted to anon; resolve_survey_cats must NOT be.
select p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef                               as security_definer,
       coalesce(array_to_string(p.proacl, ' | '), '(default: PUBLIC)') as acl
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('public_get_survey','public_submit_survey',
                     'public_get_signature_request','public_submit_signature',
                     'resolve_survey_cats')
 order by p.proname;

-- C2. CLOSED — and the check below was WRONG as originally written.
--
-- It expected zero anon grants on these tables. That expectation was
-- incorrect: Supabase bootstraps every project with
--   GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated
-- so those grants are present on every table from day one and were not
-- introduced by any migration here. Finding them is the default state,
-- not a leak.
--
-- Grants are irrelevant while RLS holds, and RLS was verified directly
-- (29 Jul):
--   surveys, quotations, document_signatures, pricing_config,
--   customer_surveys — RLS enabled, 1 policy each, all {authenticated},
--   `org_id in (select current_org_ids()) or is_platform_admin()`.
--   No policy admits anon.
--   app_defaults — RLS enabled, 0 policies, by design; only SECURITY
--   DEFINER functions read it.
--   rls_forced false everywhere, which is standard Supabase and only
--   affects the owner role.
-- Net: anon reads zero rows from all six.
--
-- Do NOT revoke these grants. It gains nothing real and risks the PIN
-- login flow.
--
-- The query below is kept only as the RLS check that should have been
-- written in the first place — policies are what actually gate anon, so
-- that is what to inspect.
select c.relname            as table_name,
       c.relrowsecurity     as rls_enabled,
       c.relforcerowsecurity as rls_forced,
       count(p.polname)     as policy_count,
       coalesce(string_agg(distinct r.rolname, ','), '(none)') as policy_roles
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_policy p on p.polrelid = c.oid
  left join lateral unnest(p.polroles) pr(oid) on true
  left join pg_roles r on r.oid = pr.oid
 where n.nspname = 'public'
   and c.relname in ('surveys','quotations','document_signatures',
                     'pricing_config','app_defaults','customer_surveys')
 group by c.relname, c.relrowsecurity, c.relforcerowsecurity
 order by c.relname;
-- rls_enabled must be true on all six. policy_roles must never contain
-- 'anon'. app_defaults legitimately has policy_count 0.
