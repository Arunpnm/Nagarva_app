-- ============================================================
-- Drop customer_surveys.items — the column that caused the
-- rooms-vs-items confusion, and has never held a single value.
--
-- 15 Sept 2026. Arun's decision, reversed the same day and correct in its
-- reversed form: ROOMS SURVIVES, ITEMS IS DROPPED.
--
-- ------------------------------------------------------------
-- WHY, counted rather than argued
-- ------------------------------------------------------------
-- customer_surveys holds 9 rows. Of the ten columns added by
-- 20260909_consolidate_survey_tables.sql, these are NULL on ALL NINE:
--
--     items            0 / 9 non-null
--     custom_items     0 / 9
--     photos           0 / 9
--     total_cft        0 / 9
--     suggested_vehicle 0 / 9
--
-- while `rooms` is NOT NULL and carries the line items on 5 rows (the
-- other 4 are pending surveys holding an empty array).
--
-- `items` was added for the item/CFT survey module that the 8 Sept
-- decision then cancelled. It has no writer in SQL, none in Dart, and
-- none on the public page. It exists only to be mistaken for the real
-- column — which is exactly what happened: it was read as the surviving
-- shape and `rooms` as the dead one, the precise inversion of the truth.
--
-- **Only `items` is dropped here.** The other four are the same class of
-- dead weight and are reported, not dropped, because `total_cft` is
-- SPOKEN FOR: CLAUDE.md commits `public_submit_survey_impl` to writing it
-- server-side when the catalogue spec lands, as its single writer.
-- Dropping it would delete a column with a scheduled purpose.
--
-- ------------------------------------------------------------
-- THE ROW THAT IS LOST. It is not converted, and it is not fine.
-- ------------------------------------------------------------
-- Survey 035758c7-49e3-4ef2-96a5-13ce010caabe — customer **Priya
-- Raghavan**, Arun Packers and Couriers, submitted 2 Sept 2026, linked to
-- a lead, zero quotations built on it. Its `rooms` holds the free-text
-- shape written by the now-dropped `submit_survey`:
--
--     [{"room": "Bedroom 1",
--       "items": "Queen bed, 2 almirahs, AC unit, 6 cartons"}]
--
-- **This migration does not touch that row, and does not convert it.**
-- Converting it would mean inventing a CFT figure for "2 almirahs" and an
-- item/sub classification nobody chose — a number the app supplies
-- wearing the vendor's authority, which is the one thing this project's
-- standing rule forbids. There is no honest conversion.
--
-- **And it is already invisible, today, with no error.** Verified by
-- reading `SurveyLine.tryParse` (survey_response_section.dart:40-52)
-- rather than trusting its doc comment: it requires a non-empty **`item`**
-- key. This element carries **`items`** — plural. So `parseSurveyRooms`
-- drops it, and the survey renders as ZERO line items. The vendor sees a
-- submitted survey with an empty list, which is precisely the failure
-- `SurveyResponseSection` was built to fix ("the items the customer had
-- gone to the trouble of listing were invisible in the app, so the
-- feature delivered nothing").
--
-- So: one real customer filled in a real survey and her mover cannot see
-- it. That is what "lost" means here. It is stated so it can be acted on
-- — re-ask Priya, or key the four lines in by hand against the
-- catalogue — rather than left to look like a converted row.
--
-- ------------------------------------------------------------
-- ORDERING against the other migrations in flight
-- ------------------------------------------------------------
-- Independent of both. This drops a column no function body names;
-- 20260915_drop_ungated_public_rpcs.sql and
-- 20260915_survey_rooms_shape_check.sql both concern `rooms` and the RPCs.
-- Run in any order relative to them.
--
-- **`rooms` is deliberately NOT renamed to `items` in this migration** —
-- see the report accompanying it. Short version: the rename's entire cost
-- is re-creating two SECURITY DEFINER functions that serve the LIVE
-- /survey page, and the catalogue spec has to rewrite one of them anyway.
-- Paying that risk twice, and running an interim where the RPC argument
-- is `p_rooms` and the column is `items`, buys nothing today. Dropping
-- `items` already removes the ambiguity that caused the confusion.
-- ============================================================

begin;

set local search_path = public, pg_catalog;

-- ------------------------------------------------------------
-- PREFLIGHT
-- ------------------------------------------------------------
-- Discriminating in both directions: the column's presence is true
-- before and false after, so this cannot pass in the applied state.
do $preflight$
declare
  v_has_items   boolean;
  v_items_rows  integer;
  v_rooms_rows  integer;
  v_total       integer;
begin
  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'customer_surveys'
       and column_name = 'items'
  ) into v_has_items;

  if not v_has_items then
    raise exception
      'PREFLIGHT: customer_surveys.items does not exist. Already applied, or '
      'the column was never there. Refusing rather than reporting a no-op as success.';
  end if;

  select count(*),
         count(*) filter (where items is not null),
         count(*) filter (where jsonb_array_length(rooms) > 0)
    into v_total, v_items_rows, v_rooms_rows
    from public.customer_surveys;

  -- The whole justification is that the column is empty. If that stopped
  -- being true, something started writing it and this drop would destroy
  -- real data — so refuse loudly rather than proceed on a stale premise.
  if v_items_rows <> 0 then
    raise exception
      'PREFLIGHT: customer_surveys.items is non-null on % of % rows. Something '
      'now WRITES this column, so dropping it would destroy data. Find the writer '
      'before running this.', v_items_rows, v_total;
  end if;

  if v_rooms_rows = 0 then
    raise exception
      'PREFLIGHT: no row has a non-empty rooms array. That contradicts the premise '
      'of this migration (rooms is the surviving, populated column). Refusing.';
  end if;

  raise notice
    'PREFLIGHT OK: % rows; items non-null on 0; rooms non-empty on %.',
    v_total, v_rooms_rows;
