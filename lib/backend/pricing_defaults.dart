import 'package:meta/meta.dart';

import '/backend/supabase/supabase.dart';
import '/backend/storage_billing.dart';
import '/backend/supabase/org_scope.dart';

/// Survey/CFT/package/charge data model + defaults (parity brief Part 3,
/// 27-28 Jul 2026). Ported from reference/APC Web App JSX/App.jsx:
/// SURVEY_CATS (~677), DEFAULT_CFT_RANGES (~881), DEFAULT_PACKAGES (~898),
/// DEFAULT_PORTER_RATES (~915), and the charges/chargeTypes shape (~2671,
/// 3175-3223).
///
/// Per the brief's multi-tenancy rule, these constants are only the
/// **fallback** — the real seed lives per-org in `pricing_config.config`
/// (see supabase/20260728_pricing_config_survey_seed.sql). [PricingConfig]
/// reads that row and falls back to these constants key-by-key so a vendor
/// who has never customized anything still gets APC's proven defaults, and
/// one who has customized only `packages` (say) still gets the default
/// `surveyCats` for everything else.
///
/// NOTE: only this data layer + the seed migration were built this pass —
/// no UI consumes it yet (see NAGARVA_STATUS.md for what's still open:
/// the item-counter survey screen, the charges/GST quotation form, and the
/// order-detail breakdown).

class SurveySubItem {
  const SurveySubItem(this.label, this.cft);
  final String label;
  final num cft;
}

class SurveyItem {
  const SurveyItem(this.name, this.subs, {this.active = true});
  final String name;
  final List<SurveySubItem> subs;

  /// Item 12A: deactivating hides an item from NEW surveys but leaves old
  /// quotes intact — quote lines store their CFT at add-time, so a
  /// historical quote never looks its items up again (that lookup was the
  /// original 0-CFT bug). Defaults true so every pre-existing config row,
  /// which has no `active` key at all, keeps working unchanged.
  final bool active;

  SurveyItem copyWith({String? name, List<SurveySubItem>? subs, bool? active}) =>
      SurveyItem(name ?? this.name, subs ?? this.subs,
          active: active ?? this.active);
}

class CftRange {
  const CftRange(this.max, this.pkg);
  final num? max; // null == no upper bound (the reference app's Infinity)
  final String pkg;
}

class PackageInfo {
  const PackageInfo(this.type, this.crew, this.vehicle, this.vehicleCft);
  final String type;
  final int crew;
  final String vehicle;
  final num vehicleCft;
}

/// Item 12B — ONE row of the vendor's "CFT in, vehicle and crew out" table,
/// as the Settings editor presents it.
///
/// The stored shape is still two separate lists (`config.cft_ranges` maps a
/// CFT ceiling to a package NAME; `config.packages` maps that name to crew/
/// vehicle) joined by a free-text string. That join is the structural
/// weakness this type exists to hide: a vendor who renames a package in one
/// list and not the other silently breaks the suggestion (see
/// [suggestPackage], which used to guess instead of reporting it).
/// [CftSlab] is the editor's single source of truth — [PricingConfig.slabs]
/// derives it from both lists and [PricingConfig.slabsToConfig] writes both
/// back atomically, so the two can't drift apart through the UI.
///
/// The jsonb shape was deliberately kept over the relational
/// `cft_slabs`/`survey_catalogue_items` tables the master build brief
/// specifies — see CLAUDE.md's Item 12 entry for the reasoning. Do not
/// "correct" this to tables without reading that first.
class CftSlab {
  const CftSlab({
    required this.cftFrom,
    required this.cftTo,
    required this.packageName,
    required this.vehicle,
    required this.crew,
    required this.vehicleCft,
  });

  /// Inclusive lower bound, as shown in the editor.
  final num cftFrom;

  /// Inclusive upper bound. `null` means open-ended — the top row, which
  /// catches every total above the last real ceiling.
  final num? cftTo;

  final String packageName;
  final String vehicle;
  final int crew;

  /// Carried through from `config.packages[].vehicleCft` so a round-trip
  /// through the editor doesn't drop it. Not exposed in the editor UI —
  /// nothing in the app reads it today (grepped), it's data the reference
  /// web app carried; defaults to [cftTo] for a newly added row.
  final num vehicleCft;

