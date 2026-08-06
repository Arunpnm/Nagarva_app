-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 012 — auto-create lead on first inbound WhatsApp message
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001-011
--
-- Session 4, Part B3 (WA Inbox): "Auto-create lead on first inbound;
-- unparseable media records '[unsupported]'."
--
-- No client code can implement this — nothing in the app ever receives an
-- inbound WhatsApp message; that would need a webhook receiver / Edge
-- Function ingesting AiSensy's webhook and inserting into `wa_messages`,
-- which does not exist yet (CLAUDE.md's Phase 4 rule: AiSensy only ever
-- called from an Edge Function, none built for either direction so far).
-- This is the correct place for the auto-lead-creation rule regardless —
-- symmetrical with apply_stock_movement() on stock_movements (migration
-- 005), a trigger driving derived state off the one table that's actually
-- written to. Inert until something starts inserting inbound rows; ready
-- the moment it does.
--
-- Behaviour: on the FIRST inbound message for a contact with no lead_id
-- yet, creates a `leads` row (customer name from wa_contacts.display_name
-- falling back to the phone number, source 'whatsapp', notes exactly
-- matching the format Part A's own auto-creation-note UI expects:
-- 'Auto-created from WhatsApp reply. First message: "<text>"' — using
-- '[unsupported]' verbatim for msg_type='unsupported') and links
-- wa_contacts.lead_id to it. Every later inbound message on an
-- already-linked contact is a no-op here.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function wa_auto_create_lead() returns trigger as $$
declare
  v_contact wa_contacts%rowtype;
  v_new_lead_id uuid;
  v_first_text text;
begin
  if new.direction <> 'in' then
    return new;
  end if;

  select * into v_contact from wa_contacts where id = new.contact_id;
  if not found or v_contact.lead_id is not null then
    return new;
  end if;

  v_first_text := case
    when new.msg_type = 'unsupported' then '[unsupported]'
    else coalesce(new.body, '[unsupported]')
  end;

  insert into leads (org_id, customer, phone, source, status, notes)
  values (
    v_contact.org_id,
    coalesce(v_contact.display_name, v_contact.phone),
    v_contact.phone,
    'whatsapp',
    'new',
    format('Auto-created from WhatsApp reply. First message: "%s"', v_first_text)
  )
  returning id into v_new_lead_id;

  update wa_contacts set lead_id = v_new_lead_id where id = v_contact.id;

  return new;
end;
$$ language plpgsql;

drop trigger if exists wa_messages_auto_lead on wa_messages;
create trigger wa_messages_auto_lead
  after insert on wa_messages
  for each row execute function wa_auto_create_lead();

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- -- Simulate one inbound message for an existing contact with no lead yet:
-- insert into wa_messages (org_id, contact_id, direction, msg_type, body)
-- select org_id, id, 'in', 'text', 'Hi, I need a quote for moving to Pune'
-- from wa_contacts where lead_id is null limit 1;
--
-- -- Confirm a lead was created and linked:
-- select c.id, c.phone, c.lead_id, l.customer, l.source, l.notes
-- from wa_contacts c
-- join leads l on l.id = c.lead_id
-- order by l.created_at desc
-- limit 5;
