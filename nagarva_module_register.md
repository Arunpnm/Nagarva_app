# Nagarva — Consolidated Module Register

**Created:** 01 Aug 2026
**Purpose:** Single source of truth for all outstanding scope. Replaces the master index in `nagarva_master_build_brief.md`, the carryover line in `nagarva_parity_brief.md`, and the unnumbered modules in `nagarva_operational_flow.md`.

**Launch rule:** Nagarva goes live only when every module below is complete. No phased launch, no pilot-first, no scope trimming. Sequencing here is by **dependency**, not by priority — since everything ships, the only question is what order avoids rework.

**Source codes:** `MB-##` master build brief · `PB` parity brief · `OF-§` operational flow · `P8` Part 8 · `NEW` surfaced 01 Aug, not in any prior document

---

## Status of prior scope

Three reconciliation passes on 01 Aug found all three tracking documents **under-report** what exists. Verified done, against code:

| Was marked | Actually |
|---|---|
| MB-02 Not started | Done — `_writeQuoteSnapshot` writes quote data onto the order at conversion |
| MB-03 Partial | Done — in-app actions, status chips and PDF block all exist |
| MB-04 Not started | Mostly done — `DetailRow` used 20× on Order Details |
| MB-05 Not started | Done — `lib/backend/lead_status.dart` with auto-transitions and progress strip |
| MB-06 Partial | Done — Share Tracking Link + `TrackingService.logStatus` wired into three flows |
| MB-09 Not started | Done |
| MB-10, MB-11 | Done, including payment-entry delete |
| Signature/tracking "BACKEND ONLY" | Flutter side fully built |
| Materials "not started" | CRUD live since 13 Jul; only the consume path is missing |

**Also shipped 01 Aug (Part 8):** notification bell (`7b16fee`); shared `PdfBranding` + Survey PDF + Quote PDF + invoice signature inheritance (`0195e8f`); per-org charge basis + jsonb dual-shape + Detailed PDF variant (`6253524`).

**Total outstanding: 55 modules.**

---

## Phase 0 — Close out (no dependencies, do immediately)

| ID | Module | Source | Notes |
|---|---|---|---|
| NG-001 | Part 8 device test | P8 | Five tests, legacy-shape reprint first |
| NG-002 | Fix stale docs — `NAGARVA_STATUS.md` + `CLAUDE.md` RLS section | session | Doc-only writes; stops a fourth reconciliation pass |
| NG-003 | Dashboard blank space — fresh repro | MB-08 | Suspected cause is gone but was never confirmed as the cause |
| NG-004 | Verify parity sub-items: settings wiring, fleet CRUD, expense filters, touch targets | PB | Grep-level check |
| NG-005 | Privacy policy + terms | MB-21 | **Blocks WhatsApp API, Play Store, DPDP** — small, unblocks three things |
| NG-053 | Error monitoring (Sentry) | MB-20 | Listed in Phase 7 but **pull forward** — it is worth far more during the build than after |

---

## Phase 1 — Foundations

Everything downstream hangs off these. Building modules before them means retrofitting later.

| ID | Module | Source | Why first |
|---|---|---|---|
| NG-006 | RBAC matrix + server-side RLS enforcement | MB-30, OF-Part5 | Every module needs permission entries. Build the matrix now and each module registers into it; build it later and you retrofit across 50 screens |
| NG-007 | Customers master + order linkage | MB-24a | Orders store loose name/phone today. Storage billing, branch settlement, rate cards, repeat-customer history all hang off this entity |
| NG-008 | Per-tenant CFT item catalogue | MB-12A | Blocks NG-032 and NG-050. Every tenant currently inherits APC's item list |
| NG-009 | Per-tenant vehicle/crew slabs | MB-12B | Same. Overlap/gap validation at config time |
| NG-010 | Document numbering generator | OF-6.11 | Gapless, per-org, per-FY, concurrency-safe. Four documents need it — build once |
| NG-011 | Quote versioning | OF-1.2 | Brief written (`nagarva_part9_quote_versioning.md`). MB-11's delete rules already assume it exists |

---

