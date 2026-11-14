-- ============================================================
-- 20261114_customer_booking.sql  (14 Nov 2026)
--
-- Customer app: book and pay online, then "My moves" (list item 27).
-- Arun, 14 Nov 2026: "we have integrated razorpay ... test with that".
--
-- How a booking happens:
--   1. The customer signs in with their mobile number (OTP, the same
--      sign-in the vendor app uses).
--   2. The app sends the move to the `mkt-book` function. The function
--      prices it again with mkt_quote() - a customer can never send their
--      own price - saves a booking here, and makes a Razorpay payment link
--      for the ADVANCE.
--   3. The customer pays on Razorpay's own page.
--   4. Razorpay tells `razorpay-webhook` (event payment_link.paid). That
--      calls mkt_booking_paid() below, which checks the amount, marks the
--      booking paid and creates the marketplace job (broadcast to vendors),
--      exactly as a job typed in by the Nagarva admin.
--   5. "My moves" (mkt_my_moves) shows the customer each booking: paid or
--      not, the job's progress, the vendor once one accepts, and the
--      delivery code.
--
-- Nothing here moves money: Razorpay holds it; this records what
-- Razorpay says happened.
--
-- Run once in the Supabase SQL editor. Nothing is deleted.
-- ============================================================

begin;

create table if not exists public.mkt_bookings (
  id               uuid primary key default gen_random_uuid(),
  customer_user_id uuid not null,
  customer_name    text not null,
  customer_phone   text not null,
  input            jsonb not null,      -- what was priced (mkt_quote input)
  quote            jsonb not null,      -- mkt_quote's answer at booking time
  pickup_address   text not null,
  drop_address     text not null,
  move_date        date not null,
  slot             text,
  total_inr        numeric not null,
  advance_inr      numeric not null,
  status           text not null default 'awaiting_payment'
                   check (status in ('awaiting_payment', 'paid', 'cancelled', 'expired')),
  rzp_link_id      text unique,
  rzp_link_url     text,
  rzp_payment_id   text,
  paid_at          timestamptz,
  job_id           uuid references public.mkt_jobs(id),
  created_at       timestamptz not null default now()
);
create index if not exists mkt_bookings_customer_idx on public.mkt_bookings (customer_user_id, created_at desc);

alter table public.mkt_bookings enable row level security;
drop policy if exists mkt_bookings_own on public.mkt_bookings;
create policy mkt_bookings_own on public.mkt_bookings
  for select using (customer_user_id = auth.uid() or public.is_platform_admin());
drop policy if exists mkt_bookings_admin on public.mkt_bookings;
create policy mkt_bookings_admin on public.mkt_bookings
  for all using (public.is_platform_admin()) with check (public.is_platform_admin());
-- Inserts and payment updates come only from the functions (service role).

-- Razorpay says the advance is paid: check, mark paid, create the job.
-- Idempotent: a repeat of the same event returns the job already made.
create or replace function public.mkt_booking_paid(p_link_id text, p_payment_id text, p_amount_paise bigint)
returns text language plpgsql security definer set search_path = public as $$
declare
  b  public.mkt_bookings%rowtype;
  r  public.mkt_city_rules;
  v_job uuid;
  v_otp text;
  v_items jsonb;
  v_no text;
begin
  select * into b from public.mkt_bookings where rzp_link_id = p_link_id for update;
  if not found then
    return 'unknown_link';
  end if;
  if b.job_id is not null then
    return 'already_booked';
  end if;
  if p_amount_paise is null or p_amount_paise < round(b.advance_inr * 100) then
    return 'amount_short';
  end if;

  r := public.mkt_rules_for(b.input->>'from_city');

  -- The items with their names, the way vendors read them.
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', c.key, 'name', c.name, 'cat', c.cat,
           'variant', c.variants -> coalesce((l->>'variant')::int, 0) ->> 'name',
           'cft', (c.variants -> coalesce((l->>'variant')::int, 0) ->> 'cft')::numeric,
           'qty', coalesce((l->>'qty')::int, 1),
           'services', coalesce(l->'services', '[]'::jsonb))), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(coalesce(b.input->'lines', '[]'::jsonb)) l
    join public.mkt_catalogue c on c.key = l->>'key';

  v_otp := lpad((floor(random() * 10000))::int::text, 4, '0');
  v_no  := 'NG-' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD') || '-'
           || lpad((floor(random() * 9000) + 1000)::int::text, 4, '0');

  insert into public.mkt_jobs (
    job_no, pickup_city, drop_city, package, move_date, slot, cft, items,
    total_inr, gst_inr, advance_inr, commission_pct,
    customer_name, customer_phone, pickup_address, drop_address, delivery_otp
  ) values (
    v_no, b.input->>'from_city', coalesce(b.input->>'to_city', b.input->>'from_city'),
    coalesce(b.input->>'package', 'standard'), b.move_date, b.slot,
    (b.quote->>'cft')::numeric, v_items,
    b.total_inr, coalesce((b.quote->>'gst')::numeric, round(b.total_inr * 18 / 118, 2)),
    b.advance_inr, coalesce(r.commission_pct, 0),
    b.customer_name, b.customer_phone, b.pickup_address, b.drop_address, v_otp
  ) returning id into v_job;

  insert into public.mkt_job_events (job_id, kind, note)
  values (v_job, 'broadcast', 'Booked and paid in the customer app (Razorpay ' || coalesce(p_payment_id, '') || ')');

  update public.mkt_bookings
     set status = 'paid', paid_at = now(), rzp_payment_id = p_payment_id, job_id = v_job
   where id = b.id;
  return 'booked';
end $$;
revoke all on function public.mkt_booking_paid(text, text, bigint) from public, anon, authenticated;

-- The signed-in customer's moves, newest first.
create or replace function public.mkt_my_moves()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', b.id,
      'created_at', b.created_at,
      'status', b.status,
      'pay_url', case when b.status = 'awaiting_payment' then b.rzp_link_url end,
      'from_city', b.input->>'from_city',
      'to_city', coalesce(b.input->>'to_city', b.input->>'from_city'),
      'move_date', b.move_date,
      'slot', b.slot,
      'package', b.input->>'package',
      'total', b.total_inr,
      'advance', b.advance_inr,
      'pickup_address', b.pickup_address,
      'drop_address', b.drop_address,
      'job_no', j.job_no,
      'job_status', j.status,
      'delivery_code', case when j.status not in ('delivered', 'cancelled') then j.delivery_otp end,
      'vendor_name', case when j.accepted_org_id is not null then o.name end,
      'vendor_phone', case when j.accepted_org_id is not null and j.status not in ('delivered', 'cancelled') then o.phone end
    ) x
      from public.mkt_bookings b
      left join public.mkt_jobs j on j.id = b.job_id
      left join public.organizations o on o.id = j.accepted_org_id
     where b.customer_user_id = auth.uid()
  ) s;
$$;
revoke all on function public.mkt_my_moves() from public, anon;
grant execute on function public.mkt_my_moves() to authenticated;

commit;
