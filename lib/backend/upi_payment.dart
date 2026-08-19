/// Item 19 Phase 1 — UPI collection links.
///
/// Phase 1 is deliberately SMALL: build a raw `upi://pay` URI from the
/// tenant's own VPA and hand it off. No gateway, no hosted pay page, no
/// webhook, no reconciliation. A payment made through one of these links
/// arrives in the vendor's bank account and is invisible to this app
/// until somebody records it in Quick Payment — exactly as a cash or
/// bank transfer is today. Phase 1 shortens the "how do I pay you?"
/// conversation; it does not automate collection.
///
/// **Per-tenant, never global.** The VPA always comes from the signed-in
/// org's own `organizations.upi_id`. There is no app-level fallback and
/// there must never be one — a shared default would route one vendor's
/// customer payments into another vendor's account. Same rule Arun set
/// for Razorpay keys (see CLAUDE.md, Item 19/31): the money leg is the
/// tenant's, always.
///
/// **`upi://` is not a web link.** It resolves only on a device with a
/// UPI app installed, and most chat clients will not linkify a
/// non-http scheme — so a customer on desktop WhatsApp may see plain
/// text rather than something tappable. That limitation is the reason a
/// hosted pay page exists as a later phase; it is not a bug in this one,
/// and the copy shown to the vendor should not promise more than the
/// link can do.
library;

import 'dart:convert';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// A tenant's UPI identity, resolved for the current org.
class UpiPayee {
  const UpiPayee({required this.vpa, required this.name});

  /// The virtual payment address, e.g. `arunpackers@okhdfcbank`.
  final String vpa;

  /// Payee name shown in the customer's UPI app.
  final String name;
}

/// True for something shaped like `name@handle`.
///
/// Deliberately loose: NPCI does not publish an exhaustive handle list
/// and new PSP handles appear regularly, so a strict allow-list would
/// reject valid VPAs and be wrong within months. This catches the real
/// mistakes — a phone number, an email typo'd into the field, empty
/// text — and lets anything plausible through to the UPI app, which is
/// the actual authority on whether an address exists.
bool isPlausibleVpa(String? vpa) {
  final v = (vpa ?? '').trim();
  if (v.isEmpty) return false;
  return RegExp(r'^[a-zA-Z0-9._-]{2,}@[a-zA-Z][a-zA-Z0-9.]{1,}$').hasMatch(v);
}

/// Reads the current org's UPI identity, or null when none is set.
///
/// Mirrors `PdfBranding`'s resolution order (`organizations.upi_id`
/// first, the org's own `settings.business_profile` jsonb as fallback)
/// so the ID a vendor sees on an invoice and the one a customer is
/// asked to pay can never disagree.
Future<UpiPayee?> resolveOrgUpiPayee() async {
  final orgId = OrgScope.currentOrgId;
  if (orgId == null) return null;

  final rows = await OrganizationsTable().queryRows(
    queryFn: (q) => q.eq('id', orgId),
  );
  if (rows.isEmpty) return null;
  final org = rows.first;

  var vpa = (org.upiId ?? '').trim();
  if (vpa.isEmpty) {
    // Older orgs configured before `organizations.upi_id` existed still
    // carry it in the business_profile blob.
    try {
      final s = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'business_profile'),
      );
      if (s.isNotEmpty && (s.first.value ?? '').isNotEmpty) {
        final decoded = jsonDecodeSafe(s.first.value!);
        vpa = '${decoded?['upi_id'] ?? ''}'.trim();
      }
    } catch (_) {}
  }
  if (vpa.isEmpty) return null;

  return UpiPayee(
    vpa: vpa,
    name: org.name.trim().isEmpty ? 'Payee' : org.name.trim(),
  );
}

/// Builds a `upi://pay` URI.
///
/// Every value is percent-encoded through [Uri] rather than string
/// concatenation — an org name with a space or an `&` in the note would
/// otherwise truncate the query and produce a link that either fails or,
/// worse, pays a different amount than intended.
///
/// [amount] is written with exactly two decimals: UPI apps reject `am`
/// values they cannot parse, and a bare `12000.0` is not universally
/// accepted. Pass a non-positive [amount] to omit it entirely, which
/// produces a valid "customer types the amount" link.
String buildUpiUri({
  required String vpa,
  required String payeeName,
  double? amount,
  String? note,
}) {
  final params = <String, String>{
    'pa': vpa.trim(),
    'pn': payeeName.trim(),
    'cu': 'INR',
  };
  if (amount != null && amount > 0) {
    params['am'] = amount.toStringAsFixed(2);
  }
  final tn = (note ?? '').trim();
  if (tn.isNotEmpty) {
    // Transaction notes are short in practice and some PSPs silently
    // truncate; keep it well inside that so the order reference survives.
    params['tn'] = tn.length > 50 ? tn.substring(0, 50) : tn;
  }
  return Uri(scheme: 'upi', host: 'pay', queryParameters: params).toString();
}

/// The message a vendor sends a customer alongside the link.
///
/// Kept here rather than inline at the call site so the wording stays in
/// one place — it is customer-facing text sent under the vendor's name.
String buildUpiRequestMessage({
  required String orgName,
  required String customerName,
  required String orderId,
  required double amount,
  required String vpa,
  required String upiUri,
}) {
  final amt = amount.toStringAsFixed(0);
  return 'Hello $customerName, the balance due on your order $orderId is '
      '₹$amt.\n\nPay by UPI to: $vpa\n\nOr tap to pay on a phone with a '
      'UPI app installed:\n$upiUri\n\n— $orgName';
}

/// Tolerant decode for the `business_profile` blob — a malformed or
/// non-object value reads as "no profile" rather than throwing into a
/// payment flow.
Map<String, dynamic>? jsonDecodeSafe(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}
