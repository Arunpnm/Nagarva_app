-- BUG-025 (full test, 1 Nov 2026): most actions were never recorded in
-- the Activity log — only quotations and app_settings had the audit
-- trigger, and the app logs a handful of actions itself.
--
-- The existing public.audit_row() (field-level diff, actor = auth.uid(),
-- skips no-op updates) is attached to the business tables below.
-- number_series is left out on purpose: every issued document number
-- would add a row of noise.
--
-- One change to audit_row(): PIN columns (pin, pin_hash) are stripped
-- before logging, so a staff/owner PIN hash never lands in audit_log.
--
-- NOT APPLIED — Arun runs this.

begin;

create or replace function public.audit_row()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_old       jsonb;
  v_new       jsonb;
  v_entity_id text;
  v_org       uuid;
  v_action    text;
  v_changed   text[];
  v_actor     uuid;
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new) - 'pin' - 'pin_hash';
    v_action := 'row_insert';
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old) - 'pin' - 'pin_hash';
    v_new := to_jsonb(new) - 'pin' - 'pin_hash';
    v_action := 'row_update';
    -- No-op update (or a PIN-only change, already stripped): nothing to log.
    if v_old = v_new then
      return null;
    end if;
  else
    v_old := to_jsonb(old) - 'pin' - 'pin_hash';
    v_action := 'row_delete';
  end if;

  v_entity_id := coalesce(v_new ->> 'id', v_old ->> 'id');
  if v_entity_id is null then
    raise exception
      'audit_row: %.% has no id value; audit_log.entity_id is NOT NULL.',
      tg_table_schema, tg_table_name;
  end if;

  begin
    v_org := coalesce(v_new ->> 'org_id', v_old ->> 'org_id')::uuid;
  exception when others then
    v_org := null;
  end;

  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into v_changed
      from (
        select coalesce(n.key, o.key) as k
          from jsonb_each(v_new) n
          full outer join jsonb_each(v_old) o on o.key = n.key
         where n.value is distinct from o.value
      ) d;
  end if;

  begin
    v_actor := auth.uid();
  exception when others then
    v_actor := null;
  end;

  insert into public.audit_log (
    org_id, entity_type, entity_id, action, actor,
    actor_name, actor_role, old_value, new_value, changed_fields
  ) values (
    v_org, tg_table_name, v_entity_id, v_action, v_actor,
    null, null, v_old, v_new, v_changed
  );

  return null;
end;
$function$;

do $attach$
declare
  t text;
begin
  foreach t in array array[
    'orders', 'leads', 'customers', 'payment_entries', 'expenses',
    'addons', 'credit_notes', 'lr_register', 'pod_records', 'complaints',
    'staff', 'staff_advances', 'staff_incentives', 'salary_payments',
    'job_expense_floats', 'vehicles', 'trips', 'trip_expenses',
    'vendors', 'vendor_bills', 'vendor_payments',
    'rate_cards', 'rate_card_rules', 'branches'
  ]
  loop
    execute format('drop trigger if exists trg_audit_%1$s on public.%1$I', t);
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete '
      'on public.%1$I for each row execute function public.audit_row()', t);
  end loop;
end
$attach$;

commit;

-- Check: select tgname from pg_trigger where tgname like 'trg_audit_%'
--   → 26 rows (24 new + quotations + app_settings).
