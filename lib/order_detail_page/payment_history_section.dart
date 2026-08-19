import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Payment history + delete, for a single order (Item 11 sweep, 16 Aug
/// 2026 — `payment_entries` had soft-delete columns and a working
/// recycle-bin entry, but no delete UI anywhere in the app to reach it
/// from). Deliberately separate from [QuickPaymentSection] (entry-only,
/// hides once the order is closed or fully paid) — this renders
/// regardless of order/balance state, since a fully-paid or closed order
/// is exactly when someone would come looking to fix a mis-entered
/// payment.
class PaymentHistorySection extends StatefulWidget {
  const PaymentHistorySection({super.key, required this.orderId, this.onChanged});

  final String orderId;
  final VoidCallback? onChanged;

  @override
  State<PaymentHistorySection> createState() => PaymentHistorySectionState();
}

class PaymentHistorySectionState extends State<PaymentHistorySection> {
  bool _loading = true;
  List<PaymentEntriesRow> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await PaymentEntriesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId),
      );
      rows.sort((a, b) => (b.receivedAt ?? b.createdAt ?? DateTime(0))
          .compareTo(a.receivedAt ?? a.createdAt ?? DateTime(0)));
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(PaymentEntriesRow entry) async {
    final deleted = await DeleteAction.run(
      context,
      table: 'payment_entries',
      id: entry.id,
      entityLabel: 'payment',
      check: () => SoftDeleteService.canDeletePaymentEntry(entry),
      reasonRequired: true,
      onDeleted: () {
        widget.onChanged?.call();
        _load();
      },
    );
    if (deleted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    if (_loading) return const SizedBox.shrink();
    if (_entries.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Payment History',
              style: GoogleFonts.interTight(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryText)),
          const SizedBox(height: 10),
          for (final e in _entries) _row(theme, e),
        ],
      ),
    );
  }

  Widget _row(FlutterFlowTheme theme, PaymentEntriesRow e) {
    final when = e.receivedAt ?? e.createdAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₹${e.amount.toStringAsFixed(0)} · ${e.mode.toUpperCase()}',
                    style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryText)),
                if (when != null)
                  Text(DateFormat('d MMM yyyy, h:mm a').format(when.toLocal()),
                      style: GoogleFonts.inter(
                          fontSize: 11.5, color: theme.secondaryText)),
                if ((e.note ?? '').trim().isNotEmpty)
                  Text(e.note!.trim(),
                      style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: theme.secondaryText)),
                if (e.receiptId != null)
                  Text('Receipted',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: theme.primary)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _delete(e),
            icon: Icon(Icons.delete_outline, size: 19, color: theme.error),
            tooltip: 'Delete payment',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
