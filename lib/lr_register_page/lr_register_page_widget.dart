import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';

/// LR Register (Session 4, Part C-3) — a searchable register behind the
/// LR document generation that already existed (Session 3,
/// order_documents_section.dart's _genLr). Read-only: this doesn't
/// generate LRs, it finds ones already issued.
class LrRegisterPageWidget extends StatefulWidget {
  const LrRegisterPageWidget({super.key});

  static String routeName = 'LrRegisterPage';
  static String routePath = '/lr-register';

  @override
  State<LrRegisterPageWidget> createState() => _LrRegisterPageWidgetState();
}

class _LrRegisterPageWidgetState extends State<LrRegisterPageWidget>
    with RefreshOnPopMixin<LrRegisterPageWidget> {
  bool _loading = true;
  List<LrRegisterRow> _all = [];
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _all = await LrRegisterTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('created_at', ascending: false),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load LR register: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _statuses => _all.map((r) => r.status).toSet().toList()..sort();

  List<LrRegisterRow> get _filtered {
    var rows = _all;
    if (_statusFilter != null) rows = rows.where((r) => r.status == _statusFilter).toList();
    if (_search.trim().isNotEmpty) {
      final term = _search.trim().toLowerCase();
      rows = rows.where((r) =>
          r.lrNo.toLowerCase().contains(term) ||
          (r.consigneeName ?? '').toLowerCase().contains(term) ||
          (r.vehicleNo ?? '').toLowerCase().contains(term)).toList();
    }
    return rows;
  }

  Future<void> _openDetail(LrRegisterRow lr) async {
    List<LrCopiesRow> copies = [];
    PodRecordsRow? pod;
    try {
      if (lr.id != null) {
        copies = await LrCopiesTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('lr_id', lr.id!),
        );
        final pods = await PodRecordsTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('lr_id', lr.id!),
        );
        pod = pods.isNotEmpty ? pods.first : null;
      }
    } catch (_) {}
    if (!mounted) return;
    final ng = NgPalette.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: ng.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Text(lr.lrNo,
                  style: NgFonts.geist(
                      fontSize: 17, fontWeight: FontWeight.w700, color: ng.text)),
              Align(
                  alignment: Alignment.centerLeft,
                  child: NgPill(_statusLabel(lr.status),
                      status: _statusTone(lr.status))),
              const SizedBox(height: 10),
              _kv('Date', lr.lrDate == null ? '—' : DateFormat('d MMM yyyy').format(lr.lrDate!)),
              _kv('Order', lr.orderId ?? '—'),
              _kv('From', lr.fromPlace ?? '—'),
              _kv('To', lr.toPlace ?? '—'),
              _kv('Consignor', lr.consignorName ?? '—'),
              _kv('Consignee', lr.consigneeName ?? '—'),
              _kv('Consignee Phone', lr.consigneePhone ?? '—'),
              _kv('Vehicle', lr.vehicleNo ?? '—'),
              _kv('Driver', lr.driverName ?? '—'),
              _kv('Packages', '${lr.packageCount ?? 0}'),
              _kv('Freight Mode', lr.freightMode ?? '—'),
              _kv('Total Amount', '₹${(lr.totalAmount ?? 0).toStringAsFixed(2)}'),
              if (copies.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Copies Generated',
                    style: NgFonts.geist(fontSize: 12.5, fontWeight: FontWeight.w700)),
                Wrap(
                  spacing: 6,
                  children: [
                    // NOT VisualDensity.compact, and not a Chip.
                    //
                    // Compact subtracts 8 logical pixels from the widget's
                    // own size, and on the dashboard period chips that came
                    // straight out of the label - "This" rendered as "Thi"
                    // with the s faded at the pill edge, reproducible at
                    // 500dp with the row half empty, so it was never a space
                    // problem. Copy types are LONGER words ("Consignor",
                    // "Transporter"), so the same squeeze bites harder here.
                    //
                    // Swept 6 Sept 2026: eleven other sites use compact
                    // density and ten are IconButtons, which have no label to
                    // clip. This was the only other chip.
                    for (final c in copies)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: NgPalette.of(context).bg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          c.copyType,
                          style: NgFonts.geist(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: NgPalette.of(context).text,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (pod != null) ...[
                const SizedBox(height: 10),
                Text('Proof of Delivery',
                    style: NgFonts.geist(fontSize: 12.5, fontWeight: FontWeight.w700)),
                _kv('Delivered At',
                    pod.deliveredAt == null ? '—' : DateFormat('d MMM yyyy, h:mm a').format(pod.deliveredAt!.toLocal())),
                _kv('Received By', pod.receivedByName ?? '—'),
                _kv('Packages Delivered', '${pod.packagesDelivered ?? 0}'),
                if (pod.damageNoted == true)
                  _kv('Damage', pod.damageDescription ?? 'Noted'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 120, child: Text(label, style: NgFonts.geist(fontSize: 12, color: Colors.grey))),
            Expanded(child: Text(value, style: NgFonts.geist(fontSize: 12.5))),
          ],
        ),
      );

  static const _kStatusOrder = ['issued', 'in_transit', 'delivered', 'cancelled'];

  String _statusLabel(String st) => switch (st) {
        'issued' => 'Issued',
        'in_transit' => 'In transit',
        'delivered' => 'Delivered',
        'cancelled' => 'Cancelled',
        _ => st,
      };

  NgStatus _statusTone(String st) => switch (st) {
        'in_transit' => NgStatus.blue,
        'delivered' => NgStatus.green,
        'cancelled' => NgStatus.red,
        _ => NgStatus.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final statuses = [
      ..._kStatusOrder.where(_statuses.contains),
      ..._statuses.where((s) => !_kStatusOrder.contains(s)),
    ];
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  const NgModuleHeader('LR Register'),
                  const SizedBox(height: 14),
                  NgSearchField(
                    controller: _searchCtrl,
                    hint: 'Search LR no, consignee or vehicle',
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 14),
                  NgChipRow(
                    edge: 0,
                    chips: [
                      NgChip(
                        label: 'All',
                        selected: _statusFilter == null,
                        onTap: () => setState(() => _statusFilter = null),
                      ),
                      for (final st in statuses)
                        NgChip(
                          label: _statusLabel(st),
                          selected: _statusFilter == st,
                          onTap: () => setState(() => _statusFilter = st),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_filtered.isEmpty)
                    NgCard(
                      child: Text('No LRs found.',
                          textAlign: TextAlign.center,
                          style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                    )
                  else
                    NgCardList(children: [
                      for (final lr in _filtered) _lrRow(lr),
                    ]),
                ],
              ),
            ),
    );
  }

  Widget _lrRow(LrRegisterRow lr) {
    final c = NgPalette.of(context);
    return InkWell(
      onTap: () => _openDetail(lr),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lr.lrNo,
                      style: NgFonts.mono(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  const SizedBox(height: 2),
                  Text(
                    '${lr.consigneeName ?? '—'} · ${lr.fromPlace ?? '—'} → ${lr.toPlace ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(functions.inrFull(lr.totalAmount ?? 0),
                    style: NgFonts.mono(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
                const SizedBox(height: 4),
                NgPill(_statusLabel(lr.status), status: _statusTone(lr.status)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
