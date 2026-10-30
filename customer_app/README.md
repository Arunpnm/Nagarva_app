# Nagarva customer app

Customers book a move directly with Nagarva. Nagarva prices it from its own
rates and broadcasts it to vendors through the marketplace. Design:
`design_handoff_nagarva_redesign/design/Nagarva Customer.dc.html`.

A separate Flutter app (Arun, 30 Oct 2026), package `in.nagarva.customer`,
on the same pinned SDK as the vendor app (Flutter 3.35.5) and the same
Supabase project.

## What works

The quote flow, end to end: move type → city and floors → items (the design
catalogue, sizes in CFT, per-item services) → date and time → package →
add-ons → review with the price.

Every price comes from `mkt_quote()` on the server
(`supabase/20261030_marketplace_pricing.sql`), from the rates Nagarva's
admins enter in Super Admin › Marketplace › Prices. A missing price shows
as "not taking bookings for this yet", never as a made-up number.

## What waits

- **Booking and payment.** `kBookingLive` in `lib/config.dart` is false;
  the last button says online payment opens soon. Arun's decision: wait
  for the payment gateway (which entity collects is with the CA, CLAUDE.md
  Item 31).
- **Login (phone OTP), My bookings, tracking, damage claims, reschedule,
  cancel, account.** They all hang off a booking, so they come with it.
- **Languages.** English only for now; the design has six.
- **Website.** `Nagarva Website.dc.html` is the same flow in a web shell;
  `flutter build web` of this app is the starting point.

## Run

```
cd customer_app
flutter pub get
flutter run
flutter test
```

The pricing migration must be run in Supabase first, or the city list is
empty.
