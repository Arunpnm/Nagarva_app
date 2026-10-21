-- 20261021_expenses_payment_mode.sql
--
-- Adds expenses.payment_mode so the Cash book can tell cash spent from
-- money paid by UPI, bank or card. Until now an expense recorded WHAT and
-- HOW MUCH, never HOW it was paid, so "cash out" could not be shown at
-- all — counting every expense as cash would overstate it.
--
-- Nullable on purpose, and NOT backfilled: the existing rows never
-- recorded a mode, and stamping them 'cash' would be inventing a fact.
-- They stay null and the Cash book leaves them out.
--
-- After this runs and the column is confirmed by query, flip
-- kExpensePaymentModeLive in lib/config/app_config.dart so Quick Expense
-- starts asking "Paid by". Flipping it first breaks every expense save.
--
-- Handed over unrun. Run in the SQL editor as one statement batch.

begin;

-- Preflight: refuse rather than skip.
do $$
begin
  if to_regclass('public.expenses') is null then
    raise exception 'public.expenses does not exist — wrong database?';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'expenses'
                and column_name = 'payment_mode') then
    raise exception 'expenses.payment_mode already exists — this migration has already run.';
  end if;
end $$;

alter table public.expenses
  add column payment_mode text;

alter table public.expenses
  add constraint expenses_payment_mode_check
  check (payment_mode is null or payment_mode in ('cash', 'upi', 'bank', 'card'));

-- Postflight: assert the construct, inside the transaction, so a miss
-- rolls the whole thing back.
do $$
declare
  v_nullable text;
  v_generated text;
  v_def text;
begin
  select is_nullable, is_generated into v_nullable, v_generated
    from information_schema.columns
   where table_schema = 'public' and table_name = 'expenses'
     and column_name = 'payment_mode';
  if v_nullable is distinct from 'YES' then
    raise exception 'payment_mode missing or not nullable (is_nullable=%)', v_nullable;
  end if;
  if v_generated is distinct from 'NEVER' then
    raise exception 'payment_mode is generated (%), cannot be written', v_generated;
  end if;

  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conrelid = 'public.expenses'::regclass
     and conname = 'expenses_payment_mode_check';
  if v_def is null or v_def !~ 'cash' or v_def !~ 'card' then
    raise exception 'expenses_payment_mode_check missing or wrong: %', v_def;
  end if;

  -- RLS must still be on; adding a column cannot turn it off, but the
  -- check costs nothing and the lint convention asks for it.
  if not (select relrowsecurity from pg_class where oid = 'public.expenses'::regclass) then
    raise exception 'RLS is off on public.expenses';
  end if;
end $$;

commit;