  CftSlab copyWith({
    num? cftFrom,
    num? cftTo,
    bool clearCftTo = false,
    String? packageName,
    String? vehicle,
    int? crew,
    num? vehicleCft,
  }) =>
      CftSlab(
        cftFrom: cftFrom ?? this.cftFrom,
        cftTo: clearCftTo ? null : (cftTo ?? this.cftTo),
        packageName: packageName ?? this.packageName,
        vehicle: vehicle ?? this.vehicle,
        crew: crew ?? this.crew,
        vehicleCft: vehicleCft ?? this.vehicleCft,
      );
}

/// Result of resolving a CFT total against the vendor's slabs.
///
/// Replaces the old `packageInfoForCft`, which returned `packages.first`
/// whenever the range->package join failed. That fallback meant a renamed
/// or deleted package silently suggested the WRONG vehicle and crew on
/// every quote, with nothing anywhere reporting it — the surveyor saw a
/// confident, plausible, incorrect answer. This type forces the caller to
/// distinguish "resolved", "nothing entered yet", and "your configuration
/// is broken", so the last one can be shown as the config error it is.
class PackageSuggestion {
  const PackageSuggestion._(this.info, this.unresolvedPackageName, this.empty);

  /// A real match: CFT fell in a slab and that slab's package resolved.
  const PackageSuggestion.resolved(PackageInfo info) : this._(info, null, false);

  /// CFT fell in a slab, but no `packages` row matches that slab's name —
  /// i.e. the two lists have drifted. Carries the name that didn't resolve
  /// so the UI can name it.
  const PackageSuggestion.unresolved(String packageName)
      : this._(null, packageName, false);

  /// Nothing to suggest yet (no items added, or no slabs configured at
  /// all). Not an error state.
  const PackageSuggestion.empty() : this._(null, null, true);

  final PackageInfo? info;
  final String? unresolvedPackageName;
  final bool empty;

  bool get ok => info != null;

  /// True only for a real misconfiguration — the case worth shouting about.
  bool get isConfigError => unresolvedPackageName != null;
}

/// A billable charge field. [billable] fields are the 5 that have a
/// billing-mode toggle (included-in-freight vs a separate amount) — see
/// chargeTypes in the reference app; everything else is just a plain
/// amount with no toggle.
class ChargeField {
  const ChargeField(this.key, this.label, {this.billable = false});
  final String key;
  final String label;
  final bool billable;
}

