-- ============================================================
-- supabase/20260817_signature_link_hardening.sql
--
-- Two independent fixes to the "original" (service_role-only) signature
-- RPC pair, found during the 17 Aug 2026 link.nagarva.in incident
-- review — unrelated to that incident's own fix, safe to run regardless
-- of how the /survey /sign recovery resolves.
--
-- 1. EXPIRY WAS NEVER ENFORCED. Neither get_signature_request nor
--    submit_signature checked document_signatures.expires_at, and
--    neither did sign-document/index.ts (the only caller — this pair is
--    granted to service_role only). Every signature link ever sent was
--    (and until this migration runs, still is) usable forever. Fixed in
--    the RPCs themselves, not the Edge Function, so it holds regardless
--    of caller. Live exposure checked 17 Aug 2026: 2 of 2 currently
--    'pending' document_signatures rows are already past expires_at.
--
-- 2. get_signature_request returned `to_jsonb(row) - a_couple_columns`
--    — a deny-list, so every column ever added to orders/quotations in
--    the future is customer-visible by default. Replaced with an
--    explicit allow-list built by reading exactly what
--    lib/sign_page/sign_page_widget.dart's _documentCard() renders (that
--    page is dead code w.r.t. link.nagarva.in as of this same incident,
--    but its rendering logic is still the real spec for "what a signer
--    needs to see"). Confirmed removed: quotations.margin_pct,
--    orders.porter_commission_pct (the two fields Arun specifically
--    asked about), plus discount_amount/discount_pct/list_amount,
--    notes/supervisor_notes/damage_report/hold_reason_note, all
--    billing_party_*/eway/irn fields, and every internal id/timestamp/
--    workflow-state column. Full picked-field list is in chat, not
--    duplicated here — re-derive from _documentCard() if this comment
--    goes stale.
--
--    One behavior CHANGE, not just a removal: orders never had a plain
--    `items` column (only `quote_items`), so the old deny-list payload
--    put it under the key `quote_items` — which _documentCard() never
--    reads (it only ever looks for `items`), so every order-type
--    signature request has silently shown NO item count since this
--    flow was built. The allow-list aliases `quote_items` to `items` in
--    the order branch, fixing that as a side effect. Also added `amount`
--    (orders only, quotations has no such column) alongside `total` so
--    _documentCard()'s existing `asNum('total') ?? asNum('amount')`
--    fallback keeps working for a directly-booked order with no
--    itemized quote — same fallback convention already used elsewhere
--    in this app (order_pnl_section.dart etc.).
--
-- Also reconciles the two signature-size caps Arun flagged:
-- public_submit_signature allowed 1.5MB, sign-document/index.ts caps at
-- 512KB. Standardized on 512KB (524288 bytes) — public_submit_signature
-- changed to match; sign-document's own cap is untouched (already
-- correct).
--
-- No signature/return-shape change on get_signature_request or
-- submit_signature (same columns, same argument list) — CREATE OR
-- REPLACE is safe here per this project's own convention; no DROP
-- needed.
--
-- Does NOT touch: public_get_signature_request/public_submit_signature's
-- own expiry/allow-list logic (already correct, see the RPC-family
-- comparison given 17 Aug 2026), or anything on link.nagarva.in.
-- ============================================================

create or replace function public.get_signature_request(p_token text)
 returns table(signature_id uuid, doc_type text, doc_id text, sig_status text, sig_customer_name text, sig_signed_at timestamp with time zone, org_name text, payload jsonb)
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  return query
  select ds.id,
         ds.document_type,
         ds.document_id,
         ds.status,
         ds.customer_name,
         ds.signed_at,
         o.name,
         case ds.document_type
           when 'quote' then (
             select jsonb_build_object(
               'id',           q.id,
               'customer',     q.customer,
               'from_address', q.from_address,
               'from_city',    q.from_city,
               'to_address',   q.to_address,
               'to_city',      q.to_city,
               'items',        q.items,
               'subtotal',     q.subtotal,
               'gst_pct',      q.gst_pct,
               'gst_amount',   q.gst_amount,
               'total',        q.total
             )
             from public.quotations q
             where q.id = ds.document_id and q.org_id = ds.org_id
               and q.deleted_at is null
           )
           else (
             select jsonb_build_object(
               'id',           ord.id,
               'customer',     ord.customer,
               'from_address', ord.from_address,
               'from_city',    ord.from_city,
               'to_address',   ord.to_address,
               'to_city',      ord.to_city,
               'items',        ord.quote_items,
               'subtotal',     ord.quote_subtotal,
               'gst_pct',      ord.quote_gst_pct,
               'gst_amount',   ord.quote_gst_amount,
               'total',        ord.quote_total,
               'amount',       ord.amount
             )
             from public.orders ord
             where ord.id = ds.document_id and ord.org_id = ds.org_id
               and ord.deleted_at is null
           )
         end
  from public.document_signatures ds
  join public.organizations o on o.id = ds.org_id
  where ds.sign_token = p_token
    and (ds.expires_at is null or ds.expires_at > now())
  limit 1;
