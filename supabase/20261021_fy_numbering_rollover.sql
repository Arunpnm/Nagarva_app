-- 20261021_fy_numbering_rollover.sql
--
-- DEADLINE: 1 April 2027 (CLAUDE.md, "financial-year numbering rollover").
-- Every number_series / lr_series row today is fy = '2026-27', and the
-- allocators RAISE when no row matches the requested fy. The app asks for
-- the current FY, so at 00:00 IST on 1 April 2027 every invoice, receipt,
-- proforma, voucher, LR, credit note … fails for every tenant at once.
--
-- roll_over_number_series(org, to_fy, dry_run) clones the org's ACTIVE
-- rows of the previous FY into to_fy. It derives everything from the
-- org's own configuration and invents nothing — the distinction from the
-- old allocation-time auto-insert that produced bare '0001' invoices.
--
-- TWO KINDS OF SERIES, and they must be treated differently:
--
--   * A prefix that carries the year ('BLR/2026-27/', APC's '2026/') gets
--     the year advanced ('BLR/2027-28/', '2027/') and restarts at 0.
--     Unique by construction; safe to create any time, including March.
--
--   * A prefix with NO year ('LR', 'BLR-LR', 'CLM-', 'PO-', 'STG-' …)
--     CANNOT restart at 0: lr_register, claims, purchase_orders, grn,
--     storage_jobs, payslips and contracts all carry a unique index on
--     (org_id, <number>), so next year's LR0001 would collide with this
--     year's and the save would fail. Those series CONTINUE the counter.
--     And they are only copied once the new FY has started (IST): copied
--     in March, the old row would keep issuing numbers after the copy and
--     the new row would start inside the range already used. From
--     1 April the app only asks for the new FY, so the copy is final.
--     Before that, dry run and the real call both report them as
--     'waits'.
--
-- Callable by owner / admin / manager (is_org_manager). SECURITY INVOKER,
-- so number_series' own RLS applies on top. Idempotent: an existing
-- to_fy row is reported as 'exists' and left alone.
--
-- Handed over unrun.

begin;

do $$
begin
  if to_regclass('public.number_series') is null or to_regclass('public.lr_series') is null then
    raise exception 'number_series / lr_series missing — wrong database?';
  end if;
  if to_regprocedure('public.is_org_manager(uuid)') is null then
    raise exception 'is_org_manager(uuid) is missing — run the Tier A RLS migration first.';
  end if;
  if to_regprocedure('public.roll_over_number_series(uuid,text,boolean)') is not null then
    raise exception 'roll_over_number_series already exists — this migration has already run.';
  end if;
end $$;

create function public.roll_over_number_series(
  p_org uuid,
  p_to_fy text,
  p_dry_run boolean default false
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_to_start   int;
  v_from_start int;
  v_from       text;
  v_started    boolean;
  r            record;
  v_prefix     text;
  v_yearless   boolean;
  v_exists     boolean;
  v_status     text;
  v_first      text;
  v_created    int := 0;
  v_out        jsonb := '[]'::jsonb;
begin
  if p_org is null then
    raise exception 'Choose a business first.' using errcode = 'P0001';
  end if;
  if p_to_fy is null or p_to_fy !~ '^\d{4}-\d{2}$' then
    raise exception 'Financial year must look like 2027-28.' using errcode = 'P0001';
  end if;
  v_to_start := left(p_to_fy, 4)::int;
  if right(p_to_fy, 2)::int <> (v_to_start + 1) % 100 then
    raise exception '% is not a financial year.', p_to_fy using errcode = 'P0001';
  end if;
  -- coalesce: a NULL from the helper must refuse, never fall through.
  if not coalesce(public.is_org_manager(p_org), false) then
    raise exception 'Only the owner or a manager can start a new year''s numbering.'
      using errcode = 'P0001';
  end if;

  v_from_start := v_to_start - 1;
  v_from := v_from_start || '-' || lpad(((v_from_start + 1) % 100)::text, 2, '0');
  v_started := (now() at time zone 'Asia/Kolkata')::date >= make_date(v_to_start, 4, 1);

  -- Document series (invoice, receipt, proforma, voucher, credit note …).
  for r in
    select * from number_series
     where org_id = p_org and fy = v_from and active
     order by doc_type, branch nulls first
  loop
    v_prefix := case
      when position(v_from in coalesce(r.prefix, '')) > 0
        then replace(r.prefix, v_from, p_to_fy)
      when coalesce(r.prefix, '') ~ ('\y' || v_from_start || '\y')
        then regexp_replace(r.prefix, '\y' || v_from_start || '\y', v_to_start::text)
      else null
    end;
    v_yearless := v_prefix is null;

    select exists (
      select 1 from number_series
       where org_id = p_org and doc_type = r.doc_type
         and coalesce(branch, '') = coalesce(r.branch, '')
         and fy = p_to_fy
    ) into v_exists;

    v_status := case
      when v_exists then 'exists'
      when v_yearless and not v_started then 'waits'
      else 'ready'
    end;

    v_first := coalesce(case when v_yearless then r.prefix else v_prefix end, '')
            || lpad((case when v_yearless then coalesce(r.last_number, 0) + 1 else 1 end)::text,
                    coalesce(r.padding, 4), '0')
            || coalesce(r.suffix, '');

    if not p_dry_run and v_status = 'ready' then
      begin
        insert into number_series
          (org_id, doc_type, branch, fy, prefix, suffix, padding, last_number, active)
        values
          (p_org, r.doc_type, r.branch, p_to_fy,
           case when v_yearless then r.prefix else v_prefix end,
           r.suffix, r.padding,
           case when v_yearless then coalesce(r.last_number, 0) else 0 end,
           true);
        v_created := v_created + 1;
        v_status := 'created';
      exception when unique_violation then
        v_status := 'exists';   -- another session got there first
      end;
    end if;

    v_out := v_out || jsonb_build_object(
      'kind', 'doc', 'doc_type', r.doc_type, 'branch', r.branch,
      'status', v_status, 'first', v_first, 'continues', v_yearless);
  end loop;

  -- LR series. Their prefixes carry no year, so they continue the counter.
  for r in
    select * from lr_series
     where org_id = p_org and fy = v_from and active
     order by branch nulls first
  loop
    select exists (
      select 1 from lr_series
       where org_id = p_org and coalesce(branch, '') = coalesce(r.branch, '')
         and fy = p_to_fy
    ) into v_exists;

    v_status := case
      when v_exists then 'exists'
      when not v_started then 'waits'
      else 'ready'
    end;
    v_first := coalesce(r.prefix, 'LR') || lpad((coalesce(r.last_number, 0) + 1)::text, 4, '0');

    if not p_dry_run and v_status = 'ready' then
      begin
        insert into lr_series (org_id, branch, fy, prefix, last_number, active)
        values (p_org, r.branch, p_to_fy, r.prefix, coalesce(r.last_number, 0), true);
        v_created := v_created + 1;
        v_status := 'created';
      exception when unique_violation then
        v_status := 'exists';
      end;
    end if;

    v_out := v_out || jsonb_build_object(
      'kind', 'lr', 'doc_type', 'lr', 'branch', r.branch,
      'status', v_status, 'first', v_first, 'continues', true);
  end loop;

  return jsonb_build_object(
    'from', v_from, 'to', p_to_fy, 'dry_run', p_dry_run,
    'year_started', v_started, 'created', v_created, 'series', v_out);
end;
$fn$;

revoke all on function public.roll_over_number_series(uuid, text, boolean) from public, anon;
grant execute on function public.roll_over_number_series(uuid, text, boolean) to authenticated;

-- Postflight. Behaviour, as a real manager, with nothing written.
do $$
declare
  v_uid   uuid;
  v_org   uuid;
  v_res   jsonb;
  v_rows  int;
  v_before_ns int;
  v_before_lr int;
  v_e     jsonb;
  v_denied boolean := false;
  v_next  text;
  v_start int;
begin
  -- ACL, read with aclexplode (grantee 0 is PUBLIC).
  if exists (
    select 1 from pg_proc p, aclexplode(p.proacl) a
     where p.oid = 'public.roll_over_number_series(uuid,text,boolean)'::regprocedure
       and a.privilege_type = 'EXECUTE'
       and (a.grantee = 0 or a.grantee = 'anon'::regrole)
  ) then
    raise exception 'PUBLIC or anon can execute roll_over_number_series';
  end if;
  if (select prosecdef from pg_proc
       where oid = 'public.roll_over_number_series(uuid,text,boolean)'::regprocedure) then
    raise exception 'roll_over_number_series must be SECURITY INVOKER';
  end if;

  -- A probe that finds nobody tests nothing: refuse instead.
  select m.user_id, m.org_id into v_uid, v_org
    from org_members m
   where exists (select 1 from number_series s
                  where s.org_id = m.org_id and s.fy is not null and s.active)
   limit 1;
  if v_uid is null then
    raise exception 'No org member with an FY number series to probe with.';
  end if;

  -- The next FY after the newest one this org has.
  select max(fy) into v_next from number_series where org_id = v_org and fy is not null;
  v_start := left(v_next, 4)::int + 1;
  v_next := v_start || '-' || lpad(((v_start + 1) % 100)::text, 2, '0');

  select count(*) into v_before_ns from number_series where org_id = v_org;
  select count(*) into v_before_lr from lr_series where org_id = v_org;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res := public.roll_over_number_series(v_org, v_next, true);
  reset role;

  select count(*) into v_rows from jsonb_array_elements(v_res -> 'series');
  if v_rows <> (select count(*) from number_series
                 where org_id = v_org and active
                   and fy = (v_res ->> 'from'))
              + (select count(*) from lr_series
                 where org_id = v_org and active
                   and fy = (v_res ->> 'from')) then
    raise exception 'dry run listed % series, expected every active % row', v_rows, v_res ->> 'from';
  end if;
  for v_e in select * from jsonb_array_elements(v_res -> 'series') loop
    if coalesce(v_e ->> 'first', '') = '' then
      raise exception 'dry run produced an empty first number: %', v_e;
    end if;
    -- A yearless series must not be offered before the year starts.
    if (v_e ->> 'continues')::boolean
       and not (v_res ->> 'year_started')::boolean
       and v_e ->> 'status' = 'ready' then
      raise exception 'yearless series offered before the year started: %', v_e;
    end if;
  end loop;
  if (select count(*) from number_series where org_id = v_org) <> v_before_ns
     or (select count(*) from lr_series where org_id = v_org) <> v_before_lr then
    raise exception 'dry run wrote rows';
  end if;

  -- And it must refuse a caller who is not a manager of the org.
  perform set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-000000000000',
                      'role', 'authenticated')::text, true);
  set local role authenticated;
  -- Only THE refusal counts: any other error (a bug in the function)
  -- would otherwise pass this check without testing the guard.
  begin
    perform public.roll_over_number_series(v_org, v_next, true);
  exception when others then
    v_denied := sqlerrm like 'Only the owner or a manager%';
  end;
  reset role;
  if not v_denied then
    raise exception 'a non-member was not refused by the manager guard';
  end if;
end $$;

commit;