const kDefaultSurveyCats = <String, List<SurveyItem>>{
  'Bedrooms': [
    SurveyItem('Bed', [
      SurveySubItem('Single', 30),
      SurveySubItem('Double', 45),
      SurveySubItem('Queen Size', 55),
      SurveySubItem('King Size', 65),
    ]),
    SurveyItem('Mattress', [
      SurveySubItem('Single', 12),
      SurveySubItem('Double', 15),
      SurveySubItem('Queen', 18),
      SurveySubItem('King', 20),
    ]),
    SurveyItem('Wardrobe / Almirah', [
      SurveySubItem('2 Door', 40),
      SurveySubItem('3 Door', 55),
      SurveySubItem('4 Door', 70),
      SurveySubItem('Sliding', 60),
    ]),
    SurveyItem('Table', [
      SurveySubItem('Study Table', 15),
      SurveySubItem('Dressing Table', 20),
      SurveySubItem('Bedside Table', 8),
    ]),
    SurveyItem('Chair', [
      SurveySubItem('1 Chair', 5),
      SurveySubItem('2 Chairs', 10),
      SurveySubItem('Recliner', 18),
    ]),
    SurveyItem('Television', [
      SurveySubItem('Up to 32"', 8),
      SurveySubItem('32"–50"', 12),
      SurveySubItem('50"+ LED', 16),
    ]),
    SurveyItem('Air Conditioner', [
      SurveySubItem('Window AC', 15),
      SurveySubItem('Split AC 1T', 10),
      SurveySubItem('Split AC 1.5T', 12),
      SurveySubItem('Split AC 2T', 14),
    ]),
    SurveyItem('Cabinet & Storage', [
      SurveySubItem('Small', 15),
      SurveySubItem('Medium', 25),
      SurveySubItem('Large', 35),
    ]),
    SurveyItem('Other Appliances', [SurveySubItem('Item', 10)]),
  ],
  'Living Room': [
    SurveyItem('Sofa', [
      SurveySubItem('1 Seater', 15),
      SurveySubItem('2 Seater', 25),
      SurveySubItem('3 Seater', 35),
      SurveySubItem('L-Shape', 60),
      SurveySubItem('5 Seater', 70),
    ]),
    SurveyItem('Dining Table', [
      SurveySubItem('2 Seater', 15),
      SurveySubItem('4 Seater', 25),
      SurveySubItem('6 Seater', 35),
      SurveySubItem('8 Seater', 50),
    ]),
    SurveyItem('Television', [
      SurveySubItem('Up to 32"', 8),
      SurveySubItem('32"–50"', 12),
      SurveySubItem('50"+ LED', 16),
    ]),
    SurveyItem('Center Table', [
      SurveySubItem('Small', 8),
      SurveySubItem('Medium', 12),
      SurveySubItem('Large', 18),
    ]),
    SurveyItem('Chair', [
      SurveySubItem('1', 5),
      SurveySubItem('2', 10),
      SurveySubItem('4', 20),
    ]),
    SurveyItem('Air Conditioner', [
      SurveySubItem('Window AC', 15),
      SurveySubItem('Split AC', 12),
    ]),
    SurveyItem('Cabinet / TV Unit', [
      SurveySubItem('Small', 15),
      SurveySubItem('Medium', 25),
      SurveySubItem('Large', 35),
    ]),
    SurveyItem('Bookshelf', [
      SurveySubItem('Small', 12),
      SurveySubItem('Medium', 20),
      SurveySubItem('Large', 30),
    ]),
    SurveyItem('Appliances', [SurveySubItem('Item', 8)]),
    SurveyItem('Bar Furniture', [
      SurveySubItem('Bar Cabinet', 25),
      SurveySubItem('Wine Rack', 15),
    ]),
  ],
  'Kitchen': [
    SurveyItem('Refrigerator', [
      SurveySubItem('Single Door', 15),
      SurveySubItem('Double Door', 20),
      SurveySubItem('Triple Door', 28),
      SurveySubItem('Side by Side', 35),
    ]),
    SurveyItem('Utensils & Crockery', [
      SurveySubItem('1 Box', 6),
      SurveySubItem('2 Boxes', 12),
      SurveySubItem('3+ Boxes', 18),
    ]),
    SurveyItem('Gas Stove / Chimney', [
      SurveySubItem('Gas Stove', 6),
      SurveySubItem('Chimney', 10),
      SurveySubItem('Both', 16),
    ]),
    SurveyItem('Microwave', [
      SurveySubItem('Small', 6),
      SurveySubItem('Large', 10),
    ]),
    SurveyItem('Mixer / Grinder', [
      SurveySubItem('1', 4),
      SurveySubItem('2+', 8),
    ]),
    SurveyItem('Kitchen Appliances', [SurveySubItem('Item', 5)]),
    SurveyItem('Kitchen Furniture', [
      SurveySubItem('Cabinet', 20),
      SurveySubItem('Island', 30),
      SurveySubItem('Dining', 25),
    ]),
  ],
  'Miscellaneous': [
    SurveyItem('Washing Machine', [
      SurveySubItem('Top Load', 15),
      SurveySubItem('Front Load', 18),
    ]),
    SurveyItem('Decorative Items', [
      SurveySubItem('Small', 5),
      SurveySubItem('Medium', 10),
      SurveySubItem('Large', 20),
    ]),
    SurveyItem('Suitcases & Bags', [
      SurveySubItem('1–2', 8),
      SurveySubItem('3–5', 16),
      SurveySubItem('6+', 28),
    ]),
    SurveyItem('Bicycle', [
      SurveySubItem('Kids', 12),
      SurveySubItem('Adult', 18),
      SurveySubItem('Electric', 22),
    ]),
    SurveyItem('Bike / Two Wheeler', [
      SurveySubItem('Scooter', 25),
      SurveySubItem('Standard Bike', 30),
      SurveySubItem('Sports Bike', 35),
      SurveySubItem('Electric Bike', 28),
    ]),
    SurveyItem('Musical Instruments', [SurveySubItem('Item', 15)]),
    SurveyItem('Kids Vehicle', [
      SurveySubItem('Cycle', 12),
      SurveySubItem('Scooter', 18),
      SurveySubItem('Toy Car', 10),
    ]),
    SurveyItem('Gym Equipment', [
      SurveySubItem('Treadmill', 40),
      SurveySubItem('Weights Set', 20),
      SurveySubItem('Exercise Bike', 25),
      SurveySubItem('Others', 15),
    ]),
    SurveyItem('Home Appliances', [
      SurveySubItem('Geyser', 8),
      SurveySubItem('Fan', 6),
      SurveySubItem('Iron', 3),
      SurveySubItem('Vacuum Cleaner', 8),
    ]),
    SurveyItem('Plants & Pots', [
      SurveySubItem('Small (<5)', 5),
      SurveySubItem('Medium (5-10)', 12),
      SurveySubItem('Large (10+)', 25),
    ]),
  ],
  'Cartons & Packing': [
    SurveyItem('Self Carton Large', [SurveySubItem('Qty', 6)]),
    SurveyItem('Self Carton Medium', [SurveySubItem('Qty', 4)]),
    SurveyItem('Self Carton Small', [SurveySubItem('Qty', 3)]),
    SurveyItem('Gunny Bag', [SurveySubItem('Qty', 5)]),
  ],
};

