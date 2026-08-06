import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
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
    final theme = FlutterFlowTheme.of(context);
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
            color: theme.primaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Text(lr.lrNo,
                  style: GoogleFonts.interTight(
                      fontSize: 17, fontWeight: FontWeight.w700, color: theme.primaryText)),
              _statusChip(theme, lr.status),
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
                    style: GoogleFonts.interTight(fontSize: 12.5, fontWeight: FontWeight.w700)),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in copies)
                      Chip(label: Text(c.copyType), visualDensity: VisualDensity.compact),
                  ],
                ),
              ],
              if (pod != null) ...[
                const SizedBox(height: 10),
                Text('Proof of Delivery',
                    style: GoogleFonts.interTight(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
            SizedBox(width: 120, child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey))),
            Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 12.5))),
          ],
        ),
      );

  Widget _statusChip(FlutterFlowTheme theme, String status) {
    final color = {
          'issued': Colors.grey,
          'in_transit': Colors.blue,
          'delivered': Colors.green,
          'cancelled': Colors.red,
        }[status] ??
        Colors.grey;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(status, style: GoogleFonts.inter(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text('LR Register',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600), fontSize: 22, fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search LR No / Consignee / Vehicle',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 8),
                  if (_statuses.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                            label: const Text('All'),
                            selected: _statusFilter == null,
                            onSelected: (_) => setState(() => _statusFilter = null)),
                        for (final s in _statuses)
                          ChoiceChip(
                              label: Text(s),
                              selected: _statusFilter == s,
                              onSelected: (_) => setState(() => _statusFilter = s)),
                      ],
                    ),
                  const SizedBox(height: 10),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('No LRs found.', style: GoogleFonts.inter(color: theme.secondaryText)),
                    )
                  else
                    for (final lr in _filtered) _lrRow(theme, lr),
                ],
              ),
            ),
    );
  }

  Widget _lrRow(FlutterFlowTheme theme, LrRegisterRow lr) {
    return InkWell(
      onTap: () => _openDetail(lr),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lr.lrNo, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    [
                      lr.consigneeName ?? '—',
                      '${lr.fromPlace ?? '—'} → ${lr.toPlace ?? '—'}',
                    ].join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${(lr.totalAmount ?? 0).toStringAsFixed(0)}',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                _statusChip(theme, lr.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
