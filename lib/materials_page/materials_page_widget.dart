import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/components/load_error_state.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import 'material_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  bool _showLowStockOnly = false;
  String? _loadError;

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
    // Hang follow-up (7 Aug 2026): this query used to be unguarded — if it
    // threw or (before table.dart's new query timeout) simply never
    // resolved, safeSetState below was never reached and the page stayed
    // on "Loading…" forever with nothing to say why. Now a failure is a
    // real, retryable error state instead of a silent freeze.
    try {
      _model.materialsOut = await MaterialsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name'),
      );
      _model.materialsList =
          (_model.materialsOut ?? []).toList().cast<MaterialsRow>();
      _loadError = null;
    } catch (e) {
      _loadError = 'Could not load materials: $e';
      safeSetState(() {});
      return;
    }
    safeSetState(() {});
  }

  @override
  void dispose() {
    _model.dispose();
    _searchCtrl.dispose();

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

  // Item 11 sweep (16 Aug 2026): materials had soft-delete columns and a
  // working recycle-bin entry but no delete UI anywhere to reach it from.
  Future<void> _deleteMaterial(MaterialsRow m) async {
    final deleted = await DeleteAction.run(
      context,
      table: 'materials',
      id: m.id!,
      entityLabel: 'material',
      check: () => SoftDeleteService.canDeleteMaterial(m),
      onDeleted: _loadMaterials,
    );
    if (deleted) await _loadMaterials();
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

  final _searchCtrl = TextEditingController();

  Widget _materialRow(BuildContext context, MaterialsRow m) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final low = _isLow(m);
    final unit = (m.unit ?? '').trim();
    final qty = (m.quantity ?? 0);
    return InkWell(
      onTap: m.id == null ? null : () => _openMaterial(m.id!),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NgFonts.geist(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: c.text)),
                      ),
                      if (low) ...[
                        const SizedBox(width: 6),
                        NgPill(l.ngMatReorderSoon, status: NgStatus.amber),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if ((m.category ?? '').trim().isNotEmpty)
                        m.category!.trim(),
                      if ((m.sku ?? '').trim().isNotEmpty) m.sku!.trim(),
                      if (m.isReturnable == true) l.ngMatReturnable,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 1)} $unit'.trim(),
                    style: NgFonts.mono(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: low ? c.acc : c.text)),
                if ((m.minStock ?? 0) > 0)
                  Text(l.ngMatMin(m.minStock!.toStringAsFixed(0)),
                      style: NgFonts.geist(fontSize: 11.5, color: c.faint)),
              ],
            ),
            IconButton(
              tooltip: l.ngMatDelete,
              icon: Icon(Icons.delete_outline_rounded,
                  size: 19, color: c.faint),
              onPressed: m.id == null ? null : () => _deleteMaterial(m),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final q = _searchCtrl.text.trim().toLowerCase();
    final all = _model.materialsList
        .where((m) =>
            q.isEmpty ||
            m.name.toLowerCase().contains(q) ||
            (m.sku ?? '').toLowerCase().contains(q) ||
            (m.category ?? '').toLowerCase().contains(q))
        .toList();
    final low = all.where(_isLow).toList();
    final shown = _showLowStockOnly ? low : all;
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _loadMaterials),
      body: RefreshIndicator(
        onRefresh: _loadMaterials,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            NgModuleHeader(
              l.ngMenuMaterials,
              actions: [
                NgPrimaryButton(
                  compact: true,
                  height: 40,
                  icon: Icons.add_rounded,
                  label: l.ngMatNew,
                  onPressed: _newMaterial,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loadError != null)
              LoadErrorState(message: _loadError!, onRetry: _loadMaterials)
            else ...[
              NgSearchField(
                controller: _searchCtrl,
                hint: l.ngMatSearch,
                onChanged: (_) => safeSetState(() {}),
              ),
              const SizedBox(height: 14),
              NgChipRow(
                edge: 0,
                chips: [
                  NgChip(
                    label: l.ngTabAll,
                    count: all.length,
                    selected: !_showLowStockOnly,
                    onTap: () =>
                        safeSetState(() => _showLowStockOnly = false),
                  ),
                  NgChip(
                    label: l.ngMatReorderSoon,
                    count: low.length,
                    selected: _showLowStockOnly,
                    onTap: () => safeSetState(() => _showLowStockOnly = true),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (shown.isEmpty)
                NgCard(
                  child: Text(l.ngMatNone,
                      textAlign: TextAlign.center,
                      style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                )
              else
                NgCardList(children: [
                  for (final m in shown) _materialRow(context, m),
                ]),
            ],
          ],
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
