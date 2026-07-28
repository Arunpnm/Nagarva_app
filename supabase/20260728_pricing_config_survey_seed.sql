-- Parity brief Part 3 (27-28 Jul 2026) — survey/CFT/package/charge defaults,
-- seeded into the existing `pricing_config` table rather than a new one
-- (brief explicitly says: check pricing_config fits before adding a table —
-- it does, `config` is already jsonb with an `org_id` column).
--
-- Data ported verbatim from reference/APC Web App JSX/App.jsx:
--   SURVEY_CATS        (~line 677)  -> config->'survey_cats'
--   DEFAULT_CFT_RANGES (~line 881)  -> config->'cft_ranges'
--   DEFAULT_PACKAGES   (~line 898)  -> config->'packages'
--   DEFAULT_PORTER_RATES (~line 915) -> config->'porter_rates'
--   charge field list (~line 2671, 3175-3223) -> config->'charge_defaults'
--     (billing-mode-eligible keys + their default mode, matching
--     chargeTypes' initial state: packing/unpacking/loading/unloading/
--     materials default to "included"; everything else has no billing
--     mode concept, just a plain amount)
--
-- Idempotency: this migration can be re-run safely. It only ever merges
-- missing keys into an org's existing config (`seed_defaults || config`,
-- so the ORG'S existing keys win on conflict — a vendor's own edits are
-- never overwritten) and only inserts a fresh row for orgs that don't have
-- one yet. Re-running after a vendor has edited their pricing_config is
-- safe and will not clobber their changes.
--
-- Run this AFTER confirming `pricing_config` has a unique constraint (or
-- equivalent) allowing one row per org — added below if missing, since the
-- upsert relies on it.

begin;

-- One pricing_config row per org — needed for the upsert below. Safe/no-op
-- if it already exists.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'pricing_config_org_id_key'
  ) then
    alter table public.pricing_config
      add constraint pricing_config_org_id_key unique (org_id);
  end if;
end $$;

