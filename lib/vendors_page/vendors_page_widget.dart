import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'vendor_detail_page_widget.dart';

/// Vendors (Session 4, Part C-6) — subcontractors/suppliers this org pays
/// (porters, vehicle owners, packing material suppliers, labour
/// contractors). Live schema confirmed directly against the DB: vendors +
/// order_vendors + vendor_bills + vendor_payments.
class VendorsPageWidget extends StatefulWidget {
  const VendorsPageWidget({super.key});

  static String routeName = 'VendorsPage';
  static String routePath = '/vendors';

  @override
  State<VendorsPageWidget> createState() => _VendorsPageWidgetState();
}

class _VendorsPageWidgetState extends State<VendorsPageWidget>
    with RefreshOnPopMixin<VendorsPageWidget> {
  bool _loading = true;
  List<VendorsRow> _all = [];
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
  String? _typeFilter;
  bool _showInactive = false;

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
      _all = await VendorsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load vendors: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _types => _all
      .map((v) => v.vendorType)
      .whereType<String>()
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  List<VendorsRow> get _filtered {
    var rows = _all;
    if (!_showInactive) rows = rows.where((v) => v.active).toList();
    if (_typeFilter != null) rows = rows.where((v) => v.vendorType == _typeFilter).toList();
    if (_search.trim().isNotEmpty) {
      final term = _search.trim().toLowerCase();
      rows = rows
          .where((v) =>
              v.name.toLowerCase().contains(term) ||
              (v.phone ?? '').toLowerCase().contains(term) ||
              (v.city ?? '').toLowerCase().contains(term))
          .toList();
    }
    return rows;
  }

  Future<void> _newVendor() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String type = 'other';
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('New Vendor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  autofocus: true),
              TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Vendor Type'),
                items: const [
                  DropdownMenuItem(value: 'porter', child: Text('Porter')),
                  DropdownMenuItem(value: 'vehicle', child: Text('Vehicle Owner')),
                  DropdownMenuItem(
                      value: 'packing_material', child: Text('Packing Material')),
                  DropdownMenuItem(value: 'labour', child: Text('Labour Contractor')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setDialogState(() => type = v ?? 'other'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: nameCtrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (created != true || nameCtrl.text.trim().isEmpty) return;
    try {
      final inserted = await VendorsTable().insert({
        ...OrgScope.stamp(),
        'name': nameCtrl.text.trim(),
        'vendor_type': type,
        if (phoneCtrl.text.trim().isNotEmpty) 'phone': phoneCtrl.text.trim(),
      });
      await _load();
      if (mounted && inserted.id != null) {
        context.pushNamed(
          VendorDetailPageWidget.routeName,
          queryParameters: {'vendorId': serializeParam(inserted.id, ParamType.String)},
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create vendor: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    String pretty(String t) =>
        t.isEmpty ? t : (t[0].toUpperCase() + t.substring(1)).replaceAll('_', ' ');
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
                  NgModuleHeader('Vendors', actions: [
                    NgPrimaryButton(
                      compact: true,
                      height: 40,
                      icon: Icons.add_rounded,
                      label: 'New vendor',
                      onPressed: _newVendor,
                    ),
                  ]),
                  const SizedBox(height: 14),
                  NgSearchField(
                    controller: _searchCtrl,
                    hint: 'Search name, phone or city',
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 14),
                  NgChipRow(edge: 0, chips: [
                    NgChip(
                        label: 'All',
                        selected: _typeFilter == null,
                        onTap: () => setState(() => _typeFilter = null)),
                    for (final t in _types)
                      NgChip(
                          label: pretty(t),
                          selected: _typeFilter == t,
                          onTap: () => setState(() => _typeFilter = t)),
                  ]),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: NgSecondaryButton(
                      height: 36,
                      icon: _showInactive
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      label: _showInactive ? 'Hide inactive' : 'Show inactive',
                      onPressed: () =>
                          setState(() => _showInactive = !_showInactive),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_filtered.isEmpty)
                    NgCard(
                      child: Text('No vendors found.',
                          textAlign: TextAlign.center,
                          style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                    )
                  else
                    NgCardList(children: [
                      for (final v in _filtered)
                        NgListRow(
                          onTap: () => context.pushNamed(
                            VendorDetailPageWidget.routeName,
                            queryParameters: {
                              'vendorId': serializeParam(v.id, ParamType.String)
                            },
                          ),
                          leading: NgAvatar(v.name),
                          title: v.name,
                          subtitle: [
                            if ((v.vendorType ?? '').isNotEmpty)
                              pretty(v.vendorType!),
                            if ((v.phone ?? '').isNotEmpty) v.phone!,
                            if ((v.city ?? '').isNotEmpty) v.city!,
                          ].join(' · '),
                          trailing: v.active
                              ? Icon(Icons.chevron_right_rounded,
                                  size: 20, color: c.faint)
                              : const NgPill('Inactive',
                                  status: NgStatus.red),
                        ),
                    ]),
                ],
              ),
            ),
    );
  }
}
