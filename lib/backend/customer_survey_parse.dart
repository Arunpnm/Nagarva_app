/// Parsing helpers for `customer_surveys` (Session 4, Part B1).
///
/// Deliberately separate from survey_response_section.dart's
/// parseSurveyRooms() — that parses `surveys.rooms` (a flat array of
/// {cat,item,sub,cft,qty} entries, a different table with a different
/// shape). `customer_surveys.items` is a flat jsonb OBJECT of
/// {itemKey: qty}, with no room/category grouping and no per-item CFT
/// (total_cft is precomputed and stored separately) — so there is no
/// "room-by-room" structure in this data to render, despite the kickoff
/// brief describing the detail view that way. Rendered as a flat item
/// list instead of inventing groupings the data doesn't have.
library;

/// One entry from `items` — a humanized label (best-effort: there is no
/// catalogue anywhere in this app mapping keys like "tvLarge"/"centerTbl"
/// to display names, since these keys belong to a different, older survey
/// system than pricing_config's own catalogue) plus its quantity.
class CustomerSurveyItemLine {
  const CustomerSurveyItemLine(this.key, this.label, this.qty);
  final String key;
  final String label;
  final num qty;
}

String humanizeItemKey(String key) {
  // camelCase / snake_case -> "Title Case With Spaces". Best-effort only —
  // "tvLarge" -> "Tv Large", "centerTbl" -> "Center Tbl". No canonical
  // label catalogue exists for these keys anywhere in this app.
  final spaced = key
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ');
  return spaced
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// `items`: jsonb object {itemKey: qty}. Tolerant of qty arriving as a
/// string (jsonb round-trips aren't always strictly typed — same caution
/// this app already applies to survey_quote's own parsing).
List<CustomerSurveyItemLine> parseCustomerSurveyItems(dynamic items) {
  if (items is! Map) return const [];
  final out = <CustomerSurveyItemLine>[];
  items.forEach((k, v) {
    final key = k.toString();
    final qty = v is num ? v : num.tryParse('$v');
    if (qty != null && qty > 0) {
      out.add(CustomerSurveyItemLine(key, humanizeItemKey(key), qty));
    }
  });
  out.sort((a, b) => a.label.compareTo(b.label));
  return out;
}

/// `custom_items`: jsonb array, shape unverified against live data (every
/// row seen so far has it empty). Each entry is expected to be an object;
/// read defensively across a few plausible key names rather than assuming
/// one, and skip anything that doesn't parse as a name+qty pair.
List<CustomerSurveyItemLine> parseCustomItems(dynamic customItems) {
  if (customItems is! List) return const [];
  final out = <CustomerSurveyItemLine>[];
  for (final raw in customItems) {
    if (raw is! Map) continue;
    final name = (raw['name'] ?? raw['label'] ?? raw['item'])?.toString();
    if (name == null || name.trim().isEmpty) continue;
    final rawQty = raw['qty'] ?? raw['quantity'] ?? 1;
    final qty = rawQty is num ? rawQty : num.tryParse('$rawQty') ?? 1;
    out.add(CustomerSurveyItemLine('custom:$name', name.trim(), qty));
  }
  return out;
}

/// `photos`: jsonb object {roomName: [dataUri, dataUri, ...]}. Returns a
/// flat list of (roomName, dataUri) pairs, dropping anything that isn't
/// a string starting with "data:" (the only shape confirmed live).
List<(String room, String dataUri)> parseCustomerSurveyPhotos(dynamic photos) {
  if (photos is! Map) return const [];
  final out = <(String, String)>[];
  photos.forEach((room, list) {
    if (list is! List) return;
    for (final p in list) {
      if (p is String && p.startsWith('data:')) {
        out.add((room.toString(), p));
      }
    }
  });
  return out;
}

/// "" / "Ground" / "yes" / "no" — from_floor/from_lift/to_floor/to_lift
/// are all TEXT. Renders the raw value, or a dash when blank — never
/// parsed as int/bool.
String displayOrDash(String? v) => (v == null || v.trim().isEmpty) ? '—' : v.trim();
