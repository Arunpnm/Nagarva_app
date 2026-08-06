import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
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
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text('Vendors',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _showInactive ? 'Hide Inactive' : 'Show Inactive',
            icon: Icon(_showInactive ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showInactive = !_showInactive),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newVendor,
        icon: const Icon(Icons.add),
        label: const Text('New Vendor'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search Name / Phone / City',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 8),
                  if (_types.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                            label: const Text('All'),
                            selected: _typeFilter == null,
                            onSelected: (_) => setState(() => _typeFilter = null)),
                        for (final t in _types)
                          ChoiceChip(
                              label: Text(t),
                              selected: _typeFilter == t,
                              onSelected: (_) => setState(() => _typeFilter = t)),
                      ],
                    ),
                  const SizedBox(height: 10),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('No vendors found.',
                          style: GoogleFonts.inter(color: theme.secondaryText)),
                    )
                  else
                    for (final v in _filtered) _vendorRow(theme, v),
                ],
              ),
            ),
    );
  }

  Widget _vendorRow(FlutterFlowTheme theme, VendorsRow v) {
    return InkWell(
      onTap: () => context.pushNamed(
        VendorDetailPageWidget.routeName,
        queryParameters: {'vendorId': serializeParam(v.id, ParamType.String)},
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.name,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    [
                      if ((v.vendorType ?? '').isNotEmpty) v.vendorType,
                      if ((v.phone ?? '').isNotEmpty) v.phone,
                      if ((v.city ?? '').isNotEmpty) v.city,
                    ].whereType<String>().join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            if (!v.active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.error.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Inactive', style: GoogleFonts.inter(fontSize: 10, color: theme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
