-- Row count of every table in the public schema, one "table<TAB>count" line
-- each, sorted. Used by .github/workflows/db-backup.yml on the live database
-- (before and after the dump) and on the restored copy, so the same question
-- is asked of both. count(*), not pg_stat estimates (CLAUDE.md: statistics
-- are not an audit).
select c.relname,
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from public.%I', c.relname),
                           false, true, '')))[1]::text::bigint
  from pg_class c
 where c.relnamespace = 'public'::regnamespace
   and c.relkind in ('r', 'p')
   and not c.relispartition
 order by 1;
