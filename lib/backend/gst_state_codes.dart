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

int gstStateCode(String? city) =>
    kGstStateCodes[(city ?? '').toLowerCase().trim()] ?? 33;

/// True when the two locations are in different GST states, i.e. IGST
/// applies rather than CGST+SGST.
///
/// Note both unknown cities resolve to 33, so an unrecognised pair reads
/// as INTRA-state. That is the reference app's behaviour and is the safer
/// default for a Tamil Nadu-based vendor, but it is a real limitation:
/// expanding the table is what makes interstate detection correct for a
/// new region.
bool isInterState(String? a, String? b) => gstStateCode(a) != gstStateCode(b);
