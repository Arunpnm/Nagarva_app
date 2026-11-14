-- ============================================================
-- 20261114_customer_alerts.sql  (14 Nov 2026)
--
-- Found in the live browser test on 14 Nov 2026: two things a customer
-- does on a link reached nobody in the vendor app.
--   1. Sending the moving list (survey) the FIRST time. Only a re-send
--      ("Survey updated") made a notification.
--   2. Signing a quote or any other document. The open lead page updates
--      live, but nobody is told unless they happen to be looking at it.
--
-- Both now make a notification for the company (every staff member who
-- sees the bell), the same way the payment report and complaint do.
-- Triggers, so every way a survey is sent or a document signed is
-- covered, now and later.
--
-- Run once in the Supabase SQL editor. Nothing is deleted. A failure to
-- write the notification never blocks the customer's send or signature.
-- ============================================================

begin;

-- 1. Moving list received --------------------------------------------------
create or replace function public.notify_survey_received()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_name  text := coalesce(nullif(btrim(coalesce(new.customer_name, '')), ''), 'The customer');
  v_items int;
begin
  begin
    -- rooms is a flat list: [{cat, item, sub, qty, cft}, ...]
    select coalesce(sum(coalesce((i->>'qty')::int, 1)), 0)
      into v_items
      from jsonb_array_elements(case when jsonb_typeof(new.rooms) = 'array' then new.rooms else '[]'::jsonb end) i;
  exception when others then
    v_items := null;
  end;
  begin
    insert into public.notifications (org_id, recipient_staff_id, type, title, body, ref_lead_id)
    values (new.org_id, null, 'survey_received', 'Moving list received',
            v_name || ' sent their moving list'
              || case when coalesce(v_items, 0) > 0 then ' (' || v_items || ' items)' else '' end
              || '. Check it and send the quote.',
            new.lead_id::text);
  exception when others then null;
  end;
  return new;
end $$;

drop trigger if exists customer_surveys_notify_received on public.customer_surveys;
create trigger customer_surveys_notify_received
  after update of status on public.customer_surveys
  for each row
  when (new.status = 'submitted' and old.status is distinct from 'submitted')
  execute function public.notify_survey_received();

-- 2. Document signed -------------------------------------------------------
create or replace function public.notify_document_signed()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_name  text := coalesce(nullif(btrim(coalesce(new.customer_name, '')), ''), 'The customer');
  v_lead  text;
  v_no    text;
  v_doc   text;
  v_type  text;
  v_title text;
  v_body  text;
begin
  begin
    if new.document_type = 'quote' then
      select q.lead_id::text, q.quote_no into v_lead, v_no
        from public.quotations q
       where q.id::text = split_part(new.document_id, '#', 1);
      v_type  := 'quote_signed';
      v_title := 'Quote signed';
      v_body  := v_name || ' signed quotation ' || coalesce(v_no, '')
                 || '. The order is booked; collect the advance.';
    else
      v_doc := case new.document_type
                 when 'invoice'  then 'invoice'
                 when 'pod'      then 'delivery note'
                 when 'delivery' then 'delivery note'
                 else replace(coalesce(new.document_type, 'document'), '_', ' ')
               end;
      select o.lead_id::text into v_lead
        from public.orders o
       where o.id = coalesce(new.order_id, new.document_id);
      v_type  := 'document_signed';
      v_title := 'Customer signed';
      v_body  := v_name || ' signed the ' || v_doc
                 || coalesce(' for order ' || new.order_id, '') || '.';
    end if;

    insert into public.notifications (org_id, recipient_staff_id, type, title, body, ref_lead_id)
    values (new.org_id, null, v_type, v_title, v_body, v_lead);
  exception when others then null;
  end;
  return new;
end $$;

drop trigger if exists document_signatures_notify_signed on public.document_signatures;
create trigger document_signatures_notify_signed
  after update of status on public.document_signatures
  for each row
  when (new.status = 'signed' and old.status is distinct from 'signed')
  execute function public.notify_document_signed();

revoke all on function public.notify_survey_received() from public, anon, authenticated;
revoke all on function public.notify_document_signed() from public, anon, authenticated;

commit;
