-- ============================================================
-- supabase/20260818_arrival_code_and_signature_completion.sql
--
-- Replaces the two-OTP job flow with: a single ARRIVAL code, and a
-- customer SIGNATURE at handover as the completion event.
--
-- ---- WHY (Arun, 18 Aug 2026) ---------------------------------------
-- The completion OTP proved nothing. Read the code before changing it:
-- `_generateOtp()` writes a random 4-digit code to `orders.job_otp` and
-- DISPLAYS IT ON THE SUPERVISOR'S OWN SCREEN; `_verifyAndComplete()`
-- then re-reads that same value from the DB and compares it to what the
-- supervisor typed. The supervisor holds both halves. Nothing in the
-- flow binds it to the customer being present — it proves only that a
-- supervisor typed a number their own phone had just shown them.
--
-- A single code reused at both ends is worse still: once the supervisor
-- has it, they can close the job from anywhere.
--
-- A signature at handover proves presence, produces a document, and
-- reuses `SignaturePad`, which already works. So:
--   ARRIVAL    -> one code per order, shared with the customer at
--                 confirmation, entered by the supervisor on arrival.
--   COMPLETION -> customer signs on the supervisor's phone. The
--                 signature IS the completion event and the POD.
--
-- ---- WHAT THIS MIGRATION DOES *NOT* CHANGE -------------------------
-- The nine writes in `_verifyAndComplete()` (order status, crew sync,
-- status history, pod_records, attendance, notification_log,
-- notifications, field-expense lock) are all correct and all stay. This
-- replaces the GATE in front of them, not the flow behind it.
--
-- HANDED BACK UNRUN.
-- ============================================================

begin;

-- ---- 1. Arrival code ------------------------------------------------
--
-- A NEW column rather than reusing `orders.job_otp` (Arun's call): the
-- old column holds completion OTPs for in-flight jobs, and repurposing
-- it mid-transition would silently change what an existing job's code
-- means. `job_otp` is left in place and stops being written; drop it in
-- a later cleanup once no open order depends on it.
--
-- DEFAULT rather than app-generated so a code always exists by
-- construction — no code path can forget to create one, which is the
-- same reasoning as seeding number_series at signup rather than
-- allocating lazily.
--
-- 4 digits deliberately: this is a "did the customer share it with you"
-- check, not a security boundary. It must be readable over a phone call
-- and typeable with gloves on. Guessing it wrongly gains an attacker
-- nothing — arrival only moves the job to 'transit'.
alter table orders
  add column if not exists arrival_code text
  default lpad((floor(random() * 10000))::int::text, 4, '0');

-- Existing orders have no code. Give every one that could still be
-- worked a code now; delivered/closed/cancelled jobs are history and
-- don't need one.
update orders
   set arrival_code = lpad((floor(random() * 10000))::int::text, 4, '0')
 where arrival_code is null
   and coalesce(status, '') not in ('delivered', 'closed', 'cancelled');

comment on column orders.arrival_code is
  'Shared with the customer when the job is confirmed; the supervisor '
  'enters it on arrival to mark shifting started. Delivery is manual '
  'for now (read out, or printed on the order confirmation) — wire to '
  'AiSensy when that exists. NOT a security boundary: it proves the '
  'customer passed it on, nothing more. Completion is proven by the '
  'signature on pod_records, not by any code.';

-- ---- 2. How a job was completed -------------------------------------
--
-- A new column rather than repurposing `pod_records.otp_verified`
-- (Arun's call, and the right one): a boolean whose NAME LIES is worse
-- than an extra column. Someone reading `otp_verified = false` in 2027
-- would reasonably conclude the OTP check failed, when in fact no OTP
-- was ever involved.
--
-- `otp_verified` stays, untouched, describing historical rows honestly.
alter table pod_records
  add column if not exists completion_method text;

-- Backfill before adding the constraint, so every existing row is valid.
-- Every pod_records row to date was written by the OTP flow.
update pod_records
   set completion_method = case
         when otp_verified is true then 'otp'
         else 'otp'  -- same: the only writer that ever existed was the
                     -- OTP flow, and it always set otp_verified true.
       end
 where completion_method is null;

alter table pod_records
  drop constraint if exists pod_records_completion_method_check;
alter table pod_records
  add constraint pod_records_completion_method_check
  check (completion_method is null or
         completion_method in ('signature', 'otp', 'not_available'));

comment on column pod_records.completion_method is
  'signature      = customer signed at handover (signature_data is set, '
  'and received_by_name/relationship are required by the app). '
  'otp            = legacy 4-digit completion OTP, removed 18 Aug 2026 '
  'because the supervisor held both halves and it proved nothing. '
  'not_available  = customer absent or refused; reason in remarks, '
  'no signature. These surface distinctly in the owner''s Awaiting '
  'Approval queue — "done, signed" and "done, nobody signed" are '
  'different risks and must not look the same to the approver.';

-- ---- 3. Reason for an unsigned completion ---------------------------
-- `pod_records.remarks` already exists and carries the free text. This
-- adds only the structured reason, so unsigned completions can be
-- counted and filtered rather than grepped.
alter table pod_records
  add column if not exists not_available_reason text;

alter table pod_records
  drop constraint if exists pod_records_not_available_reason_check;
alter table pod_records
  add constraint pod_records_not_available_reason_check
  check (not_available_reason is null or
         not_available_reason in ('customer_absent', 'refused_to_sign',
                                  'representative_took_delivery',
                                  'device_or_app_failure'));

comment on column pod_records.not_available_reason is
  'Set only when completion_method = ''not_available''. Structured so '
  'unsigned completions can be counted per supervisor and per reason — '
  'a flow with no escape hatch gets worked around in the field, and the '
  'worst workaround here is the supervisor signing it themselves. Free '
  'text goes in remarks alongside this.';

commit;

-- ============================================================
-- VERIFY (read-only)
--
--   select count(*) filter (where arrival_code is not null) as with_code,
--          count(*) as total
--     from orders
--    where coalesce(status,'') not in ('delivered','closed','cancelled');
--   -- expect with_code = total
--
--   select completion_method, count(*) from pod_records
--    group by completion_method;
--   -- expect every existing row = 'otp'
--
-- NOTE ON OFFLINE (checked, 18 Aug 2026): SignaturePad.toPngBase64()
-- rasterises locally via RenderRepaintBoundary and needs no network, and
-- pod_records.signature_data is `text` holding the base64 PNG inline —
-- so the signature never needs a Storage bucket. What still needs
-- connectivity is the nine completion writes, which was equally true of
-- the OTP flow. The app captures the signature to local state BEFORE any
-- write, so a failed sync can never make a customer sign twice. Genuine
-- offline completion is Item 18's queue, not a blocker for this change.
-- ============================================================
