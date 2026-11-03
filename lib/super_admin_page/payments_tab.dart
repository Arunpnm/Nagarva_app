import 'package:flutter/material.dart';

import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import 'admin_common.dart';

/// Admin › Payments: subscription payments from vendors, read from
/// platform_invoices. Nothing writes that table until online billing is
/// live (Item 31, on hold for the CA's call on which entity bills), and
/// even then only the gateway's webhook will mark a payment paid; this
/// screen never does.
class PaymentsTab extends StatefulWidget {
  const PaymentsTab({super.key});
  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends AdminSectionState<PaymentsTab> {
  List<Map<String, dynamic>> _rows = const [];
  Map<String, String> _orgs = const {};
  String _filter = 'all';

  @override
  String get migrationFile => 'the billing migration';

  @override
  Future<void> fetch() async {
    final r = await Future.wait([
      db.from('platform_invoices').select().order('invoice_date', ascending: false).limit(500),
      db.from('organizations').select('id,name'),
    ]);
    _rows = List<Map<String, dynamic>>.from(r[0]);
    _orgs = {for (final o in r[1]) '${o['id']}': '${o['name']}'};
  }

  @override
  Widget build(BuildContext context) => body((c) {
        final now = DateTime.now();
        bool thisMonth(Map r) {
          final d = DateTime.tryParse('${r['paid_at'] ?? r['invoice_date']}');
          return d != null && d.year == now.year && d.month == now.month;
        }

        num sum(Iterable<Map> rs, String k) => rs.fold<num>(0, (s, r) => s + (r[k] as num? ?? 0));
        final paid = _rows.where((r) => r['status'] == 'paid');
        final shown = _filter == 'all' ? _rows : _rows.where((r) => r['status'] == _filter).toList();
        return [
          const AdminHeading('Payments', 'Subscriptions from vendors'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (label, value, sub) in [
              ('Collected this month', adminMoney.format(sum(paid.where(thisMonth), 'total_amount')),
                  '${paid.where(thisMonth).length} payments'),
              ('GST this month', adminMoney.format(sum(paid.where(thisMonth), 'gst_amount')), 'for GSTR-1'),
              ('Failed', '${_rows.where((r) => r['status'] == 'failed').length}', 'all time'),
            ])
              SizedBox(
                width: 200,
                child: NgCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                    const SizedBox(height: 4),
                    Text(value,
                        style: NgFonts.geist(fontSize: 22, fontWeight: FontWeight.w600, color: c.text)),
                    Text(sub, style: NgFonts.geist(fontSize: 12, color: c.faint)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 6, children: [
            for (final (k, l) in const [('all', 'All'), ('paid', 'Paid'), ('failed', 'Failed'), ('refunded', 'Refunded')])
              NgChip(
                  label: l,
                  count: k == 'all' ? _rows.length : _rows.where((r) => r['status'] == k).length,
                  selected: _filter == k,
                  onTap: () => setState(() => _filter = k)),
          ]),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            const NgEmptyState(
              icon: Icons.payments_outlined,
              title: 'No subscription payments yet',
              subtitle:
                  'Vendors cannot pay online until subscription billing goes live. Payments will appear here as the gateway confirms them.',
            )
          else
            NgCardList(children: [
              for (final r in shown)
                NgListRow(
                  icon: switch ('${r['status']}') {
                    'paid' => Icons.check_circle_outline_rounded,
                    'failed' => Icons.error_outline_rounded,
                    'refunded' => Icons.undo_rounded,
                    _ => Icons.schedule_rounded,
                  },
                  iconStatus: switch ('${r['status']}') {
                    'paid' => NgStatus.green,
                    'failed' => NgStatus.red,
                    'refunded' => NgStatus.blue,
                    _ => NgStatus.amber,
                  },
                  title: _orgs['${r['org_id']}'] ?? 'Vendor',
                  subtitle: ['${r['invoice_no'] ?? ''}', adminDate(r['invoice_date'])]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(adminMoney.format(r['total_amount'] ?? 0),
                            style: NgFonts.mono(fontSize: 13.5, color: c.text)),
                        Text('${r['status']}', style: NgFonts.geist(fontSize: 12, color: c.mute)),
                      ]),
                ),
            ]),
          const SizedBox(height: 10),
          Text('Payments are marked paid only by the payment gateway, never by hand. Amounts include 18% GST.',
              style: NgFonts.geist(fontSize: 12, color: c.mute)),
        ];
      });
}
