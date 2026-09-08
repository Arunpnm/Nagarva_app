-- Four tables each carry two indexes over the same key. Drop the
-- redundant one in each pair.
--
-- Arun, 8 Sept 2026, after scanning every index in the schema: this is a
-- standing habit, not fallout from the aborted 42803 run. That
-- transaction wrapper held and nothing partial survived — three of these
-- four pairs predate the order-allocator migration entirely.
--
--   document_signatures   sign_token_idx        + sign_token_key
--   pricing_config        idx_..._org_id        + ..._org_id_key
--   surveys               surveys_token_idx     + surveys_token_key
--   number_series         number_series_key_uniq + number_series_uniq
--
-- A redundant index is not free: every INSERT and UPDATE maintains both,
-- and both occupy cache. Nothing reads the second one that could not read
-- the first.
--
-- ==========================================================================
-- WHICH MEMBER SURVIVES, AND WHY IT DIFFERS BY PAIR
-- ==========================================================================
--
-- Three pairs are `plain index + unique CONSTRAINT`. The constraint-backed
-- index survives, and it must: `DROP INDEX` against a constraint-backed
-- index fails outright ("cannot drop index ... because constraint ...
-- requires it"), and dropping the constraint instead would remove a
-- uniqueness guarantee this is not authorised to touch. A btree unique
-- index over the same column serves every lookup the plain one served, so
-- nothing is lost.
--
-- The fourth pair, `number_series`, is two STANDALONE unique indexes over
-- an identical expression, neither constraint-backed. `number_series_uniq`
-- survives, per Arun — it is the original, created alongside the table in
-- `nagarva_migration_006_compliance.sql:292`.
--
-- ==========================================================================
-- A CORRECTION THIS FILE EXISTS BECAUSE OF
-- ==========================================================================
--
-- `number_series_key_uniq` is mine, added by
-- `20260908_next_order_id_allocator.sql` to close what was described as a
-- missing unique constraint on the series key — "a live invoice exposure
-- today". **That exposure was never real.** The uniqueness has existed
-- since migration 006, expressed as a standalone
-- `CREATE UNIQUE INDEX ... (org_id, doc_type, coalesce(branch,''),
-- coalesce(fy,''))` — byte-identical to the one I added.
--
-- The reasoning error is worth naming because it will recur: I checked
-- `pg_constraint`, found only the PK, the prefix CHECK and the branch FK,
-- and concluded no uniqueness existed. **A unique index created with
-- `CREATE UNIQUE INDEX` rather than `ALTER TABLE ... ADD CONSTRAINT` does
-- not appear in `pg_constraint` at all.** It lives only in `pg_index`.
-- Asking the constraint catalogue whether a table is protected answers a
-- narrower question than it appears to.
--
-- The order allocator's own preflight is corrected in the same commit to
-- ASSERT the index exists rather than create a second one, so a replay
-- cannot recreate both.
--
-- ==========================================================================
-- SEQUENCING
-- ==========================================================================
--
-- `surveys` is due to be renamed. A rename carries indexes across
-- unchanged, so cleaning this pair now means one index moves to the new
-- name instead of two.

begin;

-- ==========================================================================
-- PREFLIGHT — raises per pair, never skips
-- ==========================================================================
-- Deliberately NOT `DROP INDEX IF EXISTS`. If a pair is not in the state
-- described above, that is a fact worth stopping on: either the schema
-- moved underneath this file, or it has already run. Skipping quietly
-- would hand back a clean result for a script that did nothing.
do $pre$
declare
  r            record;
  v_keep_def   text;
  v_drop_def   text;
  v_keep_uniq  boolean;
  v_drop_con   text;
begin
  for r in
    select * from (values
      ('document_signatures', 'document_signatures_sign_token_key', 'document_signatures_sign_token_idx'),
      ('pricing_config',      'pricing_config_org_id_key',          'idx_pricing_config_org_id'),
      ('surveys',             'surveys_token_key',                  'surveys_token_idx'),
      ('number_series',       'number_series_uniq',                 'number_series_key_uniq')
    ) as t(tbl, keep_idx, drop_idx)
  loop
    -- Both members must exist. Absence is a stop, not a skip.
    if to_regclass('public.' || r.keep_idx) is null then
      raise exception
        'PREFLIGHT: %.% (the index to KEEP) does not exist. The schema is not in the state this migration was written against.',
        r.tbl, r.keep_idx;
    end if;
    if to_regclass('public.' || r.drop_idx) is null then
      raise exception
        'PREFLIGHT: %.% (the index to DROP) does not exist. Either this migration has already run, or the pair was cleaned by hand.',
        r.tbl, r.drop_idx;
    end if;

    -- Same key, compared after normalising OUT the index name and the
    -- UNIQUE keyword. Three of these pairs are plain-vs-unique, so their
    -- raw pg_get_indexdef text differs by more than the name — comparing
    -- the DDL verbatim would fail on every pair except number_series and
    -- prove nothing about the thing that matters, which is whether the
    -- two cover the same columns/expressions.
    select regexp_replace(pg_get_indexdef(i.oid),
                          '^CREATE (UNIQUE )?INDEX \S+ ON ', ''),
           ix.indisunique
      into v_keep_def, v_keep_uniq
      from pg_class i join pg_index ix on ix.indexrelid = i.oid
     where i.oid = ('public.' || r.keep_idx)::regclass;

    select regexp_replace(pg_get_indexdef(i.oid),
                          '^CREATE (UNIQUE )?INDEX \S+ ON ', '')
      into v_drop_def
      from pg_class i where i.oid = ('public.' || r.drop_idx)::regclass;

    if v_keep_def is distinct from v_drop_def then
      raise exception
        'PREFLIGHT: %/% do not cover the same key. KEEP=[%] DROP=[%]. Dropping would lose an index, not a duplicate.',
        r.keep_idx, r.drop_idx, v_keep_def, v_drop_def;
    end if;

    -- The survivor must be UNIQUE, or dropping the other could remove a
    -- uniqueness guarantee. (True in all four pairs today; asserted so a
    -- future edit cannot quietly invert which one survives.)
    if not v_keep_uniq then
      raise exception
        'PREFLIGHT: % is not unique, so it cannot stand in for %.',
        r.keep_idx, r.drop_idx;
    end if;

    -- THE ONE THAT WOULD FAIL MID-RUN. A constraint-backed index cannot
    -- be dropped directly — Postgres raises "cannot drop index ...
    -- because constraint ... requires it". Surface it here, naming the
    -- constraint, rather than aborting halfway through the drops.
    select con.conname into v_drop_con
      from pg_constraint con
     where con.conindid = ('public.' || r.drop_idx)::regclass;

    if v_drop_con is not null then
      raise exception
        'PREFLIGHT: % is backed by constraint %. DROP INDEX cannot remove it, and dropping the constraint is not in this migration''s scope.',
        r.drop_idx, v_drop_con;
    end if;
  end loop;
end
$pre$;

-- ==========================================================================
-- DROP — explicit, no IF EXISTS
-- ==========================================================================
drop index public.document_signatures_sign_token_idx;
drop index public.idx_pricing_config_org_id;
drop index public.surveys_token_idx;
drop index public.number_series_key_uniq;

-- ==========================================================================
-- POSTFLIGHT — assertions, inside the transaction
-- ==========================================================================
do $post$
declare
  r record;
begin
  for r in
    select * from (values
      ('document_signatures', 'document_signatures_sign_token_key', 'document_signatures_sign_token_idx'),
      ('pricing_config',      'pricing_config_org_id_key',          'idx_pricing_config_org_id'),
      ('surveys',             'surveys_token_key',                  'surveys_token_idx'),
      ('number_series',       'number_series_uniq',                 'number_series_key_uniq')
    ) as t(tbl, keep_idx, drop_idx)
  loop
    if to_regclass('public.' || r.drop_idx) is not null then
      raise exception 'POSTFLIGHT: % still exists.', r.drop_idx;
    end if;

    -- The survivor is the whole point. Losing it while dropping its
    -- duplicate would remove the guarantee rather than the redundancy.
    if to_regclass('public.' || r.keep_idx) is null then
      raise exception 'POSTFLIGHT: % is gone. The wrong index was dropped.', r.keep_idx;
    end if;

    if not (select ix.indisunique from pg_index ix
             where ix.indexrelid = ('public.' || r.keep_idx)::regclass) then
      raise exception 'POSTFLIGHT: % is no longer unique.', r.keep_idx;
    end if;
  end loop;

  -- The series key specifically: uniqueness must still be enforced over
  -- the coalesce expression the allocators rely on. This is the property
  -- next_doc_number and next_order_id depend on, asserted by shape rather
  -- than by index name so a later rename cannot silently pass.
  if not exists (
    select 1 from pg_index ix join pg_class i on i.oid = ix.indexrelid
     where ix.indrelid = 'public.number_series'::regclass
       and ix.indisunique
       and pg_get_indexdef(i.oid) like '%COALESCE(branch%'
       and pg_get_indexdef(i.oid) like '%COALESCE(fy%')
  then
    raise exception
      'POSTFLIGHT: number_series no longer has a unique index over (org_id, doc_type, coalesce(branch), coalesce(fy)). The allocators depend on it.';
  end if;
end
$post$;

commit;

-- ==========================================================================
-- ROLLBACK
-- ==========================================================================
-- Recreates each dropped index exactly as it was. Note none of these is
-- needed for correctness — they were redundant when dropped — so this is
-- for restoring the schema to its prior shape, not for restoring a
-- guarantee.
-- begin;
--   create index document_signatures_sign_token_idx
--     on public.document_signatures using btree (sign_token);
--   create index idx_pricing_config_org_id
--     on public.pricing_config using btree (org_id);
--   create index surveys_token_idx
--     on public.surveys using btree (token);
--   create unique index number_series_key_uniq
--     on public.number_series using btree
--     (org_id, doc_type, coalesce(branch, ''::text), coalesce(fy, ''::text));
-- commit;
