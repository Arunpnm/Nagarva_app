# COMPETITOR_UX_SPEC.md — Sales Engagement Layer (place in project root)

## Context
A competitor app (packers & movers field-sales tool) was analyzed from 10 screens.
Their strength is field-sales UX; they show no accounting, payroll, GST, porter,
or multi-tenant depth. Nagarva adopts their best UX patterns, refined, on top of
its ERP foundation. Simplicity rule for everything below: primary actions are
one tap, forms are bottom sheets not pages, and every list card carries its own
quick-action row.

## Feature 1 — One-Tap Outcome Logging (highest priority)
After calling a lead/customer, a bottom sheet appears (triggered from the card's
Call action after dial, or manually):
- Header: contact name + status chip + phone + timestamp
- Free-text "notes" field with mic (speech-to-text) + "Set Reminder" shortcut
- Big outcome buttons (color-coded):
  Leads: [Interested — Send Quote] [Call Back] [Lost Lead] [No Answer / Busy]
  CRM contacts: [Interested — Create Lead] [Just Inquiry — Set Reminder]
                [Not Interested / Wrong Number]
- Each tap: updates lead.status, appends to call/outcome history, auto-creates
  a reminder where implied (Call Back → tomorrow default), closes sheet.
- Refinement over competitor: after [Interested — Send Quote], deep-link straight
  into the quotation flow pre-filled with the lead.

## Feature 2 — Follow-up Hub
Dedicated page with two tabs: Sales (Leads) and Ops (Orders).
Card = name, status chip, date + phone, RECENT ACTIVITY (last outcome + last
call), highlighted REMINDER pill (datetime + note), LATEST NOTE, and a
quick-action row: [Call] [WhatsApp] [Add Note] [Set Reminder].
Sort: overdue reminders first, then today, then upcoming.
Refinement: swipe right = done/log outcome; badge count on nav icon;
no duplicate cards (competitor bug); empty states with guidance.

## Feature 3 — WhatsApp Template Hub (plan-gated)
Settings-area page:
- Provider selector: (a) Direct WhatsApp (Personal) — free, opens wa.me deep
  link with prefilled message, zero setup; (b) Meta Business API / AiSensy —
  official background sending (existing AiSensy integration path).
- Plan gating: Direct = all plans incl. Trial; API = Pro (read from
  subscription_plans.features jsonb, e.g. "whatsapp": true).
- Template list grouped by category (Sales / Ops / Payments), each with an
  enable toggle and edit sheet.
- Edit sheet: body text with variable tags inserted by tap:
  {{customer_name}} {{vendor_name}} {{amount}} {{order_no}} {{survey_link}}
  {{quote_link}} {{invoice_link}} {{driver_name}} {{vehicle_no}} {{eta}}
- Seed templates (per org, editable): New Lead Welcome, Self-Survey Link,
  Rough Estimate, Follow-up (Pending Survey), Follow-up (Quote Sent),
  Send Official Quote, Advance Payment Nudge, Truck & Driver Info,
  Payment Receipt, Job Completed Thank You.
- Storage: new table wa_templates(id, org_id, code, category, body, enabled,
  updated_at). Rendering replaces variables from the lead/order context.
- Every [WhatsApp] quick action across the app uses the enabled template for
  its context via the selected provider.

## Feature 4 — Operations Command Calendar
CalendarPage becomes the ops command center:
- Month / Week / Day toggle
- Overlay filter chips: Orders, Transit, Follow-ups, Reminders (multi-select)
- Month cells show colored dots per event type; tapping a day opens that day's
  event list (order cards with time + status chip)
- Bottom summary chips: Moves / Leads / Alerts counts for visible range
- Data: orders(move_date), vehicle_trips(trip_date), reminders(due_date),
  leads follow-ups.

## Feature 5 — Lead list upgrades
- Pipeline chips with live counts: All / New / Follow-up / Quoted / Converted /
  Lost (tap = filter)
- Service-type filter row (Residential / Part Load / Vehicle / Office...)
- Each card: avatar initial, name, lead #, date, service tag, status chip, and
  quick-action row [View] [Call] [WhatsApp] [F-Up] [Quote]
- Search by name/mobile; no "No Date" noise (hide empty fields)

## Feature 6 — CRM Hub (customer database, lower priority)
Searchable customer directory with bulk CSV import (Name, Mobile, Email;
10-digit validation), per-contact: call, Send Survey Link, Full Lead conversion,
and the CRM outcome sheet from Feature 1.

## Build order (fits existing stage plan)
These slot in as the "Sales Engagement" stage AFTER tenant safety (Stage 1) and
admin panel (1.5), alongside/within Orders core parity:
1. Outcome logging sheet + lead card quick actions (Features 1 & 5)
2. Follow-up Hub (Feature 2)
3. Template Hub with Direct WhatsApp provider (Feature 3; AiSensy/API path can
   land later with Edge Functions)
4. Ops Calendar (Feature 4)
5. CRM Hub (Feature 6)
All tables new to this spec (wa_templates, any call_history structure) need
org_id from birth and RLS like everything else. SQL goes through the owner.