const kDefaultCftRanges = <CftRange>[
  CftRange(80, 'Micro Shifting'),
  CftRange(155, '1 RK / Studio'),
  CftRange(180, '1 BHK Small'),
  CftRange(250, '1 BHK Medium'),
  CftRange(275, '1 BHK Big'),
  CftRange(400, '2 BHK Small'),
  CftRange(550, '2 BHK Medium'),
  CftRange(700, '2 BHK Big'),
  CftRange(900, '3 BHK Small'),
  CftRange(1050, '3 BHK Medium'),
  CftRange(1200, '3 BHK Big'),
  CftRange(1400, '4 BHK Small'),
  CftRange(1600, '4 BHK Medium'),
  CftRange(null, '4 BHK Big'),
];

const kDefaultPackages = <PackageInfo>[
  PackageInfo('Micro Shifting', 2, '7 Ft', 161),
  PackageInfo('1 RK / Studio', 2, '7 Ft', 161),
  PackageInfo('1 BHK Small', 3, '8 Ft', 184),
  PackageInfo('1 BHK Medium', 4, '10 Ft', 275),
  PackageInfo('1 BHK Big', 4, '10 Ft', 275),
  PackageInfo('2 BHK Small', 4, '14 Ft', 546),
  PackageInfo('2 BHK Medium', 5, '17 Ft', 714),
  PackageInfo('2 BHK Big', 5, '17 Ft', 714),
  PackageInfo('3 BHK Small', 6, '19 Ft', 931),
  PackageInfo('3 BHK Medium', 6, '19 Ft + 7 Ft', 1092),
  PackageInfo('3 BHK Big', 8, '19 Ft + 10 Ft', 1206),
  PackageInfo('4 BHK Small', 8, '19 Ft + 14 Ft', 1477),
  PackageInfo('4 BHK Medium', 10, '19 Ft + 17 Ft', 1645),
  PackageInfo('4 BHK Big', 10, '19 Ft + 19 Ft', 1862),
];

const kDefaultPorterRates = {'local': 16, 'outstation': 19};

/// billable == true fields default to 'included' (bundled into freight);
/// all others are just a plain amount with no billing-mode toggle.
const kDefaultChargeFields = <ChargeField>[
  ChargeField('transport', 'Freight / Transport'),
  ChargeField('packing', 'Packing Charge', billable: true),
  ChargeField('unpacking', 'Un Packing Charge', billable: true),
  ChargeField('loading', 'Loading Charge', billable: true),
  ChargeField('unloading', 'Un Loading Charge', billable: true),
  ChargeField('materials', 'Packing Material Charge', billable: true),
  ChargeField('storage', 'Storage'),
  ChargeField('carTransport', 'Car Transport'),
  ChargeField('misc', 'Miscellaneous'),
  ChargeField('stCharge', 'S.T. Charge'),
  ChargeField('otherCharges', 'Other Charges'),
  ChargeField('acUninstall', 'AC Uninstall'),
  ChargeField('acInstall', 'AC Install'),
  ChargeField('tvUninstall', 'TV Uninstall'),
  ChargeField('tvInstall', 'TV Install'),
  ChargeField('wardrobe', 'Wardrobe Dismantle/Assemble'),
  ChargeField('carpenter', 'Carpenter Charges'),
  ChargeField('electrician', 'Electrician Charges'),
  ChargeField('bikeTransport', 'Bike Transport'),
  ChargeField('discount', 'Discount'),
  ChargeField('advanceOnQuote', 'Advance Paid'),
];

