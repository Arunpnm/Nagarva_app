import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'material_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'materials_page_model.dart';
export 'materials_page_model.dart';

/// Packing material inventory management (Session 4 rebuild).
///
/// Was a read-only list with a stub "Add/Restock" button that only ever
/// showed a SnackBar — nothing anywhere wrote to `materials.quantity` or
/// `stock_movements`. `materials.quantity` is now maintained entirely by
/// the `apply_stock_movement()` trigger on `stock_movements` (migration
/// 005) — this page never writes `quantity` directly; every stock change
/// goes through [showMaterialDetailSheet]'s Stock In/Out/Adjust actions.
class MaterialsPageWidget extends StatefulWidget {
  const MaterialsPageWidget({super.key});

  static String routeName = 'MaterialsPage';
  static String routePath = '/materials';

  @override
  State<MaterialsPageWidget> createState() => _MaterialsPageWidgetState();
}

class _MaterialsPageWidgetState extends State<MaterialsPageWidget>
    with RefreshOnPopMixin<MaterialsPageWidget> {
  late MaterialsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<LowStockViewRow> _lowStock = [];
  bool _showLowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => MaterialsPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) => _loadMaterials());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1) — also catches the
  // detail sheet's own stock movements, since it's a bottom sheet on this
  // same route rather than a pushed one; _loadMaterials is called directly
  // after the sheet closes too (see _openMaterial).
  @override
  void onPageRefresh() => _loadMaterials();

  Future<void> _loadMaterials() async {
    _model.materialsOut = await MaterialsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).order('name'),
    );
    _model.materialsList =
        (_model.materialsOut ?? []).toList().cast<MaterialsRow>();
    try {
      _lowStock = await LowStockViewTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name'),
      );
    } catch (_) {
      // low_stock_view may not exist yet on an org whose migration 005
      // hasn't been run — the page still works off materials.quantity/
      // min_stock for the plain list either way.
      _lowStock = [];
    }
    safeSetState(() {});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  bool _isLow(MaterialsRow m) {
    final qty = m.quantity ?? 0;
    final min = m.minStock ?? 0;
    return min > 0 && qty <= min;
  }

  Future<void> _openMaterial(String id) async {
    await showMaterialDetailSheet(context, id);
    if (mounted) _loadMaterials();
  }

  Future<void> _newMaterial() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _NewMaterialDialog(),
    );
    if (result == null) return;
    try {
      final inserted =
          await MaterialsTable().insert({...OrgScope.stamp(), ...result});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${inserted.name} added.')));
      // A brand-new material starts at 0 — no opening stock_movements row
      // unless the user immediately does a Stock In, which is the more
      // honest record (an explicit "purchase" entry) than silently
      // fabricating an 'opening' row for a material that never had stock.
      await _loadMaterials();
      if (inserted.id != null) await _openMaterial(inserted.id!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not add material: $e')));
    }
  }

  Widget _statCard(BuildContext context, String label, String value,
      {bool danger = false}) {
    return Flexible(
      flex: 1,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: FlutterFlowTheme.of(context).labelMedium.override(
                      font: GoogleFonts.inter(),
                      color: FlutterFlowTheme.of(context).secondaryText,
                      letterSpacing: 0.0,
                    ),
              ),
              Text(
                value,
                style: FlutterFlowTheme.of(context).headlineMedium.override(
                      font: GoogleFonts.interTight(),
                      color: danger
                          ? FlutterFlowTheme.of(context).error
                          : FlutterFlowTheme.of(context).primaryText,
                      letterSpacing: 0.0,
                    ),
              ),
            ].divide(const SizedBox(height: 4.0)),
          ),
        ),
      ),
    );
  }

  Widget _materialRow(BuildContext context, MaterialsRow m) {
    final low = _isLow(m);
    final qtyLabel =
        '${(m.quantity ?? 0).toStringAsFixed(m.quantity == m.quantity?.roundToDouble() ? 0 : 1)} ${m.unit ?? ''}'
            .trim();
    return InkWell(
      onTap: m.id == null ? null : () => _openMaterial(m.id!),
      borderRadius: BorderRadius.circular(10.0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16.0, 14.0, 16.0, 14.0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(),
                            color: FlutterFlowTheme.of(context).primaryText,
                            letterSpacing: 0.0,
                          ),
                    ),
                    Text(
                      [
                        if ((m.category ?? '').isNotEmpty) m.category,
                        low
                            ? 'Reorder < ${(m.minStock ?? 0).toStringAsFixed(0)}'
                            : 'OK',
                      ].whereType<String>().join(' · '),
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            font: GoogleFonts.inter(),
                            color: low
                                ? FlutterFlowTheme.of(context).error
                                : FlutterFlowTheme.of(context).secondaryText,
                            letterSpacing: 0.0,
                          ),
                    ),
                  ].divide(const SizedBox(height: 3.0)),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).primaryBackground,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      10.0, 4.0, 10.0, 4.0),
                  child: Text(
                    qtyLabel,
                    style: FlutterFlowTheme.of(context).labelMedium.override(
                          font: GoogleFonts.inter(),
                          color: low
                              ? FlutterFlowTheme.of(context).error
                              : FlutterFlowTheme.of(context).primaryText,
                          letterSpacing: 0.0,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allMaterials = _model.materialsList;
    final lowStockCount = allMaterials.where(_isLow).length;
    final materials =
        _showLowStockOnly ? allMaterials.where(_isLow).toList() : allMaterials;
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            FFLocalizations.of(context).getText(
              '95925ruu' /* Materials */,
            ),
            style: theme.titleLarge.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w600,
                ),
          ),
          actions: const [],
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(color: theme.primaryBackground),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        _statCard(context, 'Total SKUs', '${allMaterials.length}'),
                        InkWell(
                          onTap: lowStockCount == 0
                              ? null
                              : () => setState(
                                  () => _showLowStockOnly = !_showLowStockOnly),
                          borderRadius: BorderRadius.circular(12),
                          child: _statCard(context, 'Low Stock', '$lowStockCount',
                              danger: lowStockCount > 0),
                        ),
                      ].divide(const SizedBox(width: 12.0)),
                    ),
                    if (_lowStock.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: 16, color: theme.error),
                                const SizedBox(width: 6),
                                Text('Reorder soon',
                                    style: GoogleFonts.interTight(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: theme.error)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (final l in _lowStock.take(5))
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '${l.name}: ${(l.quantity ?? 0).toStringAsFixed(0)} '
                                  '${l.unit ?? ''} left'
                                  '${l.reorderQty != null && l.reorderQty! > 0 ? ' — reorder ${l.reorderQty!.toStringAsFixed(0)}' : ''}',
                                  style: GoogleFonts.inter(
                                      fontSize: 12, color: theme.secondaryText),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _showLowStockOnly ? 'Inventory (low stock)' : 'Inventory',
                          style: theme.titleMedium.override(
                                font: GoogleFonts.interTight(),
                                color: theme.primaryText,
                                letterSpacing: 0.0,
                              ),
                        ),
                        if (_showLowStockOnly)
                          TextButton(
                            onPressed: () =>
                                setState(() => _showLowStockOnly = false),
                            child: const Text('Show all'),
                          ),
                      ],
                    ),
                    if (materials.isEmpty)
                      Text(
                        _model.materialsOut == null
                            ? 'Loading…'
                            : _showLowStockOnly
                                ? 'Nothing low on stock.'
                                : 'No materials tracked yet for this org.',
                        style: theme.bodySmall.override(
                              font: GoogleFonts.inter(),
                              color: theme.secondaryText,
                            ),
                      )
                    else
                      ...materials.map((m) => _materialRow(context, m)),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 16.0, 0.0, 16.0),
                      child: FFButtonWidget(
                        onPressed: _newMaterial,
                        text: 'New Material',
                        icon: const Icon(
                          Icons.add_box,
                          size: 20.0,
                        ),
                        options: FFButtonOptions(
                          width: double.infinity,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconColor: theme.primaryBackground,
                          color: theme.primary,
                          textStyle: TextStyle(color: theme.primaryBackground),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),
                  ].divide(const SizedBox(height: 16.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewMaterialDialog extends StatefulWidget {
  const _NewMaterialDialog();
  @override
  State<_NewMaterialDialog> createState() => _NewMaterialDialogState();
}

class _NewMaterialDialogState extends State<_NewMaterialDialog> {
  final _nameCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'pcs');
  final _categoryCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _hsnCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _minStockCtrl = TextEditingController();
  final _reorderQtyCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _sellingCtrl = TextEditingController();
  bool _isReturnable = false;

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _unitCtrl,
      _categoryCtrl,
      _skuCtrl,
      _hsnCtrl,
      _branchCtrl,
      _minStockCtrl,
      _reorderQtyCtrl,
      _costCtrl,
      _sellingCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Material'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true,
              ),
              TextField(
                controller: _unitCtrl,
                decoration: const InputDecoration(labelText: 'Unit (pcs/box/kg…)'),
              ),
              TextField(
                controller: _categoryCtrl,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _skuCtrl,
                      decoration: const InputDecoration(labelText: 'SKU'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _hsnCtrl,
                      decoration: const InputDecoration(labelText: 'HSN Code'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _branchCtrl,
                decoration: const InputDecoration(labelText: 'Branch'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minStockCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Min Stock'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _reorderQtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Reorder Qty'),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Cost/Unit (₹)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _sellingCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Selling Price (₹)'),
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                value: _isReturnable,
                onChanged: (v) => setState(() => _isReturnable = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Returnable (e.g. crates, dollies)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop({
              'name': name,
              'unit': _unitCtrl.text.trim().isEmpty ? null : _unitCtrl.text.trim(),
              'category': _categoryCtrl.text.trim().isEmpty
                  ? null
                  : _categoryCtrl.text.trim(),
              'sku': _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
              'hsn_code':
                  _hsnCtrl.text.trim().isEmpty ? null : _hsnCtrl.text.trim(),
              'branch': _branchCtrl.text.trim().isEmpty
                  ? null
                  : _branchCtrl.text.trim(),
              'min_stock': double.tryParse(_minStockCtrl.text.trim()) ?? 0,
              'reorder_qty':
                  double.tryParse(_reorderQtyCtrl.text.trim()) ?? 0,
              'cost_per_unit': double.tryParse(_costCtrl.text.trim()) ?? 0,
              'selling_price': double.tryParse(_sellingCtrl.text.trim()) ?? 0,
              'is_returnable': _isReturnable,
              'quantity': 0,
            });
          },
          child: const Text('Add Material'),
        ),
      ],
    );
  }
}
