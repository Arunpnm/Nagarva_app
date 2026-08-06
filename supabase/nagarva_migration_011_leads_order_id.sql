-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 011 — leads.order_id
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001-010
--
-- Session 4, Part A5 (Confirm Order / Skip Survey): the brief asks the
-- confirm-order flow to "link lead.order_id" once the order is created.
-- No such column exists anywhere in migrations 001-010 (grepped) — leads
-- only ever gets a status flip to 'confirmed' today, with no back-pointer
-- to the order that resulted from it.
--
-- The app code (lead_detail_page_widget.dart's _createOrderFromLead)
-- already attempts this write in a try/catch that swallows failure, same
-- pattern as _writeQuoteSnapshot in the same file — so nothing breaks
-- while this migration is unrun, and the write starts landing with no
-- code change once it is.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

alter table leads add column if not exists order_id text
  references orders(id) on delete set null;

create index if not exists leads_order_id_idx on leads (order_id)
  where order_id is not null;

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select id, customer, status, order_id
-- from leads
-- where status = 'confirmed'
-- order by created_at desc
-- limit 20;