end;
$function$;

create or replace function public.submit_signature(p_token text, p_signature_data text, p_customer_name text, p_signer_ip text)
 returns table(ok boolean, message text)
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_row public.document_signatures%rowtype;
  v_id uuid;
begin
  select * into v_row
  from public.document_signatures
  where sign_token = p_token;

  if not found then
    return query select false, 'Invalid or expired link'::text;
    return;
  end if;

  -- Already signed: succeed idempotently rather than erroring, so a
  -- double-tap or a refresh on the customer's phone doesn't look broken.
  -- Unchanged from before this migration.
  if v_row.status = 'signed' then
    return query select true, 'Already signed'::text;
    return;
  end if;

  if v_row.expires_at is not null and v_row.expires_at < now() then
    return query select false, 'This link has expired'::text;
    return;
  end if;

  if p_signature_data is null or length(trim(p_signature_data)) = 0 then
    return query select false, 'Signature is required'::text;
    return;
  end if;

  -- ~512KB ceiling on the base64 canvas image — matches
  -- sign-document/index.ts's MAX_SIGNATURE_BYTES (the Edge Function that
  -- actually fronts this RPC); the two were out of sync at 512KB vs
  -- public_submit_signature's separate 1.5MB cap, not this function,
  -- which had none at all before this migration.
  if length(p_signature_data) > 524288 then
    return query select false, 'Signature image too large'::text;
    return;
  end if;

  update public.document_signatures
     set signature_data = p_signature_data,
         customer_name  = coalesce(nullif(trim(p_customer_name), ''),
                                   customer_name),
         signer_ip      = p_signer_ip,
         signed_at      = now(),
         status         = 'signed'
   where sign_token = p_token
     and status = 'pending'
     and (expires_at is null or expires_at > now())
  returning id into v_id;

  if v_id is null then
    -- The pre-checks above already ruled out not-found/already-signed/
    -- expired, but re-check rather than assume why the UPDATE matched
    -- nothing — a genuinely concurrent submit that committed between
    -- the SELECT above and this UPDATE should report "Already signed",
    -- not "expired".
    select * into v_row from public.document_signatures where sign_token = p_token;
    if v_row.status = 'signed' then
      return query select true, 'Already signed'::text;
    else
      return query select false, 'This link has expired'::text;
    end if;
    return;
  end if;

  return query select true, 'Signed'::text;
end;
$function$;

-- public_submit_signature: reconcile its own cap to the same 512KB.
create or replace function public.public_submit_signature(p_token text, p_customer_name text, p_signature_data text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  if p_signature_data is null or length(p_signature_data) < 100 then
    return jsonb_build_object('ok', false, 'reason', 'bad_payload');
  end if;

  -- 512KB ceiling — was 1.5MB, reconciled to match sign-document's own
  -- MAX_SIGNATURE_BYTES and submit_signature's new cap above.
  if length(p_signature_data) > 524288 then
    return jsonb_build_object('ok', false, 'reason', 'too_large');
  end if;

  update public.document_signatures
     set signature_data = p_signature_data,
         customer_name  = coalesce(nullif(left(p_customer_name, 120), ''), customer_name),
         signed_at      = now(),
         status         = 'signed'
   where sign_token = p_token
     and signed_at  is null
     and status     = 'pending'
     and expires_at > now()
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_signable');
  end if;

  return jsonb_build_object('ok', true, 'signature_id', v_id);
end;
$function$;

-- Verify after running:
--   select count(*) from document_signatures
--     where status = 'pending' and expires_at < now();  -- was 2, should
--     still show 2 (they're still 'pending' rows — this migration stops
--     NEW get/submit calls from succeeding on them, it doesn't touch
--     existing rows) but a get_signature_request/submit_signature call
--     against either token should now fail.
