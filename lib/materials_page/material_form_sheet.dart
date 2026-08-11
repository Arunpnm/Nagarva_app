import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Add/Restock form for MaterialsPage — resolves the "Add/Restock form not
/// built yet" TODO left in materials_page_widget.dart during the Phase 2
/// pass (see CLAUDE.md/NAGARVA_DEV_LOG.md).
///
/// Opens as a modal bottom sheet, mirroring users_page/staff_form_sheet.dart's
/// pattern: pass [existing] to edit/restock an SKU, null to add a new one.
/// Inserts stamp org_id via OrgScope.stamp(); updates go through
/// OrgScope.write() per the repo's org-scoping convention (see
/// lib/backend/supabase/org_scope.dart).
///
/// Fields follow the live `materials` table (see
/// lib/backend/supabase/database/tables/materials.dart): name, unit,
/// quantity, min_stock, cost_per_unit. `last_updated` is stamped with the
/// current time on every save so MaterialsPage could later sort/show
/// staleness, even though nothing reads it yet.
class MaterialFormSheet extends StatefulWidget {
  const MaterialFormSheet({super.key, this.existing});

  final MaterialsRow? existing;

  /// Returns true if a row was saved (caller should reload the list).
  static Future<bool> show(BuildContext context, {MaterialsRow? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MaterialFormSheet(existing: existing),
    );
    return saved == true;
  }

  @override
  State<MaterialFormSheet> createState() => _MaterialFormSheetState();
}

class _MaterialFormSheetState extends State<MaterialFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _quantity;
  late final TextEditingController _minStock;
  late final TextEditingController _costPerUnit;
  bool _saving = false;
  String? _error;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _name = TextEditingController(text: m?.name ?? '');
    _unit = TextEditingController(text: m?.unit ?? '');
    _quantity = TextEditingController(
        text: m?.quantity == null ? '' : _trimZero(m!.quantity!));
    _minStock = TextEditingController(
        text: m?.minStock == null ? '' : _trimZero(m!.minStock!));
    _costPerUnit = TextEditingController(
        text: m?.costPerUnit == null ? '' : _trimZero(m!.costPerUnit!));
  }

  static String _trimZero(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _quantity.dispose();
    _minStock.dispose();
    _costPerUnit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'unit': _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        'quantity': double.tryParse(_quantity.text.trim()) ?? 0.0,
        'min_stock': _minStock.text.trim().isEmpty
            ? null
            : double.tryParse(_minStock.text.trim()),
        'cost_per_unit': _costPerUnit.text.trim().isEmpty
            ? null
            : double.tryParse(_costPerUnit.text.trim()),
        'last_updated': DateTime.now().toIso8601String(),
      };
      if (isEdit) {
        await MaterialsTable().update(
          data: data,
          matchingRows: (q) =>
              OrgScope.write(q).eq('id', widget.existing!.id!),
        );
      } else {
        await MaterialsTable().insert({...OrgScope.stamp(), ...data});
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  InputDecoration _dec(BuildContext context, String label, {String? hint}) {
    final theme = FlutterFlowTheme.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.inter(color: theme.secondaryText, fontSize: 13),
      hintStyle: GoogleFonts.inter(
          color: theme.secondaryText.withOpacity(0.6), fontSize: 13),
      filled: true,
      fillColor: theme.primaryBackground,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.secondaryText.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.secondaryText.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final textStyle =
        GoogleFonts.inter(color: theme.primaryText, fontSize: 14);

    return Padding(
      // Keep the sheet above the keyboard.
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 560,
        ),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme.secondaryText.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEdit ? 'Edit / Restock Item' : 'Add Material',
                      style: GoogleFonts.interTight(
                        color: theme.primaryText,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: theme.secondaryText),
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _name,
                  style: textStyle,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec(context, 'Material name *',
                      hint: 'e.g. Corrugated Box - Large'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantity,
                        style: textStyle,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*')),
                        ],
                        decoration: _dec(context, 'Quantity in stock *'),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'Required';
                          return double.tryParse(t) == null
                              ? 'Enter a number'
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _unit,
                        style: textStyle,
                        decoration: _dec(context, 'Unit', hint: 'pcs, kg…'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minStock,
                        style: textStyle,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*')),
                        ],
                        decoration: _dec(context, 'Reorder below',
                            hint: 'Low-stock threshold'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _costPerUnit,
                        style: textStyle,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*')),
                        ],
                        decoration: _dec(context, 'Cost / unit (₹)'),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style:
                        GoogleFonts.inter(color: theme.error, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            isEdit ? 'Save Changes' : 'Add Material',
                            style: GoogleFonts.interTight(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