/// Part 8 Rev B, item 4: how a charge line is priced — per-org
/// configurable (`pricing_config.config['charge_basis']`), never
/// hardcoded per key. Only the 6 keys that are real fields in
/// [kDefaultChargeFields] today get a basis; the other 3 named in the
/// Rev A brief's Item 4 table (rearrangement, toll/parking/octroi,
/// insurance) aren't charge fields in this app yet, so they're seeded in
/// pricing_config for forward-compatibility (see
/// supabase/20260801_pricing_config_charge_basis.sql) but have no UI here.
const kChargeBasisOptions = [
  'lumpsum',
  'per_cft',
  'per_floor',
  'per_trip',
  'per_km',
  'percent_of_declared_value',
  'at_actuals',
];

const kChargeBasisLabels = {
  'lumpsum': 'Lumpsum',
  'per_cft': 'Per CFT',
  'per_floor': 'Per Floor',
  'per_trip': 'Per Trip',
  'per_km': 'Per KM',
  'percent_of_declared_value': '% of Declared Value',
  'at_actuals': 'At Actuals',
};

/// Mirrors the SQL migration's default map exactly — matches this app's
/// ACTUAL current behaviour (e.g. no per-km field anywhere, so transport
/// defaults to lumpsum, not per_km, unlike the reference APC web app).
const kDefaultChargeBasis = <String, String>{
  'packing': 'per_cft',
  'loading': 'lumpsum',
  'transport': 'lumpsum',
  'unloading': 'lumpsum',
  'unpacking': 'per_cft',
  'rearrangement': 'lumpsum',
  'materials': 'at_actuals',
  'toll_parking_octroi': 'at_actuals',
  'insurance': 'percent_of_declared_value',
};

/// GST is fixed to SAC 996719 per the brief; rate is selectable from
/// these options (matches the reference app's <select>).
const kGstSac = '996719';
const kGstRateOptions = [0, 5, 12, 18];
// 18% is the rate for full-service shifting under SAC 996719, which is
// what this product bills. 5% is the GTA-without-ITC rate and was
// inherited by accident, not chosen: APC's own live invoices bill
// CGST 9% + SGST 9%, so every invoice generated at 5% understated the
// tax against how the business actually bills (2 Sep 2026).
// NAGARVA_GST_SPEC.md sec 4 asked for this to be decided deliberately
// rather than inherited. Per-quote overrides are unaffected - this is
// only the value a NEW quote opens on.
const kGstDefaultPct = 18;

/// Total CFT -> package name, using the *lowest* matching range (mirrors
/// `getPkgFromCft`'s `CFT_RANGES.find(r => cft <= r.max)` — Array.find
/// returns the FIRST match, i.e. the smallest range whose max the total
/// still fits under). Returns null when no range matches AND none is
/// open-ended (a gap at the top — validation prevents saving that shape,
/// but a hand-edited config can still contain it).
String? packageNameForCft(num totalCft, List<CftRange> ranges) {
  for (final r in ranges) {
    if (r.max == null || totalCft <= r.max!) return r.pkg;
  }
  return null;
}

/// Item 12B-b: the honest replacement for the old `packageInfoForCft`,
/// which fell back to `packages.first` when the range->package join
/// failed — a renamed package silently suggested the wrong vehicle/crew
/// on every quote, and nothing errored. See [PackageSuggestion].
PackageSuggestion suggestPackage(
    num totalCft, List<CftRange> ranges, List<PackageInfo> packages) {
  if (totalCft <= 0 || ranges.isEmpty) return const PackageSuggestion.empty();
  final name = packageNameForCft(totalCft, ranges);
  if (name == null) {
    // No matching range and no open-ended top row: a config gap. Report
    // it as such rather than inventing an answer.
    return const PackageSuggestion.unresolved('(no matching CFT slab)');
  }
  for (final p in packages) {
    if (p.type == name) return PackageSuggestion.resolved(p);
  }
  return PackageSuggestion.unresolved(name);
}

