import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/audit_log_service.dart';
import '/backend/customer_lookup.dart';
import '/backend/customer_survey_parse.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/survey_queue.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// Detail view + actions for one `customer_surveys` row (Session 4, Part
/// B1). Room-by-room inventory isn't possible — see
/// customer_survey_parse.dart's doc comment: `items` has no room/category
/// grouping in this data, so this renders a flat item list instead of
/// inventing a structure the schema doesn't have.
Future<bool?> showCustomerSurveyDetailSheet(
    BuildContext context, String surveyId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CustomerSurveyDetailSheet(surveyId: surveyId),
  );
}

class _CustomerSurveyDetailSheet extends StatefulWidget {
  const _CustomerSurveyDetailSheet({required this.surveyId});
  final String surveyId;

  @override
  State<_CustomerSurveyDetailSheet> createState() =>
      _CustomerSurveyDetailSheetState();
}

class _CustomerSurveyDetailSheetState
    extends State<_CustomerSurveyDetailSheet> {
  CustomerSurveysRow? _survey;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await CustomerSurveysTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('id', widget.surveyId),
    );
    if (!mounted) return;
    setState(() {
      _survey = rows.isNotEmpty ? rows.first : null;
      _loading = false;
    });
  }

  Future<void> _markReviewed() async {
    final s = _survey;
    if (s == null || s.id == null) return;
    setState(() => _busy = true);
    try {
      await CustomerSurveysTable().update(
        data: {
          'status': 'reviewed',
          'reviewed_by': AppSession.instance.currentStaffName ?? 'Owner',
          'reviewed_at': DateTime.now().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', s.id!),
      );
      _changed = true;
      await SurveyQueue.instance.refresh();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachToLead() async {
    final s = _survey;
    if (s == null || s.id == null) return;
    final leadId = await showDialog<String>(
      context: context,
      builder: (_) => _LeadPickerDialog(prefillName: s.customerName),
    );
    if (leadId == null) return;
    setState(() => _busy = true);
    try {
      await CustomerSurveysTable().update(
        data: {'lead_id': leadId},
        matchingRows: (q) => OrgScope.write(q).eq('id', s.id!),
      );
      _changed = true;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Attached to lead.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not attach: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Field spec: "Open in Survey & Quote" — SurveyQuotePageWidget's own
  /// `surveyId` param seeds from the OTHER survey table (`surveys.rooms`),
  /// a different shape entirely (see customer_survey_parse.dart). Rather
  /// than force this row's flat items into that shape, this opens the
  /// builder pre-filled from the customer_surveys row's own contact/route
  /// fields only — same "start blank but pre-filled" contract the
  /// standalone hub's walk-in button already uses.
  void _openInSurveyQuote() {
    final s = _survey;
    if (s == null) return;
    context.pushNamed(
      SurveyQuotePageWidget.routeName,
      queryParameters: {
        'leadId': serializeParam(s.leadId, ParamType.String),
        'leadCustomer': serializeParam(s.customerName, ParamType.String),
        'leadPhone': serializeParam(s.phone, ParamType.String),
        'leadFromCity':
            serializeParam(s.fromCity ?? s.fromAddress, ParamType.String),
        'leadToCity': serializeParam(s.toCity ?? s.toAddress, ParamType.String),
      }.withoutNulls,
    );
  }

  /// converted_to_order_id is uuid but orders.id is TEXT — that FK can
  /// never match (flagged by Arun, fix is his own follow-up migration).
  /// This creates the real order and calls findOrCreateCustomer (same
  /// fix Part A5 made for the lead-to-order path), but deliberately does
  /// NOT attempt to write converted_to_order_id — CustomerSurveysRow's
  /// own getter for that column has no setter at all, so this can't
  /// silently regress even if someone tries later.
  Future<void> _convertToOrder() async {
    final s = _survey;
    if (s == null || s.id == null) return;
    setState(() => _busy = true);
    try {
      final orgId = OrgScope.currentOrgId!;
      String? customerId;
      try {
        customerId = await CustomerLookup.findOrCreate(
          orgId: orgId,
          name: s.customerName ?? 'Unknown',
          phone: s.phone,
        );
      } catch (_) {}

      final prefix = AppSession.instance.currentOrgSlug?.toUpperCase() ?? 'NGV';
      const seqKey = 'order_id_seq';
      final seqRows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', seqKey),
      );
      final current = seqRows.isNotEmpty
          ? (int.tryParse(seqRows.first.value ?? '1000') ?? 1000)
          : 1000;
      final next = current + 1;
      await SettingsTable().upsert(
        {
          'key': seqKey,
          ...OrgScope.stamp(),
          'value': next.toString(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'org_id,key',
      );
      final newOrderId = '$prefix-$next';

      await OrdersTable().insert({
        ...OrgScope.stamp(),
        'id': newOrderId,
        'lead_id': s.leadId,
        if (customerId != null) 'customer_id': customerId,
        'customer': s.customerName ?? '',
        'phone': s.phone,
        'from_city': s.fromCity,
        'to_city': s.toCity,
        if ((s.fromAddress ?? '').isNotEmpty) 'from_address': s.fromAddress,
        if ((s.toAddress ?? '').isNotEmpty) 'to_address': s.toAddress,
        'move_date': supaSerialize<DateTime>(s.moveDate ?? DateTime.now()),
        'amount': 0.0,
        'service': s.service,
        'notes': s.notes,
        'status': 'booked',
        'payment_status': 'pending',
        'tracking_status': 'Booked',
        'advance_paid': 0.0,
      });

      await CustomerSurveysTable().update(
        data: {'status': 'converted'},
        matchingRows: (q) => OrgScope.write(q).eq('id', s.id!),
      );
      await AuditLogService.log(
        entityType: 'customer_surveys',
        entityId: s.id!,
        action: 'converted_to_order',
        newValue: {'order_id': newOrderId},
      );
      _changed = true;
      await SurveyQueue.instance.refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order $newOrderId created.')));
      context.pushNamed(
        OrderDetailPageWidget.routeName,
        queryParameters: {
          'orderId': serializeParam(newOrderId, ParamType.String),
          'orderCustomer': serializeParam(s.customerName, ParamType.String),
          'orderPhone': serializeParam(s.phone, ParamType.String),
        }.withoutNulls,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not convert: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    final s = _survey;
    if (s == null || s.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this survey?'),
        content: const Text(
            'It stays in the list under "discarded" — nothing is deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await CustomerSurveysTable().update(
        data: {'status': 'discarded'},
        matchingRows: (q) => OrgScope.write(q).eq('id', s.id!),
      );
      _changed = true;
      await SurveyQueue.instance.refresh();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not discard: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final s = _survey;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: theme.primaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : s == null
                  ? const Center(child: Text('Survey not found.'))
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: theme.alternate,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(s.customerName ?? 'Unnamed',
                                  style: GoogleFonts.interTight(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: theme.primaryText)),
                            ),
                            _statusBadge(theme, s.status),
                          ],
                        ),
                        if ((s.phone ?? '').isNotEmpty)
                          Text(s.phone!,
                              style: GoogleFonts.inter(
                                  fontSize: 12.5, color: theme.secondaryText)),
                        const SizedBox(height: 14),
                        _section(theme, 'Route', [
                          _kv('From', [s.fromCity, s.fromAddress]
                              .whereType<String>()
                              .where((x) => x.isNotEmpty)
                              .join(' — ')),
                          _kv('From Floor', displayOrDash(s.fromFloor)),
                          _kv('From Lift', displayOrDash(s.fromLift)),
                          _kv('To', [s.toCity, s.toAddress]
                              .whereType<String>()
                              .where((x) => x.isNotEmpty)
                              .join(' — ')),
                          _kv('To Floor', displayOrDash(s.toFloor)),
                          _kv('To Lift', displayOrDash(s.toLift)),
                          _kv('Move Date',
                              s.moveDate == null
                                  ? '—'
                                  : DateFormat('d MMM yyyy').format(s.moveDate!)),
                          _kv('Service', s.service),
                        ]),
                        _section(theme, 'Inventory (CFT Totals)', [
                          _kv('Total CFT', '${s.totalCft ?? 0}'),
                          _kv('Suggested Vehicle',
                              displayOrDash(s.suggestedVehicle)),
                        ]),
                        _itemsBlock(theme, s),
                        _photosBlock(theme, s),
                        if ((s.notes ?? '').isNotEmpty)
                          _section(theme, 'Special Instructions', [
                            Text(s.notes!,
                                style: GoogleFonts.inter(fontSize: 12.5)),
                          ]),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (s.status == 'submitted')
                              FilledButton.icon(
                                onPressed: _busy ? null : _markReviewed,
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Mark Reviewed'),
                              ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _openInSurveyQuote,
                              icon: const Icon(Icons.list_alt, size: 16),
                              label: const Text('Open in Survey & Quote'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  (_busy || s.leadId != null) ? null : _attachToLead,
                              icon: const Icon(Icons.link, size: 16),
                              label: Text(s.leadId != null
                                  ? 'Attached to Lead'
                                  : 'Attach to Lead'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  (_busy || s.status == 'converted') ? null : _convertToOrder,
                              icon: const Icon(Icons.assignment_turned_in, size: 16),
                              label: const Text('Convert to Order'),
                            ),
                            OutlinedButton.icon(
                              onPressed: (_busy || s.status == 'discarded')
                                  ? null
                                  : _discard,
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Discard'),
                            ),
                          ],
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _statusBadge(FlutterFlowTheme theme, String status) {
    final color = {
          'pending': Colors.grey,
          'submitted': Colors.blue,
          'reviewed': Colors.purple,
          'converted': Colors.green,
          'discarded': Colors.red,
        }[status] ??
        Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(status,
          style: GoogleFonts.inter(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _section(FlutterFlowTheme theme, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.interTight(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: theme.primary)),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
                width: 110,
                child: Text(label,
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey))),
            Expanded(
                child: Text(value.isEmpty ? '—' : value,
                    style: GoogleFonts.inter(fontSize: 12.5))),
          ],
        ),
      );

  Widget _itemsBlock(FlutterFlowTheme theme, CustomerSurveysRow s) {
    final items = [
      ...parseCustomerSurveyItems(s.items),
      ...parseCustomItems(s.customItems),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return _section(theme, 'Items', [
      for (final line in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                  child: Text(line.label, style: GoogleFonts.inter(fontSize: 12.5))),
              Text('× ${line.qty}',
                  style:
                      GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
    ]);
  }

  Widget _photosBlock(FlutterFlowTheme theme, CustomerSurveysRow s) {
    final photos = parseCustomerSurveyPhotos(s.photos);
    if (photos.isEmpty) return const SizedBox.shrink();
    return _section(theme, 'Photos (${photos.length})', [
      SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final (room, dataUri) = photos[i];
            final b64 = dataUri.split(',').skip(1).join(',');
            Uint8List? bytes;
            try {
              bytes = base64Decode(b64);
            } catch (_) {}
            return GestureDetector(
              onTap: bytes == null
                  ? null
                  : () => showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: Image.memory(bytes!, fit: BoxFit.contain),
                        ),
                      ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: bytes == null
                        ? Container(width: 70, height: 60, color: theme.alternate)
                        : Image.memory(bytes, width: 70, height: 60, fit: BoxFit.cover),
                  ),
                  Text(room,
                      style: GoogleFonts.inter(fontSize: 9, color: theme.secondaryText)),
                ],
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// Minimal lead search-and-pick for "Attach to Lead".
class _LeadPickerDialog extends StatefulWidget {
  const _LeadPickerDialog({this.prefillName});
  final String? prefillName;

  @override
  State<_LeadPickerDialog> createState() => _LeadPickerDialogState();
}

class _LeadPickerDialogState extends State<_LeadPickerDialog> {
  late final _searchCtrl = TextEditingController(text: widget.prefillName ?? '');
  List<LeadsRow> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final term = _searchCtrl.text.trim();
      _results = await LeadsTable().queryRows(
        queryFn: (q) {
          var query = OrgScope.read(q);
          if (term.isNotEmpty) query = query.ilike('customer', '%$term%');
          return query.order('created_at', ascending: false).limit(20);
        },
      );
    } catch (_) {
      _results = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Attach to Lead'),
      content: SizedBox(
        width: 380,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Search leads by name',
                suffixIcon: IconButton(
                    icon: const Icon(Icons.search), onPressed: _search),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final l = _results[i];
                        return ListTile(
                          title: Text(l.customer),
                          subtitle: Text(l.phone ?? ''),
                          onTap: () => Navigator.of(context).pop(l.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
      ],
    );
  }
}
