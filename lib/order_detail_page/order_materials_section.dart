import 'package:flutter/material.dart';
import '/flutter_flow/custom_functions.dart' as functions;

import '/backend/material_usage.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

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
        chargeAmount: picked.chargeAmount,
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
    final ng = NgPalette.of(context);
    return NgSectionCard(
      title: 'Materials used',
      icon: Icons.inventory_2_outlined,
      trailing: widget.readOnly
          ? null
          : NgLinkButton('Add', icon: Icons.add_rounded, onTap: _addMaterial),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (_used.isEmpty)
            Text(
              'Cartons, tape, bubble wrap used on this job. Recorded here '
              'it counts as a cost on this order — and if the customer is '
              'buying them, it is charged to them too.',
              style: NgFonts.geist(fontSize: 13, height: 1.4, color: ng.mute),
            )
          else ...[
            for (final r in _used)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: ng.s3,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('${_qty(r.qty)}×',
                          style: NgFonts.mono(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: ng.soft)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(r.name,
                          style: NgFonts.geist(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: ng.text)),
                    ),
                    Text(functions.inrFull(r.value),
                        style: NgFonts.mono(fontSize: 13.5, color: ng.text)),
                  ],
                ),
              ),
            Divider(height: 18, color: ng.w06),
            NgKeyValue('Material cost on this job',
                functions.inrFull(_totalCost),
                mono: true, strong: true),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: NgFonts.geist(fontSize: 12.5, color: ng.red)),
          ],
        ],
      ),
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
}

class _UsageInput {
  const _UsageInput(
      this.material, this.qty, this.billToCustomer, this.chargeAmount);
  final MaterialsRow material;
  final double qty;
  final bool billToCustomer;

  /// What to charge. Null when not billing.
  final double? chargeAmount;
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
  final _chargeCtrl = TextEditingController();
  bool _bill = false;

  /// True once the vendor types in the charge box.
  ///
  /// After that the suggested figure stops overwriting it. Changing the
  /// quantity must not silently undo a negotiated price - the same rule
  /// Add Labour got after the staff dropdown was found clobbering a
  /// typed amount.
  bool _chargeTouched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _chargeCtrl.addListener(() {
      if (!_chargeTouched) _chargeTouched = true;
    });
  }

  /// Refreshes the suggested charge from the vendor's own selling price,
  /// unless they have already typed their own figure.
  void _suggestCharge() {
    if (_chargeTouched) return;
    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final price = _selected.sellingPrice ?? 0;
    final v = price * qty;
    final text = v <= 0 ? '' : v.toStringAsFixed(0);
    if (_chargeCtrl.text != text) {
      _chargeCtrl.value = TextEditingValue(text: text);
      _chargeTouched = false;
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _chargeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final price = _selected.sellingPrice ?? 0;
    final onHand = _selected.quantity ?? 0;
    return AlertDialog(
      backgroundColor: NgPalette.of(context).s1,
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
            onChanged: (v) => setState(() {
              _selected = widget.materials
                  .firstWhere((m) => m.id == v, orElse: () => _selected);
              _suggestCharge();
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _qtyCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Quantity used',
                helperText: '${onHand.toStringAsFixed(0)} in stock'),
            onChanged: (_) => setState(_suggestCharge),
          ),
          const SizedBox(height: 6),
          // OFF by default: materials used on a job are the normal case.
          // Defaulting to "charge them" would put money on a bill nobody
          // agreed to.
          CheckboxListTile(
            value: _bill,
            onChanged: (v) => setState(() {
              _bill = v ?? false;
              if (_bill) _suggestCharge();
            }),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('Customer is paying for these'),
            subtitle: Text(price > 0
                ? 'Suggested ₹${price.toStringAsFixed(0)} each - edit below '
                    'if you agreed a different price.'
                : 'No selling price set on this material. Type what you '
                    'agreed below.'),
          ),
          if (_bill)
            TextField(
              controller: _chargeCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Charge to customer',
                helperText: 'Total for this line, not per unit',
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!,
                  style: TextStyle(
                      fontSize: 12, color: NgPalette.of(context).red)),
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
            final charge = double.tryParse(_chargeCtrl.text.trim());
            if (_bill && (charge == null || charge <= 0)) {
              setState(() =>
                  _error = 'Enter what the customer is being charged.');
              return;
            }
            Navigator.of(context)
                .pop(_UsageInput(_selected, q, _bill, _bill ? charge : null));
          },
          child: const Text('Record'),
        ),
      ],
    );
  }
}