/// DEPRECATED shim for remaining callers (survey PDF, survey response
/// section) that only ever render "no suggestion" for null — for those,
/// showing nothing on a config error is acceptable; the interactive quote
/// screen uses [suggestPackage] directly and surfaces the error. Do not
/// use in new code.
PackageInfo? packageInfoForCft(
    num totalCft, List<CftRange> ranges, List<PackageInfo> packages) {
  return suggestPackage(totalCft, ranges, packages).info;
}

/// Item 12B — outcome of validating an edited slab table before save.
class SlabValidationError {
  const SlabValidationError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Validate a slab table the way the editor presents it. Returns the
/// errors found (empty list == valid). Rules, per the master brief's 12B:
/// ranges must not overlap, must not leave gaps, exactly one open-ended
/// top row, no duplicate package names, every field filled in. "An
/// unmatched CFT silently producing no suggestion is the same class of
/// bug as the 0-CFT one — fail loudly at config time, not quietly at
/// quote time."
List<SlabValidationError> validateSlabs(List<CftSlab> slabs) {
  final errors = <SlabValidationError>[];
  if (slabs.isEmpty) {
    return [const SlabValidationError('Add at least one slab.')];
  }

  final sorted = List.of(slabs)..sort((a, b) => a.cftFrom.compareTo(b.cftFrom));

  for (final s in sorted) {
    if (s.packageName.trim().isEmpty) {
      errors.add(SlabValidationError(
          'A slab starting at ${s.cftFrom} CFT has no package name.'));
    }
    if (s.vehicle.trim().isEmpty) {
      errors.add(SlabValidationError(
          '"${s.packageName}" has no vehicle.'));
    }
    if (s.crew <= 0) {
      errors.add(SlabValidationError(
          '"${s.packageName}" needs a crew count of at least 1.'));
    }
    if (s.cftTo != null && s.cftTo! < s.cftFrom) {
      errors.add(SlabValidationError(
          '"${s.packageName}": To CFT (${s.cftTo}) is below From CFT (${s.cftFrom}).'));
    }
  }

  final openEnded = sorted.where((s) => s.cftTo == null).toList();
  if (openEnded.isEmpty) {
    errors.add(const SlabValidationError(
        'The last slab must be open-ended (no To CFT) so every total gets a '
        'suggestion.'));
  } else if (openEnded.length > 1) {
    errors.add(SlabValidationError(
        'Only the last slab can be open-ended — found ${openEnded.length} '
        '(${openEnded.map((s) => s.packageName).join(', ')}).'));
  } else if (openEnded.single.cftFrom != sorted.last.cftFrom) {
    errors.add(SlabValidationError(
        'The open-ended slab ("${openEnded.single.packageName}") must be the '
        'highest range.'));
  }

  final names = <String>{};
  for (final s in sorted) {
    final n = s.packageName.trim().toLowerCase();
    if (n.isNotEmpty && !names.add(n)) {
      errors.add(SlabValidationError(
          'Two slabs share the package name "${s.packageName}".'));
    }
  }

  // Overlap/gap check between consecutive rows. Ranges are inclusive on
  // both ends (matching `cft <= max` resolution), so row N+1 must start
  // at exactly row N's ceiling + 1.
  for (var i = 0; i < sorted.length - 1; i++) {
    final a = sorted[i];
    final b = sorted[i + 1];
    if (a.cftTo == null) continue; // already reported above
    final expectedNext = a.cftTo! + 1;
    if (b.cftFrom < expectedNext) {
      errors.add(SlabValidationError(
          '"${a.packageName}" (up to ${a.cftTo}) overlaps '
          '"${b.packageName}" (from ${b.cftFrom}).'));
    } else if (b.cftFrom > expectedNext) {
      errors.add(SlabValidationError(
          'Gap between "${a.packageName}" (up to ${a.cftTo}) and '
          '"${b.packageName}" (from ${b.cftFrom}) — CFT totals of '
          '${a.cftTo! + 1}–${b.cftFrom - 1} would get no suggestion.'));
    }
  }

  if (sorted.first.cftFrom > 0) {
    errors.add(SlabValidationError(
        'The first slab starts at ${sorted.first.cftFrom} CFT — totals below '
        'that would get no suggestion. Start it at 0.'));
  }

  return errors;
}

/// Loads the current org's `pricing_config.config` and exposes each
/// section, falling back to the Dart defaults above key-by-key (not
/// row-by-row) so a partial vendor customization doesn't lose the rest of
/// APC's proven defaults.
class PricingConfig {
  PricingConfig._({
    required this.surveyCats,
    required this.cftRanges,
    required this.packages,
    required this.porterRates,
    required this.chargeBasis,
    required this.storageRates,
  });