## Phase 2 — Operational core

The daily-ops layer your staff touch. Entirely unnumbered until now, which is why it was invisible to every planning pass.

| ID | Module | Source | Depends on |
|---|---|---|---|
| NG-012 | Supervisor access window — multi-day, `load_date`/`delivery_date`, reassignment | OF-2.2 | NG-006 |
| NG-013 | Attendance derivation + double-count rule | OF-2.3 | NG-012 |
| NG-014 | Salary credit/debit ledger + days-worked calendar | OF-2.4 | NG-013 |
| NG-015 | Cash imprest (supervisor advance → settlement) | OF-2.5 | NG-006 |
| NG-016 | Materials issue → consume → return → damage | OF-Part3, PB | CRUD exists; build the cycle on it |
| NG-017 | Fuel entries — litres, odometer, photos, full-tank flag | OF-4.1A | — |
| NG-018 | Daily vehicle log + overnight-gap cross-check | OF-4.1B, 4.3 | — |
| NG-019 | Mileage engine — tank-to-tank, rolling average, anomaly flags | OF-4.2 | NG-017, NG-018 |
| NG-020 | Expense approval flow + auto-approve threshold | OF-6.4 | NG-006 |
| NG-021 | Unlock / edit-request path after completion | OF-1.5 | NG-006 |

> **Capture-first warning.** Diesel **litres** (NG-017) and material **returns** (NG-016) cannot be reconstructed retrospectively. Every day they are not captured is data permanently lost. If anything in this phase slips, these two do not.

---

## Phase 3 — Documents & compliance

| ID | Module | Source | Depends on |
|---|---|---|---|
| NG-022 | LR / consignment note (bilty) — **legally required** | MB-22 | NG-010 |
| NG-023 | Packing List | OF-1.4 | NG-010 |
| NG-024 | Loading Slip | OF-1.4 | NG-010 |
| NG-025 | Money Receipt | OF-1.4 | NG-010 |
| NG-026 | E-way bill phase 1 — capture, store, expiry alert | MB-23a | NG-022 |
| NG-027 | E-way bill phase 2 — NIC API integration | MB-23b | NG-026 |
| NG-028 | Condition photos at loading + unloading | MB-14 | — |
| NG-029 | Proof of delivery | MB-15 | NG-028 |
| NG-030 | Transit insurance + claim tracking | MB-26 | NG-028, NG-029 |
| NG-031 | Vehicle compliance, maintenance, attached/hired vehicles | MB-25, OF-4.6/4.7 | NG-018 |

> **Shared-infrastructure cluster:** NG-028, NG-029 and NG-030 all use the same evidence layer — per-org Storage bucket, client-side compression to 200–400 KB, server-side timestamps, immutable once uploaded. Build that layer once with NG-028.

---

## Phase 4 — Commercial

| ID | Module | Source | Depends on |
|---|---|---|---|
| NG-032 | Public per-vendor enquiry link + Web Enquiries inbox | MB-13 | NG-008 |
| NG-033 | Corporate accounts — consolidated invoicing, statements, ageing, credit control, rate cards | MB-24b | NG-007 |
| NG-034 | Payment collection link (UPI) | MB-19 | — |
| NG-035 | Customer feedback post-POD | OF-6.5 | NG-029, NG-039 |
| NG-036 | Lost-lead remarketing pool, postponed handling, `marketing_opt_out` | OF-1.3 | NG-039 |
| NG-037 | Duplicate lead detection across all sources | OF-6.10 | — |
| NG-038 | Addon service subcontractor master + followup | **NEW** | NG-006 |
| NG-039 | WhatsApp templates + send infrastructure + delivery status | PB | NG-005 |

> **NG-038 is genuinely new scope.** Carpenter, AC technician, deep cleaning — a vendor entity with contact, rate, job assignment, payable balance and followup. It appears in no prior document; the closest is "addon services" as an expense line.

---

## Phase 5 — Order lifecycle completeness

