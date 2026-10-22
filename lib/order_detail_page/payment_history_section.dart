import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';

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
    if (_loading) return const SizedBox.shrink();
    if (_entries.isEmpty) return const SizedBox.shrink();
    final total = _entries.fold<double>(0, (s, e) => s + e.amount);
    return NgSectionCard(
      title: 'Payment history',
      icon: Icons.payments_outlined,
      trailing: Text(functions.inrFull(total),
          style: NgFonts.mono(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: NgPalette.of(context).green)),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _entries.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: NgPalette.of(context).w06),
            _row(context, _entries[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, PaymentEntriesRow e) {
    final c = NgPalette.of(context);
    final when = e.receivedAt ?? e.createdAt;
    final sub = [
      if (when != null) DateFormat('d MMM yyyy, h:mm a').format(when.toLocal()),
      if ((e.note ?? '').trim().isNotEmpty) e.note!.trim(),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          NgIconTile(icon: _modeIcon(e.mode), status: NgStatus.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(functions.inrFull(e.amount),
                        style: NgFonts.mono(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.text)),
                    const SizedBox(width: 8),
                    NgPill(e.mode.toUpperCase()),
                    if (e.receiptId != null) ...[
                      const SizedBox(width: 6),
                      const NgPill('Receipted', status: NgStatus.green),
                    ],
                  ],
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => _delete(e),
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.red),
            tooltip: 'Delete payment',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  static IconData _modeIcon(String mode) => switch (mode.toLowerCase()) {
        'cash' => Icons.payments_outlined,
        'upi' => Icons.qr_code_2_rounded,
        'bank' || 'neft' || 'imps' || 'rtgs' => Icons.account_balance_outlined,
        'cheque' => Icons.description_outlined,
        'porter' => Icons.local_shipping_outlined,
        _ => Icons.currency_rupee_rounded,
      };
}
