import 'package:flutter/material.dart';

import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;

import '/backend/pricing_defaults.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/ng_tokens.dart';

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
  OrdersRow? _order;
  bool _loading = true;

  /// True when this order carries a frozen snapshot, i.e. it was
  /// converted after 20260729_order_quote_snapshot.sql landed.
  bool get _hasSnapshot => _order?.quoteSnapshotAt != null;

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
      _order = orders.isNotEmpty ? orders.first : null;
      final quotationId = _order?.quotationId;
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
    // With a snapshot we no longer need the live quote at all — an order
    // converted from a quote that was later deleted still shows what it
    // was confirmed on.
    if (_loading || (_quotation == null && !_hasSnapshot)) {
      return const SizedBox.shrink();
    }
    final ng = NgPalette.of(context);
    final q = _quotation;
    final o = _order;

    // Item 2: PREFER THE SNAPSHOT. orders.quotation_id stays the live
    // link, but once a quote can be revised (operational flow 1.2) or
    // signed (item 3), what the linked quote says now is not necessarily
    // what this order was confirmed on. The frozen figures win; the live
    // quote is only the fallback for orders converted before the snapshot
    // existed.
    final items = _hasSnapshot
        ? (o!.quoteItems is List ? o.quoteItems as List : const [])
        : ((q?.items is List) ? q!.items as List : const []);
    final charges = _hasSnapshot
        ? (o!.quoteCharges is Map
            ? Map<String, dynamic>.from(o.quoteCharges as Map)
            : <String, dynamic>{})
        : ((q?.charges is Map)
            ? Map<String, dynamic>.from(q!.charges as Map)
            : <String, dynamic>{});

    final subtotal = _hasSnapshot ? o!.quoteSubtotal : q?.subtotal;
    final gstPct = _hasSnapshot ? o!.quoteGstPct : q?.gstPct;
    final gstAmount = _hasSnapshot ? o!.quoteGstAmount : q?.gstAmount;
    final total = _hasSnapshot ? o!.quoteTotal : q?.total;
    final packing = _hasSnapshot
        ? o!.quotePackingType
        : charges['_suggestedPackage']?.toString();
    // Snapshot stores the RESOLVED inter/intra; the live quote may still
    // say 'auto', which _gstModeLabel correctly renders as nothing.
    final gstMode =
        _hasSnapshot ? o!.quoteGstMode : _gstModeRaw(charges);

    // Carries the charge KEY as well as label+amount, so the billing
    // mode (included / additional) can be resolved per line below.
    final chargeLines = <(String, num, String)>[];
    for (final f in kDefaultChargeFields) {
      final v = charges[f.key];
      if (v is num && v > 0) chargeLines.add((f.label, v, f.key));
    }

    return NgSectionCard(
      title: 'Quotation breakdown',
      icon: Icons.request_quote_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Item 2: this used to print only a COUNT ("3 item line(s)"),
          // which is why a converted order looked like it had lost the
          // quote's detail. Every line shows with the CFT it was actually
          // quoted at (stored per line since the 28 Jul CFT fix, so a
          // later catalogue edit can't rewrite history).
          if (items.isNotEmpty) ...[
            Row(
              children: [
                Text('Items',
                    style: NgFonts.geist(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: ng.text)),
                const Spacer(),
                Text(
                  '${items.length} line(s)'
                  '${charges['_totalCft'] != null ? ' · ${charges['_totalCft']} CFT' : ''}',
                  style: NgFonts.mono(fontSize: 12, color: ng.mute),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: ng.inset,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                for (final raw in items)
                  if (raw is Map) _itemLine(ng, Map<String, dynamic>.from(raw)),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          // Packing / suggested package, and the crew+vehicle it implies.
          if ((packing ?? '').isNotEmpty) ...[
            NgKeyValue('Package', packing!),
            const SizedBox(height: 4),
          ],
          // Flags quotes saved before the 28 Jul 2026 custom-item CFT fix,
          // where a line persisted with cft 0 and so contributed nothing
          // to the CFT total. Read-only warning: nothing is rewritten,
          // because the intended CFT for a one-off item can't be inferred
          // after the fact. See supabase/diagnostics_zero_cft_quotes.sql.
          if (_zeroCftCount(items) > 0) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ng.amberBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 17, color: ng.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_zeroCftCount(items)} item line(s) on this quote have '
                      'no CFT, so the total CFT and suggested vehicle may be '
                      'under-sized. Re-quote before dispatch if it matters.',
                      style: NgFonts.geist(
                          fontSize: 12.5, height: 1.35, color: ng.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Item 2: charge lines carry their billing mode. A charge quoted
          // as "included" is priced into the package rather than added on
          // top — without the label the two are indistinguishable.
          for (final line in chargeLines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(line.$1,
                        style: NgFonts.geist(fontSize: 13.5, color: ng.mute)),
                  ),
                  if (_billingMode(charges, line.$3) == 'included') ...[
                    const NgPill('Included', status: NgStatus.blue),
                    const SizedBox(width: 8),
                  ],
                  Text(functions.inrFull(line.$2.toDouble()),
                      style: NgFonts.mono(fontSize: 13.5, color: ng.text)),
                ],
              ),
            ),
          Divider(height: 18, color: ng.w06),
          NgKeyValue('Subtotal', functions.inrFull((subtotal ?? 0).toDouble()),
              mono: true),
          // Item 2: GST mode (IGST vs CGST+SGST) as well as the amount.
          // From the snapshot this is the RESOLVED mode; from a live
          // quote it may still be 'auto', which renders as no suffix.
          NgKeyValue(
              'GST (${(gstPct ?? 0).toStringAsFixed(0)}%)'
              '${_gstModeSuffix(gstMode)}',
              functions.inrFull((gstAmount ?? 0).toDouble()),
              mono: true),
          const SizedBox(height: 2),
          NgKeyValue('Total', functions.inrFull((total ?? 0).toDouble()),
              mono: true, strong: true),
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

/// The live quote's raw `_gstType`, which may be 'auto'. Only used as the
/// fallback for orders with no snapshot — a snapshot stores the resolved
/// value instead.
String? _gstModeRaw(Map<String, dynamic> charges) =>
    charges['_gstType']?.toString();

/// " · IGST" / " · CGST+SGST" suffix for the GST row. Empty for 'auto' or
/// null rather than guessing — showing the wrong split on a tax line is
/// worse than showing none.
String _gstModeSuffix(String? mode) {
  if (mode == 'inter') return ' · IGST';
  if (mode == 'intra') return ' · CGST+SGST';
  return '';
}

/// One quoted item line: "Sofa — 3 Seater x2" with its stored per-line
/// CFT. Reads defensively because `items` is jsonb round-tripped from the
/// quote builder, so a key can be absent on older rows.
Widget _itemLine(NgPalette ng, Map<String, dynamic> m) {
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
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '${name.isEmpty ? 'Item' : name}${qty > 1 ? '  x$qty' : ''}',
            style: NgFonts.geist(fontSize: 13, color: ng.text),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          cft == null || cft == 0
              ? 'no CFT'
              : '${total ?? cft} CFT',
          style: NgFonts.mono(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: (cft == null || cft == 0)
                ? ng.amber
                : ng.mute,
          ),
        ),
      ],
    ),
  );
}
