-- CORRECTIONS.md A4 / "No suggested money. Ever." — document settings
-- ---------------------------------------------------------------------
-- seed_org_document_settings() gave EVERY new org three things nobody at
-- that org chose:
--   * demurrage_free_days = 5 and demurrage_rate_per_day = 500, printed
--     on every Lorry Receipt as "Demurrage ... @ Rs.500 per day";
--   * quotation_terms carrying "80% advance" and "Interest @24% per
--     annum if payment is not made within 15 days" — commercial terms
--     printed on page 3 of every quotation.
-- These are APC's own figures. Counted 21 Oct 2026: all 5 orgs carry the
-- 5/500 rows, including two that are not APC (arnpnm and the QA org).
--
-- This migration:
--   1. re-creates the seeder WITHOUT those three keys (wording-only keys
--      stay: footer, goods description, invoice note, LR notice, and the
--      demurrage SENTENCE template, which prints nothing until the vendor
--      sets both figures — see DocumentBoilerplate.demurrageSentence);
--   2. deletes those three keys for NON-APC orgs only, and only where the
--      value is still exactly the seeded one (a vendor who edited it keeps
--      their edit). APC's three orgs keep theirs: they are APC's own terms.
--
-- After it, an unset demurrage prints no sentence on the LR, and a
-- quotation with no quotation_terms prints the standard operational terms
-- (quote_pdf.dart falls back already).
--
-- Run once in the SQL editor. One transaction; any failed assertion rolls
-- the whole thing back.

begin;

do $$
begin
  if to_regprocedure('public.seed_org_document_settings(uuid)') is null then
    raise exception 'seed_org_document_settings(uuid) not found — nothing to fix';
  end if;
end $$;

create or replace function public.seed_org_document_settings(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.app_settings (org_id, category, key, value)
  values
    (p_org_id, 'documents', 'doc_footer_text',
      to_jsonb('This is a computer-generated document. SAVE PAPER - SAVE TREES | BE DIGITAL - GO GREEN'::text)),
    (p_org_id, 'documents', 'goods_description_default',
      to_jsonb('Old and Used Household Goods For Personal Usage Only, Not For Sale'::text)),
    (p_org_id, 'documents', 'invoice_note',
      to_jsonb('Please keep your Cash/Jewellery and all important documents in your Custody/Lock. Carrying Liquor, Gas Cylinder, Acid of any type of Liquids (like Ghee Tin, Oil etc.) is totally prohibited.'::text)),
    (p_org_id, 'documents', 'lr_notice_text',
      to_jsonb('The consignment by the lorry receipt shall be stored at the destination under the control of the transport operator and shall be delivered to the order of the consignee whose name is mentioned in the lorry receipt. It will under no circumstances be delivered to anyone without written authorization from the consignee on its order.'::text)),
    (p_org_id, 'documents', 'demurrage_text',
      to_jsonb('Demurrage charge after more than {days} day(s) @ Rs.{rate} per day + handling & local transportation charges.'::text))
  on conflict (org_id, category, key) do nothing;
end;
$function$;

delete from public.app_settings a
 using public.organizations o
 where o.id = a.org_id
   and a.category = 'documents'
   and o.slug not in ('arun-packers-and-couriers', 'apc-bengaluru', 'apc-coimbatore')
   and (
        (a.key = 'demurrage_free_days'    and a.value = to_jsonb(5))
     or (a.key = 'demurrage_rate_per_day' and a.value = to_jsonb(500))
     or (a.key = 'quotation_terms'        and a.value::text like '%80\% advance%')
   );

do $$
declare
  v_body text;
  v_left int;
  v_apc  int;
begin
  -- Comments stripped: a tombstone must not satisfy or fail this check.
  select string_agg(l, E'\n') into v_body
    from regexp_split_to_table(
           pg_get_functiondef('public.seed_org_document_settings(uuid)'::regprocedure),
           E'\n') l
   where l !~ '^\s*--';
  if v_body ~ '\ydemurrage_free_days\y'
     or v_body ~ '\ydemurrage_rate_per_day\y'
     or v_body ~ '\yquotation_terms\y' then
    raise exception 'seeder still seeds a money key';
  end if;
  if v_body !~ '\ydemurrage_text\y' then
    raise exception 'seeder lost the demurrage_text wording key';
  end if;

  select count(*) into v_left
    from public.app_settings a join public.organizations o on o.id = a.org_id
   where o.slug not in ('arun-packers-and-couriers', 'apc-bengaluru', 'apc-coimbatore')
     and ((a.key = 'demurrage_free_days'    and a.value = to_jsonb(5))
       or (a.key = 'demurrage_rate_per_day' and a.value = to_jsonb(500)));
  if v_left <> 0 then
    raise exception 'seeded demurrage figures remain on % non-APC rows', v_left;
  end if;

  -- The opposite direction: APC's own rows must survive.
  select count(*) into v_apc
    from public.app_settings a join public.organizations o on o.id = a.org_id
   where o.slug in ('arun-packers-and-couriers', 'apc-bengaluru', 'apc-coimbatore')
     and a.key in ('demurrage_free_days', 'demurrage_rate_per_day');
  if v_apc = 0 then
    raise exception 'APC demurrage rows were deleted — refusing';
  end if;

  raise notice 'ok: seeder clean, non-APC seeded money removed, APC rows kept (%)', v_apc;
end $$;

commit;