  final Map<String, List<SurveyItem>> surveyCats;

  /// Item 12A — [surveyCats] with deactivated items dropped, and any
  /// category left empty by that filtering dropped too.
  ///
  /// Use this for the survey item PICKER. Do NOT use it when resolving an
  /// item that's already on a quote or a submitted survey — a hidden item
  /// must still reconcile correctly there, which is why [surveyCats]
  /// stays available unfiltered.
  Map<String, List<SurveyItem>> get activeSurveyCats {
    final out = <String, List<SurveyItem>>{};
    for (final e in surveyCats.entries) {
      final live = e.value.where((i) => i.active).toList();
      if (live.isNotEmpty) out[e.key] = live;
    }
    return out;
  }
  final List<CftRange> cftRanges;
  final List<PackageInfo> packages;
  final Map<String, num> porterRates;

  /// Storage sizes and their rates, as THIS org configured them.
  ///
  /// Empty for an org that has not set any, and there is deliberately no
  /// Dart fallback: shipping a rate table would pre-fill one vendor's
  /// prices as another's. See "No suggested money. Ever." in CLAUDE.md.
  final List<StorageSizeRate> storageRates;

  /// Item 12B — the two stored lists joined into the editor's unified
  /// row shape. The join is by package name, same as [suggestPackage];
  /// a range whose package is missing still yields a row (vehicle/crew
  /// blank-ish defaults) so the editor SHOWS the broken join instead of
  /// hiding the row — the vendor fixes it by filling the fields in.
  List<CftSlab> get slabs {
    final byName = {for (final p in packages) p.type: p};
    final out = <CftSlab>[];
    num from = 0;
    for (final r in cftRanges) {
      final p = byName[r.pkg];
      out.add(CftSlab(
        cftFrom: from,
        cftTo: r.max,
        packageName: r.pkg,
        vehicle: p?.vehicle ?? '',
        crew: p?.crew ?? 0,
        vehicleCft: p?.vehicleCft ?? (r.max ?? from),
      ));
      if (r.max != null) from = r.max! + 1;
    }
    return out;
  }

  /// Item 12B — the inverse of [slabs]: one edited table back into the
  /// two stored lists, written together in one config update so they
  /// can't drift. Caller is responsible for running [validateSlabs]
  /// first; this throws (rather than quietly writing a broken config) if
  /// handed an invalid table, as a second line of defense.
  static Map<String, dynamic> slabsToConfig(List<CftSlab> slabs) {
    final errors = validateSlabs(slabs);
    if (errors.isNotEmpty) {
      throw StateError('Invalid slabs: ${errors.first}');
    }
    final sorted = List.of(slabs)
      ..sort((a, b) => a.cftFrom.compareTo(b.cftFrom));
    return {
      'cft_ranges': [
        for (final s in sorted) {'max': s.cftTo, 'pkg': s.packageName.trim()},
      ],
      'packages': [
        for (final s in sorted)
          {
            'type': s.packageName.trim(),
            'crew': s.crew,
            'vehicle': s.vehicle.trim(),
            'vehicleCft': s.vehicleCft,
          },
      ],
    };
  }

  /// Part 8 Rev B item 4. Unlike the other sections, this merges key by
  /// key against [kDefaultChargeBasis] even when the org HAS a
  /// `charge_basis` entry — a vendor who has only customized `packing` in
  /// Settings must not lose sensible defaults for every other key, same
  /// reasoning as the whole-section fallback above but one level deeper.
  final Map<String, String> chargeBasis;

  /// Build a config in memory, for tests only — [loadForCurrentOrg] needs
  /// a Supabase session and a live org. Unspecified sections fall back to
  /// the same Dart defaults the real loader uses.
  @visibleForTesting
  static PricingConfig forTest({
    Map<String, List<SurveyItem>>? surveyCats,
    List<CftRange>? cftRanges,
    List<PackageInfo>? packages,
    List<StorageSizeRate>? storageRates,
  }) =>
      PricingConfig._(
        surveyCats: surveyCats ?? kDefaultSurveyCats,
        cftRanges: cftRanges ?? kDefaultCftRanges,
        packages: packages ?? kDefaultPackages,
        porterRates: kDefaultPorterRates,
        chargeBasis: kDefaultChargeBasis,
        storageRates: storageRates ?? const [],
      );

