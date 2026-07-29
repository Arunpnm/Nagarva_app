import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/pricing_defaults.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Itemized quotation breakdown, embedded in Order Details (parity brief
/// Part 3e — "an order shows a bare total with no itemisation... the
/// single most-requested gap from the phone test").
///
/// Additive and read-only: fetches the order's linked `quotations` row (if
/// any — orders created before Part 3, or converted from the plain
/// lead-convert path rather than a quote, won't have one) and renders its
/// `items`/`charges` jsonb exactly as SurveyQuotePageWidget wrote them.
/// Doesn't touch any of OrderDetailPage's own state/params.
class QuotationBreakdownSection extends StatefulWidget {
  const QuotationBreakdownSection({super.key, required this.orderId});

  final String orderId;

  @override
  State<QuotationBreakdownSection> createState() =>
      QuotationBreakdownSectionState();
}

/// Counts persisted lines with cft <= 0. Tolerates cft arriving as a num
/// or a string, since jsonb round-trips have produced both.
int _zeroCftCount(List<dynamic> items) {
  var n = 0;
  for (final raw in items) {
    if (raw is! Map) continue;
    final v = raw['cft'];
    final cft = v is num ? v : num.tryParse('$v');
    // A line with no cft key at all predates the field entirely — don't
    // flag it as a zero, it just wasn't recorded.
    if (v != null && (cft == null || cft <= 0)) n++;
  }
  return n;
}

class QuotationBreakdownSectionState
    extends State<QuotationBreakdownSection> {
  QuotationsRow? _quotation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Public so OrderDetailPage's onPageRefresh can re-pull the linked
  /// quote — item 2's refresh-after-write. A fresh conversion pushes a
  /// new page so initState covers that case, but editing the quote and
  /// coming back needs this.
  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final orders = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId),
      );
      final quotationId = orders.isNotEmpty ? orders.first.quotationId : null;
      if (quotationId != null) {
        final quotes = await QuotationsTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('id', quotationId),
        );
        _quotation = quotes.isNotEmpty ? quotes.first : null;
      }
    } catch (_) {
      // Read-only supplemental section — a failure here shouldn't block
      // the rest of Order Details from rendering.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _quotation == null) return const SizedBox.shrink();
    final theme = FlutterFlowTheme.of(context);
    final q = _quotation!;
    final items = (q.items is List) ? q.items as List : const [];
    final charges = (q.charges is Map)
        ? Map<String, dynamic>.from(q.charges as Map)
        : <String, dynamic>{};

    // Carries the charge KEY as well as label+amount, so the billing
    // mode (included / additional) can be resolved per line below.
    final chargeLines = <(String, num, String)>[];
    for (final f in kDefaultChargeFields) {
      final v = charges[f.key];
      if (v is num && v > 0) chargeLines.add((f.label, v, f.key));
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quotation Breakdown',
              style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: theme.primary)),
          const SizedBox(height: 10),
          // Item 2: this used to print only a COUNT ("3 item line(s)"),
          // which is why a converted order looked like it had lost the
          // quote's detail — the data was linked and present, just never
          // rendered. Now every line shows with the CFT it was actually
          // quoted at (stored per line since the 28 Jul CFT fix, so a
          // later catalogue edit can't rewrite history).
          if (items.isNotEmpty) ...[
            Row(
              children: [
                Text('Items',
                    style: GoogleFonts.interTight(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: theme.primaryText)),
                const Spacer(),
                Text(
                  '${items.length} line(s)'
                  '${charges['_totalCft'] != null ? ' · ${charges['_totalCft']} CFT' : ''}',
                  style: GoogleFonts.inter(
                      fontSize: 11.5, color: theme.secondaryText),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final raw in items)
              if (raw is Map) _itemLine(theme, Map<String, dynamic>.from(raw)),
            const SizedBox(height: 10),
          ],
          // Packing / suggested package, and the crew+vehicle it implies.
          if ((charges['_suggestedPackage'] ?? '').toString().isNotEmpty) ...[
            _kv(theme, 'Package', '${charges['_suggestedPackage']}'),
            const SizedBox(height: 6),
          ],
          // Flags quotes saved before the 28 Jul 2026 custom-item CFT fix,
          // where a line persisted with cft 0 and so contributed nothing
          // to the CFT total — making the suggested package and vehicle
          // too small. Read-only warning: nothing is rewritten, because
          // the intended CFT for a one-off item can't be inferred after
          // the fact. See supabase/diagnostics_zero_cft_quotes.sql.
          if (_zeroCftCount(items) > 0) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.warning.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 17, color: theme.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_zeroCftCount(items)} item line(s) on this quote have '
                      'no CFT, so the total CFT and suggested vehicle may be '
                      'under-sized. Re-quote before dispatch if it matters.',
                      style: GoogleFonts.inter(
                          fontSize: 11.5,
                          height: 1.35,
                          color: theme.primaryText),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Item 2: charge lines now carry their billing mode. A charge
          // quoted as "included" is priced into the package rather than
          // added on top — without the label the two are indistinguishable
          // on the order, which is exactly the kind of thing a customer
          // argues about later.
          for (final line in chargeLines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(line.$1,
                        style:
                            GoogleFonts.inter(color: theme.secondaryText)),
                  ),
                  if (_billingMode(charges, line.$3) == 'included')
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.tertiary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('included',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: theme.tertiary)),
                    ),
                  Text('₹${line.$2.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(color: theme.primaryText)),
                ],
              ),
            ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal',
                  style: GoogleFonts.inter(color: theme.secondaryText)),
              Text('₹${(q.subtotal ?? 0).toStringAsFixed(0)}',
                  style: GoogleFonts.inter(color: theme.primaryText)),
            ],
          ),
          // Item 2: GST mode (IGST vs CGST+SGST) as well as the amount.
          // `_gstType` is what the surveyor chose on the quote —
          // 'auto' means it was derived from the from/to states.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'GST (${(q.gstPct ?? 0).toStringAsFixed(0)}%)'
                '${_gstModeLabel(charges)}',
                style: GoogleFonts.inter(color: theme.secondaryText),
              ),
              Text('₹${(q.gstAmount ?? 0).toStringAsFixed(0)}',
                  style: GoogleFonts.inter(color: theme.primaryText)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700, color: theme.primaryText)),
              Text('₹${(q.total ?? 0).toStringAsFixed(0)}',
                  style: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700, color: theme.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Billing mode for a charge key, as stored by the quote builder under
/// `charges['_billingMode']`. Defaults to 'additional' — an unlabelled
/// charge is safer read as an extra than as bundled-in.
String _billingMode(Map<String, dynamic> charges, String key) {
  final raw = charges['_billingMode'];
  if (raw is Map && raw[key] is String) return raw[key] as String;
  return 'additional';
}

/// " · IGST" / " · CGST+SGST" suffix for the GST row. Returns an empty
/// string when the quote stored no mode, rather than guessing — showing
/// the wrong split on a tax line is worse than showing none.
String _gstModeLabel(Map<String, dynamic> charges) {
  final t = charges['_gstType'];
  if (t == 'inter') return ' · IGST';
  if (t == 'intra') return ' · CGST+SGST';
  return '';
}

/// One quoted item line: "Sofa — 3 Seater x2" with its stored per-line
/// CFT. Reads defensively because `items` is jsonb round-tripped from the
/// quote builder, so a key can be absent on older rows.
Widget _itemLine(FlutterFlowTheme theme, Map<String, dynamic> m) {
  final item = '${m['item'] ?? ''}'.trim();
  final sub = '${m['sub'] ?? ''}'.trim();
  final qty = m['qty'] is num ? (m['qty'] as num).toInt() : 1;
  final cft = m['cft'] is num ? m['cft'] as num : num.tryParse('${m['cft']}');
  final total = m['totalCftItem'] is num
      ? m['totalCftItem'] as num
      : (cft == null ? null : cft * qty);

  final name = [
    if (item.isNotEmpty) item,
    if (sub.isNotEmpty && sub != 'Qty') sub,
  ].join(' — ');

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '${name.isEmpty ? 'Item' : name}${qty > 1 ? '  x$qty' : ''}',
            style: GoogleFonts.inter(fontSize: 12.5, color: theme.primaryText),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          cft == null || cft == 0
              ? 'no CFT'
              : '${total ?? cft} CFT',
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: (cft == null || cft == 0)
                ? theme.warning
                : theme.secondaryText,
          ),
        ),
      ],
    ),
  );
}

Widget _kv(FlutterFlowTheme theme, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: GoogleFonts.inter(fontSize: 12.5, color: theme.secondaryText)),
          Text(v,
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.primaryText)),
        ],
      ),
    );
