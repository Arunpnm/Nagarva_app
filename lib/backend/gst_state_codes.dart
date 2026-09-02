/// City → GST state code lookup, and the interstate test built on it.
///
/// Extracted 29 Jul 2026 because this table existed as TWO private copies
/// — `order_detail_page_widget.dart` (invoice generation) and
/// `survey_quote_page_widget.dart` (quote GST) — and the order snapshot
/// needed a third. They happened to be identical when merged, but nothing
/// kept them that way: a vendor expanding into a new city would have had
/// to find and edit every copy, and a quote and its own invoice
/// disagreeing about IGST vs CGST+SGST is a tax error, not a cosmetic one.
///
/// Ported from apc_webapp App.jsx's STATE_CODES (~lines 506-516). Unknown
/// cities default to Tamil Nadu (33), matching the reference app's own
/// default (its company GSTIN starts with 33).
library;

const Map<String, int> kGstStateCodes = {
  'tamil nadu': 33,
  'chennai': 33,
  'coimbatore': 33,
  'karnataka': 29,
  'bangalore': 29,
  'bengaluru': 29,
  'andhra pradesh': 37,
  'telangana': 36,
  'hyderabad': 36,
  'kerala': 32,
  'maharashtra': 27,
  'mumbai': 27,
  'pune': 27,
  'delhi': 7,
  'haryana': 6,
  'gurgaon': 6,
  'uttar pradesh': 9,
  'noida': 9,
  'gujarat': 24,
  'rajasthan': 8,
  'west bengal': 19,
  'kolkata': 19,
  'madhya pradesh': 23,
  'punjab': 3,
  'odisha': 21,
};

/// Where an unrecognised location lands. Deliberately named rather than
/// repeated as a bare `33`, because "unknown defaults to Tamil Nadu" is a
/// real tax assumption and should be greppable.
const kGstDefaultStateCode = 33;

int gstStateCode(String? city) =>
    kGstStateCodes[(city ?? '').toLowerCase().trim()] ?? kGstDefaultStateCode;

/// Tolerant lookup for a free-text LOCATION - a full postal address, not
/// just a city name.
///
/// [gstStateCode] is an exact map lookup, so it can only ever match a bare
/// city. Callers that hold an address ("12/4 Anna Nagar West, 2nd Floor,
/// Chennai 600040") therefore always fell through to the default, and
/// since BOTH ends fell through, every move read as intra-state - CGST +
/// SGST on a genuinely inter-state consignment. Found live on 2 Sep 2026
/// on a Chennai -> Bengaluru quote; both cities are in the table and the
/// lookup still failed, because it was never given a city.
///
/// Worse, it was inconsistent: a quote built from a LEAD carries city
/// names and taxed correctly, while a quote built from the customer's
/// SURVEY overwrites those with full addresses and taxed wrongly. Better
/// data produced the worse answer.
///
/// Scans for any known city as a substring and takes the LAST match. Indian
/// addresses put the city near the end, so on "Mysore Road, Bengaluru" the
/// later match (Bengaluru) is the destination and the earlier one is a
/// street name. Falls back to [kGstDefaultStateCode] when nothing matches,
/// exactly as before - this widens what can match, it never guesses harder.
int gstStateCodeFromLocation(String? location) {
  final s = (location ?? '').toLowerCase().trim();
  if (s.isEmpty) return kGstDefaultStateCode;

  final exact = kGstStateCodes[s];
  if (exact != null) return exact;

  var bestIndex = -1;
  var bestCode = kGstDefaultStateCode;
  for (final entry in kGstStateCodes.entries) {
    final i = s.lastIndexOf(entry.key);
    if (i > bestIndex) {
      bestIndex = i;
      bestCode = entry.value;
    }
  }
  return bestIndex >= 0 ? bestCode : kGstDefaultStateCode;
}

/// True when the two locations are in different GST states, i.e. IGST
/// applies rather than CGST+SGST.
///
/// Note both unknown cities resolve to 33, so an unrecognised pair reads
/// as INTRA-state. That is the reference app's behaviour and is the safer
/// default for a Tamil Nadu-based vendor, but it is a real limitation:
/// expanding the table is what makes interstate detection correct for a
/// new region.
bool isInterState(String? a, String? b) =>
    gstStateCodeFromLocation(a) != gstStateCodeFromLocation(b);
