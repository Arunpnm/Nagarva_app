import '/backend/supabase/supabase.dart';
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
  const SurveyItem(this.name, this.subs);
  final String name;
  final List<SurveySubItem> subs;
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

/// GST is fixed to SAC 996719 per the brief; rate is selectable from
/// these options (matches the reference app's <select>).
const kGstSac = '996719';
const kGstRateOptions = [0, 5, 12, 18];
const kGstDefaultPct = 5;

/// Total CFT -> package name, using the *lowest* matching range (mirrors
/// `getPkgFromCft`'s `CFT_RANGES.find(r => cft <= r.max)` — Array.find
/// returns the FIRST match, i.e. the smallest range whose max the total
/// still fits under).
String packageNameForCft(num totalCft, List<CftRange> ranges) {
  for (final r in ranges) {
    if (r.max == null || totalCft <= r.max!) return r.pkg;
  }
  return ranges.isNotEmpty ? ranges.last.pkg : '4 BHK Big';
}

PackageInfo? packageInfoForCft(
    num totalCft, List<CftRange> ranges, List<PackageInfo> packages) {
  final name = packageNameForCft(totalCft, ranges);
  for (final p in packages) {
    if (p.type == name) return p;
  }
  return packages.isNotEmpty ? packages.first : null;
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
  });

  final Map<String, List<SurveyItem>> surveyCats;
  final List<CftRange> cftRanges;
  final List<PackageInfo> packages;
  final Map<String, num> porterRates;

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
      );
    }
    return PricingConfig._(
      surveyCats: _parseSurveyCats(config['survey_cats']) ?? kDefaultSurveyCats,
      cftRanges: _parseCftRanges(config['cft_ranges']) ?? kDefaultCftRanges,
      packages: _parsePackages(config['packages']) ?? kDefaultPackages,
      porterRates: _parsePorterRates(config['porter_rates']) ??
          kDefaultPorterRates,
    );
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
