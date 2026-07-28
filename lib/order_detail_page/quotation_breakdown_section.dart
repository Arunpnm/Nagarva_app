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
      _QuotationBreakdownSectionState();
}

class _QuotationBreakdownSectionState
    extends State<QuotationBreakdownSection> {
  QuotationsRow? _quotation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

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

    final chargeLines = <(String, num)>[];
    for (final f in kDefaultChargeFields) {
      final v = charges[f.key];
      if (v is num && v > 0) chargeLines.add((f.label, v));
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
          if (items.isNotEmpty) ...[
            Text('${items.length} item line(s)'
                '${charges['_totalCft'] != null ? ' · ${charges['_totalCft']} CFT' : ''}',
                style: GoogleFonts.inter(
                    fontSize: 12.5, color: theme.secondaryText)),
            const SizedBox(height: 8),
          ],
          for (final line in chargeLines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(line.$1,
                      style:
                          GoogleFonts.inter(color: theme.secondaryText)),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GST (${(q.gstPct ?? 0).toStringAsFixed(0)}%)',
                  style: GoogleFonts.inter(color: theme.secondaryText)),
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