  static Future<PricingConfig> loadForCurrentOrg() async {
    final rows = await PricingConfigTable().queryRows(
      queryFn: (q) => OrgScope.read(q).limit(1),
    );
    final config = rows.isNotEmpty ? rows.first.config : null;
    if (config is! Map) {
      return PricingConfig._(
        surveyCats: kDefaultSurveyCats,
        cftRanges: kDefaultCftRanges,
        packages: kDefaultPackages,
        porterRates: kDefaultPorterRates,
        chargeBasis: kDefaultChargeBasis,
        // No org config at all - so certainly no agreed storage prices.
        storageRates: const [],
      );
    }
    return PricingConfig._(
      surveyCats: _parseSurveyCats(config['survey_cats']) ?? kDefaultSurveyCats,
      cftRanges: _parseCftRanges(config['cft_ranges']) ?? kDefaultCftRanges,
      packages: _parsePackages(config['packages']) ?? kDefaultPackages,
      porterRates: _parsePorterRates(config['porter_rates']) ??
          kDefaultPorterRates,
      chargeBasis: _parseChargeBasis(config['charge_basis']),
      // No `?? kDefault...` here on purpose - absent means the vendor has
      // not set their prices, not that they inherit somebody else's.
      storageRates: parseStorageRates(config['storage_rates']),
    );
  }

  /// Merge [keys] into the current org's `pricing_config.config`,
  /// preserving every other key (read-merge-write, same pattern the
  /// Survey & Quote hub's catalogue save used before it moved to
  /// Settings). Inserts the row if the org somehow has none — possible
  /// for orgs created before create_org_with_owner() started seeding it.
  static Future<void> saveConfigKeys(Map<String, dynamic> keys) async {
    final existing = await PricingConfigTable().queryRows(
      queryFn: (q) => OrgScope.read(q).limit(1),
    );
    final current = existing.isNotEmpty && existing.first.config is Map
        ? Map<String, dynamic>.from(existing.first.config as Map)
        : <String, dynamic>{};
    current.addAll(keys);
    if (existing.isNotEmpty) {
      await PricingConfigTable().update(
        data: {'config': current},
        matchingRows: (q) => OrgScope.write(q).eq('id', existing.first.id!),
      );
    } else {
      await PricingConfigTable().insert({
        ...OrgScope.stamp(),
        'config': current,
      });
    }
  }

  static Map<String, String> _parseChargeBasis(dynamic raw) {
    final merged = Map<String, String>.from(kDefaultChargeBasis);
    if (raw is Map) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is String && kChargeBasisOptions.contains(value)) {
          merged[entry.key.toString()] = value;
        }
      }
    }
    return merged;
  }

  static Map<String, List<SurveyItem>>? _parseSurveyCats(dynamic raw) {
    if (raw is! Map) return null;
    try {
      return raw.map((cat, items) => MapEntry(
            cat.toString(),
            (items as List)
                .map((i) => SurveyItem(
                      i['name'] as String,
                      (i['subs'] as List)
                          .map((s) => SurveySubItem(
                              s['label'] as String, s['cft'] as num))
                          .toList(),
                      // Item 12A. Absent key == active, so configs written
                      // before this field existed stay fully visible.
                      active: i['active'] != false,
                    ))
                .toList(),
          ));
    } catch (_) {
      return null;
    }
  }

  static List<CftRange>? _parseCftRanges(dynamic raw) {
    if (raw is! List) return null;
    try {
      return raw
          .map((r) => CftRange(r['max'] as num?, r['pkg'] as String))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static List<PackageInfo>? _parsePackages(dynamic raw) {
    if (raw is! List) return null;
    try {
      return raw
          .map((p) => PackageInfo(p['type'] as String, p['crew'] as int,
              p['vehicle'] as String, p['vehicleCft'] as num))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Map<String, num>? _parsePorterRates(dynamic raw) {
    if (raw is! Map) return null;
    try {
      return raw.map((k, v) => MapEntry(k.toString(), v as num));
    } catch (_) {
      return null;
    }
  }
}
