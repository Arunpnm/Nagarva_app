# Nagarva project notes

## Pending (pick up here)
0. ERP gap batches, ALL items approved by user (19 Oct 2026). E1 DONE (i18n-b10/b10b). E3 DONE (b14 gx/cn/bk/cb, i18n-b12). E4 DONE (b15 bb/cp/pr/lq; autoOwner on new lead; i18n-b13). E6 DONE (b17 plat screen tabs br/wa/ap/bk/dw via "plat:tab"; i18n-b15; wired: brOk() filters orders/leads, waAuto(k,name) on lead/confirm/start/deliver, needAppr(rule,what,f) gates deletes + quote revise, widL drives dashboard order/visibility; rcPend/salPend + apBar for rate/salary approval; void receipt (pay rule); WA survey+due wired; br field on new leads/orders + BRSEED). E5 DONE (b16 hr screen, tabs lv/pay/inc/doc/lab via MENU dest "hr:tab"; i18n-b14). E2 DONE (i18n-b11/b11b; links() ties trips/fuel/adv/stor/claims/loads/eway/hire to orders; payX = shared payments; nextRct()). Order: E1 Operations → E2 Transport → E3 Finance → E4 Sales → E5 People → E6 Platform.
   - E1 Ops: packing list + box labels/QR, vehicle (car/bike) checklist, proof of delivery (photos+OTP), damage & claims, storage billing monthly, route planning + multi-drop, part-load booking
   - E2 Transport: driver app (trip start/end, fuel, toll), fuel log + mileage, tyre & battery, toll/FASTag, e-way bill, vehicle doc expiry (RC/FC/permit/PUC/ins), hired-truck booking & pay, diesel advance
   - E3 Finance: GSTR-1/3B export, TDS on vendors, credit notes/refunds, bank recon, Tally/Zoho export, gateway + UPI auto-match, cash book/petty cash, multi-branch accounts
   - E4 Sales: B2B accounts (credit limit, monthly billing), customer portal, live GPS link, referral/coupons, lead auto-assign, lost-lead report
   - E5 People: leave, PF/ESI, payslip PDF, overtime/incentives, staff docs expiry, labour contractor pay
   - E6 Platform: branch switcher, offline mode, backup/restore, dashboard widgets, auto WhatsApp per stage, approval for edits/deletes
   - New screen checklist: scr key, SCR_MOD, hdrBack exclusion list ('setHub','jrny',...), MENU entry, GROUPS + _grp (te/kn/ml) if new group.
   - Keep each run_script edit small (connection timeouts). New English keys in B10+ objects; translations in i18n-b10.js etc.
1. Translations (hi, ta, te, kn, ml) in i18n-help.js, i18n-b1.js … i18n-b4.js were written by Claude; native-speaker review planned at handover. Don't rewrite them unless asked.

## Modules (20 Oct)
- bizType (pm/tr/both) + modsOn overrides; MODX lists pm/tr/adv dests; modOn(dest) filters MENU; adv items go to collapsed "Advanced" group; Settings › Modules screen (scr mods); first-run btAsk sheet after onbDone. Menu labels translated via NG_TX[l]._mnu (i18n-b17.js). New menu items: add to _mnu in all 5 langs.

## Plans & docs (20 Oct)
- 4 plans free/basic/growth/pro (PLANS, PRANK, PMIN dest→min tier, tier(), planOk()); modOn() also checks plan. Modules page shows lock pill + "Unlock with an upgrade" group.
- onbDone + bizType persisted in localStorage (ng_onb_done, ng_biz_type) so phone setup shows once per install.
- Journey docs (b20): svy, qt, rct, pk, ls, lr, ins, inv with plan gating + doc viewer overlay (st docV). Quote stage has transit insurance (J.ins, 2% premium) + advance payment before confirm (confirmAdv). Strings B19/B20 → i18n-b18/b18b.

## Vendor signup (21 Oct)
- App scr 'signup' (b21/B21, state suF, out key sux): phone → OTP → business → docs → review → status. Saved to localStorage ng_signups; own id in ng_signup_me. Login A shows status banner. Strings → i18n-b19.js.
- Admin › Approvals shows "New vendor signups" (SU0 seed + ng_signups); approve adds Free-plan vendor, send back with reason chips.
- After approval vendor picks "Start 30-day Pro trial" or "Stay on Free" (plan st:'trial'; tier() → free when days≤0). Banner at ≤3 days; Plan screen demo chips for trial states. Admin vendors() reads trial from ng_signups. Rates default to 0 (empty inputs, rcEmpty banner).

## Staff join &amp; logout (26 Oct)
- b22/B22 (i18n-b20.js): staff join sheet (st jn: code → otp → pin), invOf(id) = 'AP-xxxx' code, phone must match staff phone; link saved in localStorage ng_staff_link. Login staff tab shows linked profile + PIN, or "not linked" card + demo chips.
- Staff header account_circle (acct) → Help, Log out, Remove this phone. Owner: Staff list send_to_mobile icon / after Add staff → invite sheet (st inv).

