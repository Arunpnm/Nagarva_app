import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/material_usage.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Materials used on this order, recorded FROM the order.
///
/// Arun, 3 Sept 2026: *"i need this materials usage within orders page not
/// separate ... so that it will be easy to track"*.
///
/// Before this, recording a carton against a job meant leaving the order,
/// finding the material in the Materials list, opening Stock Out, and
/// TYPING the 19-character order id by hand. Two consequences, both real:
/// nobody would do it mid-job, and a typo hit a foreign key and came back
/// as a raw Postgres error. Here the order is already known, so there is
/// no id to type and no id to get wrong.
///
/// The section also answers "how many boxes went on this job" directly —
/// previously that was only visible by reading the material's own
/// movement history and picking out the rows mentioning this order.
///
/// Writes go through [MaterialUsage.record], the same call the Materials
/// page uses, so the cost movement and the optional customer charge can
/// never drift apart between the two screens.
class OrderMaterialsSection extends StatefulWidget {
  const OrderMaterialsSection({
    super.key,
    required this.orderId,
    this.onChanged,
    this.readOnly = false,
  });

  final String orderId;

  /// Fires after a write so Order Details can reload the P&L — materials
  /// are a cost there, and a charged material is also revenue.
  final VoidCallback? onChanged;

  final bool readOnly;

  @override
  State<OrderMaterialsSection> createState() => OrderMaterialsSectionState();
}

class OrderMaterialsSectionState extends State<OrderMaterialsSection> {
  bool _loading = true;
  String? _error;

  /// Consumption rows for this order, with the material name resolved.
  List<({String name, double qty, double value})> _used = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final moves = await StockMovementsTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eq('order_id', widget.orderId)
            .eq('movement_type', 'consumption'),
      );
      final names = <String, String>{};
      if (moves.isNotEmpty) {
        final mats = await MaterialsTable().queryRows(
          queryFn: (q) => OrgScope.read(q),
        );
        for (final m in mats) {
          if (m.id != null) names[m.id!] = m.name;
        }
      }
      if (!mounted) return;
      setState(() {
        _used = [
          for (final mv in moves)
            (
              name: names[mv.materialId] ?? 'Material',
              // Stored negative (stock leaving); shown positive.
              qty: mv.quantity.abs(),
              value: mv.value.abs(),
            ),
        ];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load materials: $e';
        _loading = false;
      });
    }
  }

  double get _totalCost => _used.fold(0.0, (s, r) => s + r.value);

  Future<void> _addMaterial() async {
    List<MaterialsRow> materials;
    try {
      materials = await MaterialsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name', ascending: true),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load materials: $e');
      return;
    }
    // Only what there is stock of. Offering an out-of-stock item leads
    // straight to a negative balance nobody meant to create.
    final inStock =
        materials.where((m) => (m.quantity ?? 0) > 0).toList();
    if (!mounted) return;
    if (inStock.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No materials in stock. Add stock on the '
              'Materials page first.')));
      return;
    }

    final picked = await showDialog<_UsageInput>(
      context: context,
      builder: (_) => _AddMaterialDialog(materials: inStock),
    );
    if (picked == null) return;

    try {
      final msg = await MaterialUsage.record(
        material: picked.material,
        qty: picked.qty,
        orderId: widget.orderId,
        billToCustomer: picked.billToCustomer,
      );
      await _load();
      widget.onChanged?.call();
      if (mounted && msg != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not record usage: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 18, color: theme.primary),
              const SizedBox(width: 8),
              Text('Materials Used',
                  style: GoogleFonts.interTight(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryText)),
              const Spacer(),
              if (!widget.readOnly)
                TextButton.icon(
                  onPressed: _addMaterial,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_used.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Cartons, tape, bubble wrap used on this job. Recorded here '
                'it counts as a cost on this order — and if the customer is '
                'buying them, it is charged to them too.',
                style:
                    GoogleFonts.inter(fontSize: 12, color: theme.secondaryText),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            for (final r in _used)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${_qty(r.qty)} × ${r.name}',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.primaryText)),
                    ),
                    Text('₹${r.value.toStringAsFixed(0)}',
                        style: GoogleFonts.interTight(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.primaryText)),
                  ],
                ),
              ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text('Material cost on this job',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: theme.secondaryText)),
                ),
                Text('₹${_totalCost.toStringAsFixed(0)}',
                    style: GoogleFonts.interTight(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryText)),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: GoogleFonts.inter(fontSize: 12, color: theme.error)),
          ],
        ],
      ),
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
}

class _UsageInput {
  const _UsageInput(this.material, this.qty, this.billToCustomer);
  final MaterialsRow material;
  final double qty;
  final bool billToCustomer;
}

class _AddMaterialDialog extends StatefulWidget {
  const _AddMaterialDialog({required this.materials});
  final List<MaterialsRow> materials;

  @override
  State<_AddMaterialDialog> createState() => _AddMaterialDialogState();
}

class _AddMaterialDialogState extends State<_AddMaterialDialog> {
  late MaterialsRow _selected = widget.materials.first;
  final _qtyCtrl = TextEditingController();
  bool _bill = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final price = _selected.sellingPrice ?? 0;
    final onHand = _selected.quantity ?? 0;
    return AlertDialog(
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      title: const Text('Add material to this job'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selected.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Material'),
            items: [
              for (final m in widget.materials)
                DropdownMenuItem(
                  value: m.id,
                  child: Text(
                      '${m.name}  ·  ${(m.quantity ?? 0).toStringAsFixed(0)} in stock',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _selected = widget.materials
                .firstWhere((m) => m.id == v, orElse: () => _selected)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _qtyCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Quantity used',
                helperText: '${onHand.toStringAsFixed(0)} in stock'),
          ),
          const SizedBox(height: 6),
          // OFF by default: materials used on a job are the normal case.
          // Defaulting to "charge them" would put money on a bill nobody
          // agreed to.
          CheckboxListTile(
            value: _bill,
            onChanged: (v) => setState(() => _bill = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('Customer is paying for these'),
            subtitle: Text(price > 0
                ? 'Adds ₹${price.toStringAsFixed(0)} each to this order.'
                : 'No selling price set on this material, so nothing can '
                    'be charged.'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!,
                  style: TextStyle(
                      fontSize: 12, color: FlutterFlowTheme.of(context).error)),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final q = double.tryParse(_qtyCtrl.text.trim());
            if (q == null || q <= 0) {
              setState(() => _error = 'Enter a quantity.');
              return;
            }
            if (q > onHand) {
              setState(() =>
                  _error = 'Only ${onHand.toStringAsFixed(0)} in stock.');
              return;
            }
            Navigator.of(context).pop(_UsageInput(_selected, q, _bill));
          },
          child: const Text('Record'),
        ),
      ],
    );
  }
}
