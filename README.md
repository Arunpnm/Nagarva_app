# Nagarva

Flutter mobile app for the packers-and-movers industry — a multi-tenant
vertical SaaS/ERP built on Supabase. Started as the internal app for
Arun Packers and Couriers (APC); APC is tenant #1 of the multi-tenant
product.

This codebase began as a FlutterFlow export and is now developed as
plain Flutter/Dart. See `CLAUDE.md` for the full project brief,
architecture, conventions, and change history — read that first, it is
the living source of truth for this repo.

## Getting started

```bash
git clone https://github.com/Arunpnm/Nagarva_app.git
cd Nagarva_app
flutter pub get          # mandatory — see docs/SETUP_NEW_MACHINE.md
flutter analyze lib/
flutter run
```

Flutter is pinned at **3.35.5** — do not `flutter upgrade` (see
`CLAUDE.md`'s environment rules for why).

## Where things live

- **`CLAUDE.md`** — project brief, architecture, conventions, known
  issues, roadmap, and a dated changelog. The single source of truth.
- **`docs/`** — supporting reference docs (setup guide, open specs and
  briefs still relevant to unfinished or unverified work). Superseded
  planning docs have been removed; `CLAUDE.md`'s changelog is the
  record of what they described and how it turned out.
- **`lib/`** — the app, one folder per page (FlutterFlow-style) plus
  `backend/` (Supabase client + generated tables) and `flutter_flow/`
  (the FlutterFlow helper library).
- **`supabase/`** — SQL migrations, handed over and run manually
  against the live project (never auto-applied from this repo).