| ID | Module | Source | Depends on |
|---|---|---|---|
| NG-040 | Order cancellation — distinct from Lost, charges, refund, release crew/vehicle | OF-6.2 | — |
| NG-041 | Rescheduling — carry assignment, notify, free slot, count reschedules | OF-6.3 | — |
| NG-042 | Partial / shared loads — multi-order trips, CFT apportionment, separate LRs | OF-6.7 | NG-022 |
| NG-043 | Advance & balance payment gates | OF-6.9 | — |
| NG-044 | Warehousing / storage billing + daily accrual | MB-27, OF-6.8 | NG-007 |
| NG-045 | Branch transfers & inter-branch settlement | MB-28 | NG-007, NG-046 |

---

## Phase 6 — Intelligence

Assembly of everything captured above. Cannot be built earlier because the inputs do not exist yet.

| ID | Module | Source | Depends on |
|---|---|---|---|
| NG-046 | Job costing — actual vs quoted, per-order profitability | OF-6.1 | NG-014, NG-016, NG-019, NG-020 |
| NG-047 | Reports pack — 8 reports, date/branch filters | MB-29 | NG-046 |
| NG-048 | Data export — CSV/XLSX, GST preset | MB-17 | NG-047 |
| NG-049 | Escalation & SLA alerts | OF-6.6 | NG-012 |

> **Shared-infrastructure cluster:** NG-047 and NG-048 are the same query layer with two outputs. Build the query layer once.

---

## Phase 7 — Platform & polish

| ID | Module | Source | Depends on |
|---|---|---|---|
| NG-050 | Self-signup & trial onboarding + tenant seeding | MB-16 | NG-008, NG-009, NG-039 |
| NG-051 | Subscription billing — vendor sees, upgrades, pays for their plan | **NEW** | NG-050 |
| NG-052 | Offline mode — survey/quote capture + photo queue | MB-18 | NG-028 |
| NG-054 | Lead Details alignment remainder | MB-04 | — |
| NG-055 | Multi-language — Tier 1 (en/ta/hi/kn), Tier 2, Tier 3 | MB-07 | **Everything** |

> **NG-051 is genuinely new scope.** MB-16 assigns a trial plan; nothing lets a vendor view, upgrade or pay for it. A multi-tenant SaaS cannot go live without it.

> **NG-055 must be last.** Every screen must exist before localisation, or the work is done twice.

---

## Build conventions — apply to every module

These prevent the rework class that cost three reconciliation passes.

1. **Soft delete from creation.** `deleted_at`, `deleted_by`, `delete_reason` on every new table, partial index `where deleted_at is null`, and `and deleted_at is null` on *every* read path including KPIs and P&L. Half-done soft delete is worse than none.
2. **RLS:** `org_id in (select current_org_ids())` — never `= any(...)`.
3. **`orders.id` is TEXT** (NGV-XXXX). Joins need `::text` casts; `entity_id` columns in new tables are text.
4. **`DROP FUNCTION` before changing a return type.**
5. **Snapshot, never live-lookup.** Any value printed on a customer document — CFT per line, charge basis, rate, slab, pricing — is resolved at creation time and stored. A later config edit must never rewrite a document the customer already holds.
6. **Refresh:** `nagarvaRouteObserver` + `RefreshOnPopMixin/onPageRefresh()`. Realtime for live badges.
7. **Numbering** goes through NG-010. Never client-side max+1.
8. **Photos:** compress client-side to 200–400 KB, timestamp server-side, immutable once uploaded.
9. **Every new module registers its permissions** into the NG-006 matrix as it is built.
10. **SQL is handed over, never run.** Batch migrations per module cluster — one reviewed file, not six dribbles.
11. **Introspect before asserting.** Never reconstruct a live DB object from memory of an earlier read.

---

## Throughput notes

- **The bottleneck is SQL review, not code.** Every migration waits on Arun. Group them per cluster so one review unblocks a whole phase.
- **Do not parallelise schema work.** Two agents generating migrations against the same database produce a conflicting pair neither knows about.
- **Claude Code for anything schema-touching** — the introspect-and-push-back loop is what caught seven stale status claims. **Cowork for bulk execution** once a design is settled.
- **Update this register as the single tracker.** The stale-doc problem came from status living in three places.