-- The default seed payload, applied to every org that doesn't already
-- have these specific keys set.
with seed as (
  select '{
    "survey_cats": {
      "Bedrooms": [
        {"name":"Bed","subs":[{"label":"Single","cft":30},{"label":"Double","cft":45},{"label":"Queen Size","cft":55},{"label":"King Size","cft":65}]},
        {"name":"Mattress","subs":[{"label":"Single","cft":12},{"label":"Double","cft":15},{"label":"Queen","cft":18},{"label":"King","cft":20}]},
        {"name":"Wardrobe / Almirah","subs":[{"label":"2 Door","cft":40},{"label":"3 Door","cft":55},{"label":"4 Door","cft":70},{"label":"Sliding","cft":60}]},
        {"name":"Table","subs":[{"label":"Study Table","cft":15},{"label":"Dressing Table","cft":20},{"label":"Bedside Table","cft":8}]},
        {"name":"Chair","subs":[{"label":"1 Chair","cft":5},{"label":"2 Chairs","cft":10},{"label":"Recliner","cft":18}]},
        {"name":"Television","subs":[{"label":"Up to 32\"","cft":8},{"label":"32\"–50\"","cft":12},{"label":"50\"+ LED","cft":16}]},
        {"name":"Air Conditioner","subs":[{"label":"Window AC","cft":15},{"label":"Split AC 1T","cft":10},{"label":"Split AC 1.5T","cft":12},{"label":"Split AC 2T","cft":14}]},
        {"name":"Cabinet & Storage","subs":[{"label":"Small","cft":15},{"label":"Medium","cft":25},{"label":"Large","cft":35}]},
        {"name":"Other Appliances","subs":[{"label":"Item","cft":10}]}
      ],
      "Living Room": [
        {"name":"Sofa","subs":[{"label":"1 Seater","cft":15},{"label":"2 Seater","cft":25},{"label":"3 Seater","cft":35},{"label":"L-Shape","cft":60},{"label":"5 Seater","cft":70}]},
        {"name":"Dining Table","subs":[{"label":"2 Seater","cft":15},{"label":"4 Seater","cft":25},{"label":"6 Seater","cft":35},{"label":"8 Seater","cft":50}]},
        {"name":"Television","subs":[{"label":"Up to 32\"","cft":8},{"label":"32\"–50\"","cft":12},{"label":"50\"+ LED","cft":16}]},
        {"name":"Center Table","subs":[{"label":"Small","cft":8},{"label":"Medium","cft":12},{"label":"Large","cft":18}]},
        {"name":"Chair","subs":[{"label":"1","cft":5},{"label":"2","cft":10},{"label":"4","cft":20}]},
        {"name":"Air Conditioner","subs":[{"label":"Window AC","cft":15},{"label":"Split AC","cft":12}]},
        {"name":"Cabinet / TV Unit","subs":[{"label":"Small","cft":15},{"label":"Medium","cft":25},{"label":"Large","cft":35}]},
        {"name":"Bookshelf","subs":[{"label":"Small","cft":12},{"label":"Medium","cft":20},{"label":"Large","cft":30}]},
        {"name":"Appliances","subs":[{"label":"Item","cft":8}]},
        {"name":"Bar Furniture","subs":[{"label":"Bar Cabinet","cft":25},{"label":"Wine Rack","cft":15}]}
      ],
      "Kitchen": [
        {"name":"Refrigerator","subs":[{"label":"Single Door","cft":15},{"label":"Double Door","cft":20},{"label":"Triple Door","cft":28},{"label":"Side by Side","cft":35}]},
        {"name":"Utensils & Crockery","subs":[{"label":"1 Box","cft":6},{"label":"2 Boxes","cft":12},{"label":"3+ Boxes","cft":18}]},
        {"name":"Gas Stove / Chimney","subs":[{"label":"Gas Stove","cft":6},{"label":"Chimney","cft":10},{"label":"Both","cft":16}]},
        {"name":"Microwave","subs":[{"label":"Small","cft":6},{"label":"Large","cft":10}]},
        {"name":"Mixer / Grinder","subs":[{"label":"1","cft":4},{"label":"2+","cft":8}]},
        {"name":"Kitchen Appliances","subs":[{"label":"Item","cft":5}]},
        {"name":"Kitchen Furniture","subs":[{"label":"Cabinet","cft":20},{"label":"Island","cft":30},{"label":"Dining","cft":25}]}
      ],
      "Miscellaneous": [
        {"name":"Washing Machine","subs":[{"label":"Top Load","cft":15},{"label":"Front Load","cft":18}]},
        {"name":"Decorative Items","subs":[{"label":"Small","cft":5},{"label":"Medium","cft":10},{"label":"Large","cft":20}]},
        {"name":"Suitcases & Bags","subs":[{"label":"1–2","cft":8},{"label":"3–5","cft":16},{"label":"6+","cft":28}]},
        {"name":"Bicycle","subs":[{"label":"Kids","cft":12},{"label":"Adult","cft":18},{"label":"Electric","cft":22}]},
        {"name":"Bike / Two Wheeler","subs":[{"label":"Scooter","cft":25},{"label":"Standard Bike","cft":30},{"label":"Sports Bike","cft":35},{"label":"Electric Bike","cft":28}]},
        {"name":"Musical Instruments","subs":[{"label":"Item","cft":15}]},
        {"name":"Kids Vehicle","subs":[{"label":"Cycle","cft":12},{"label":"Scooter","cft":18},{"label":"Toy Car","cft":10}]},
        {"name":"Gym Equipment","subs":[{"label":"Treadmill","cft":40},{"label":"Weights Set","cft":20},{"label":"Exercise Bike","cft":25},{"label":"Others","cft":15}]},
        {"name":"Home Appliances","subs":[{"label":"Geyser","cft":8},{"label":"Fan","cft":6},{"label":"Iron","cft":3},{"label":"Vacuum Cleaner","cft":8}]},
        {"name":"Plants & Pots","subs":[{"label":"Small (<5)","cft":5},{"label":"Medium (5-10)","cft":12},{"label":"Large (10+)","cft":25}]}
      ],
      "Cartons & Packing": [
        {"name":"Self Carton Large","subs":[{"label":"Qty","cft":6}]},
        {"name":"Self Carton Medium","subs":[{"label":"Qty","cft":4}]},
        {"name":"Self Carton Small","subs":[{"label":"Qty","cft":3}]},
        {"name":"Gunny Bag","subs":[{"label":"Qty","cft":5}]}
      ]
    },
    "cft_ranges": [
      {"max":80,"pkg":"Micro Shifting"},
      {"max":155,"pkg":"1 RK / Studio"},
      {"max":180,"pkg":"1 BHK Small"},
      {"max":250,"pkg":"1 BHK Medium"},
      {"max":275,"pkg":"1 BHK Big"},
      {"max":400,"pkg":"2 BHK Small"},
      {"max":550,"pkg":"2 BHK Medium"},
      {"max":700,"pkg":"2 BHK Big"},
      {"max":900,"pkg":"3 BHK Small"},
      {"max":1050,"pkg":"3 BHK Medium"},
      {"max":1200,"pkg":"3 BHK Big"},
      {"max":1400,"pkg":"4 BHK Small"},
      {"max":1600,"pkg":"4 BHK Medium"},
      {"max":null,"pkg":"4 BHK Big"}
    ],
    "packages": [
      {"type":"Micro Shifting","crew":2,"vehicle":"7 Ft","vehicleCft":161},
      {"type":"1 RK / Studio","crew":2,"vehicle":"7 Ft","vehicleCft":161},
      {"type":"1 BHK Small","crew":3,"vehicle":"8 Ft","vehicleCft":184},
      {"type":"1 BHK Medium","crew":4,"vehicle":"10 Ft","vehicleCft":275},
      {"type":"1 BHK Big","crew":4,"vehicle":"10 Ft","vehicleCft":275},
      {"type":"2 BHK Small","crew":4,"vehicle":"14 Ft","vehicleCft":546},
      {"type":"2 BHK Medium","crew":5,"vehicle":"17 Ft","vehicleCft":714},
      {"type":"2 BHK Big","crew":5,"vehicle":"17 Ft","vehicleCft":714},
      {"type":"3 BHK Small","crew":6,"vehicle":"19 Ft","vehicleCft":931},
      {"type":"3 BHK Medium","crew":6,"vehicle":"19 Ft + 7 Ft","vehicleCft":1092},
      {"type":"3 BHK Big","crew":8,"vehicle":"19 Ft + 10 Ft","vehicleCft":1206},
      {"type":"4 BHK Small","crew":8,"vehicle":"19 Ft + 14 Ft","vehicleCft":1477},
      {"type":"4 BHK Medium","crew":10,"vehicle":"19 Ft + 17 Ft","vehicleCft":1645},
      {"type":"4 BHK Big","crew":10,"vehicle":"19 Ft + 19 Ft","vehicleCft":1862}
    ],
    "porter_rates": {"local":16,"outstation":19},
    "charge_defaults": {
      "billing_mode_keys": ["packing","unpacking","loading","unloading","materials"],
      "default_billing_mode": "included",
      "fields": [
        {"key":"transport","label":"Freight / Transport"},
        {"key":"packing","label":"Packing Charge","billable":true},
        {"key":"unpacking","label":"Un Packing Charge","billable":true},
        {"key":"loading","label":"Loading Charge","billable":true},
        {"key":"unloading","label":"Un Loading Charge","billable":true},
        {"key":"materials","label":"Packing Material Charge","billable":true},
        {"key":"storage","label":"Storage"},
        {"key":"carTransport","label":"Car Transport"},
        {"key":"misc","label":"Miscellaneous"},
        {"key":"stCharge","label":"S.T. Charge"},
        {"key":"otherCharges","label":"Other Charges"},
        {"key":"acUninstall","label":"AC Uninstall"},
        {"key":"acInstall","label":"AC Install"},
        {"key":"tvUninstall","label":"TV Uninstall"},
        {"key":"tvInstall","label":"TV Install"},
        {"key":"wardrobe","label":"Wardrobe Dismantle/Assemble"},
        {"key":"carpenter","label":"Carpenter Charges"},
        {"key":"electrician","label":"Electrician Charges"},
        {"key":"bikeTransport","label":"Bike Transport"},
        {"key":"discount","label":"Discount"},
        {"key":"advanceOnQuote","label":"Advance Paid"}
      ]
    },
    "gst": {"sac":"996719","default_pct":5,"rates":[0,5,12,18]}
  }'::jsonb as defaults
)
insert into public.pricing_config (org_id, config)
select o.id, seed.defaults
from public.organizations o, seed
on conflict (org_id) do update
  -- excluded.config is the seed payload we tried to insert; the org's
  -- pre-existing config (if any) wins on any overlapping key, which is
  -- what keeps a vendor's own edits from being clobbered on re-run.
  set config = excluded.config || coalesce(public.pricing_config.config, '{}'::jsonb);

commit;

-- Verify after running:
--   select org_id, config->'cft_ranges'->0, config->'packages'->0,
--          jsonb_object_keys(config->'charge_defaults')
--   from pricing_config;