end
$preflight$;

-- ------------------------------------------------------------
-- THE DROP
-- ------------------------------------------------------------
-- No IF EXISTS: the preflight has already established it is there, and a
-- silent no-op is the failure mode this project keeps recording.
alter table public.customer_surveys drop column items;

-- ------------------------------------------------------------
-- POSTFLIGHT
-- ------------------------------------------------------------
-- Same transaction, so a failed assertion rolls the drop away.
do $postflight$
declare
  v_has_items  boolean;
  v_has_rooms  boolean;
  v_total      integer;
  v_rooms_rows integer;
  v_freetext   jsonb;
begin
  select exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='customer_surveys' and column_name='items'
  ) into v_has_items;
  if v_has_items then
    raise exception 'POSTFLIGHT: customer_surveys.items still exists.';
  end if;

  -- The half that matters: prove the DROP hit only what it was aimed at.
  -- A postflight that checks only the removal would pass just as well on a
  -- migration that had taken `rooms` with it.
  select exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='customer_surveys' and column_name='rooms'
  ) into v_has_rooms;
  if not v_has_rooms then
    raise exception 'POSTFLIGHT: customer_surveys.rooms is GONE. Rolling back.';
  end if;

  select count(*), count(*) filter (where jsonb_array_length(rooms) > 0)
    into v_total, v_rooms_rows
    from public.customer_surveys;
  if v_total <> 9 or v_rooms_rows <> 5 then
    raise exception
      'POSTFLIGHT: expected 9 rows with 5 carrying line items, got % / %. '
      'Either the data moved under this migration or the drop did damage.',
      v_total, v_rooms_rows;
  end if;

  -- Priya Raghavan's row must still be here, byte for byte. It is not
  -- convertible and it is not this migration's to touch.
  select rooms into v_freetext
    from public.customer_surveys
   where id = '035758c7-49e3-4ef2-96a5-13ce010caabe';

  if v_freetext is null or v_freetext -> 0 ->> 'room' is distinct from 'Bedroom 1' then
    raise exception
      'POSTFLIGHT: the free-text survey row (035758c7, Priya Raghavan) is missing or '
      'altered. It was to be left exactly as found. Rolling back.';
  end if;

  raise notice
    'POSTFLIGHT OK: items dropped; rooms intact on % of % rows; free-text row preserved '
    'unchanged and still UNREADABLE by parseSurveyRooms (see header).',
    v_rooms_rows, v_total;
end
$postflight$;

commit;