## Check-in, search, company switch (27 Oct)
- b23/B23: no self check-in. Field staff scan the rotating QR (qrBits, 30 s) on the supervisor's Team screen; supervisor checks in by GPS (≤200 m) + selfie; supervisor "Mark present" for crew without phone (reason, st ciMan). Owner Approvals shows "Check-ins to review" (ci.rev) with Flag. Old approve/reject (aaSup/aaMgr) no longer rendered.
- Global search: empty query shows only hint; results come from data across modules (no screen entries).
- Greeting t.morning computed from device hour (gr_m/a/e).
- b24/B24: header business name → Switch company sheet (ORGS, st org); also in staff account sheet. List shows only companies saved on this phone (localStorage ng_orgs, default ['arun']); "Add a company" (st orgAdd) via login (ORGCRED kovai: manager@kovaimovers.in / kovai123) or invite code (sbp: SB-2201) → saved + switched; sign-out icon removes non-current company. Strings for B23/B24 → i18n-b21.js.

## Marketplace (27 Oct) — next phase
- Nagarva sells moves direct to public (app + website). Nagarva alone sets price: CFT from item inventory × package rate (eco/std/prem, local base + per-km) + floor charge + add-ons + 18% GST.
- Customer pays advance (10%, min ₹999) to Nagarva; balance paid to vendor after delivery OTP. 12% fixed commission auto-deducted from vendor wallet on completion.
- Broadcast: Gold sees first, then Silver, then Bronze; delay windows set by admin per city. First to accept serves. Wallet below minimum → vendor can't see broadcasts. Premium package → Gold only.
- Tier score: rating, on-time arrival, damage claims, acceptance rate, photo compliance, vendor cancellations, jobs completed.
- Files: Nagarva Customer.dc.html (customer mobile app, built first). Vendor side DONE (27 Oct): App scr 'mkt' (b25/B25, i18n-b22.js), menu 'Nagarva jobs' in Sales. Tabs jobs (new broadcast w/ Gold timer, masked customer, accept/pass; accepted stepper Accepted→On the way→Arrived→Loading(3 photos)→In transit→Delivered(OTP 4821); completed w/ rating), wallet (MW0 bal/min 2000, top-up UPI, withdraw above min, tx list; completion credits advance − 12% comm on ex-GST), tier (7 weighted factors → score, Gold 80+/Silver 60/Bronze). Admin DONE (27 Oct): Nagarva Admin scr 'mkt' (NAV 'Marketplace', mpVals(C); seeds MPJ0 jobs, MPD0 disputes, MPV0 vendors, MPW0 withdrawals, MPC0 per-city rules gs/sb/min/com/adv/advMin/lateMin/stuckH, MPWT0 weights). Tabs: live (4 columns + job drawer w/ timeline, push tier, assign, re-assign), alerts (no vendor / late / photos / stuck), disputes (refund/split/reject), vendors (tier, score, wallet, suspend), money (GMV, advances, commission, withdrawals mark paid), city rules (steppers) + weights (must total 100). Vendor availability toggle (mkAv), extra pickup cities (mkCities), return trip mode (mkRt; jobs with rl:1, rc=city) + Admin tab "Return trips" (MPR0) and city rule rlD. Customer website (28 Oct, English only): Nagarva Website.dc.html = copy of Nagarva Customer.dc.html (same flow + look, OTP login first, bookings, account, cancel/reschedule, claim, balance pay) inside a web shell (blue site bar + centered 560px column, no phone frame/status bar). Keep the two files in sync — edits to Customer should be mirrored. Old marketing-style site kept as Nagarva Website v1.dc.html.
- Customer/Website i18n (28 Oct): DOM text translator i18n-cust.js (ngCust.set(lang, body); exact English match → ' · ' parts → _p regex patterns). Dictionaries keyed by English: i18n-c-hi.js, i18n-c-{ta,te,kn,ml}.js + *2.js (split halves). State lang persisted in localStorage ng_cust_lang; pills on Login + Account. New English UI strings must be added to all 5 dictionaries. Addresses/names/codes stay English.
- Creative pass (28 Oct): blue hero on Home + Track (truck road progress), blue selected package card, blue "ticket" total on Review, OTP digit boxes. Backups: "Nagarva Customer -pre-home redesign-.dc.html", "Nagarva Website -pre-home redesign-.dc.html".

## Done
- Company branding: no Nagarva logo inside the vendor app — header/menu/Login B/join card show company logo or monogram (hdrInit). Business details (biz: logo, sign, address…) persist to localStorage ng_biz and sync live across tabs/devices via storage event (stand-in for server sync).
- Admin rebuilt from lib/super_admin_page (Plans editor, vendor detail actions). Old version kept as Nagarva Admin v1.dc.html.
- All More-menu modules designed (batches 1–4), back buttons on all non-tab screens, Help & support → Admin tickets. Screen map in github.md.
- Help icon in the top bar for supervisor / field roles (showHelpIcon) → help screen.
