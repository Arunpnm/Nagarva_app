import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/app_session.dart';
import '/backend/audit_log_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Material detail + stock movement actions (Session 4 Materials rebuild).
///
/// `materials.quantity` is maintained ENTIRELY by the `apply_stock_movement()`
/// trigger on `stock_movements` (migration 005) — every action here inserts
/// a `stock_movements` row and never touches `quantity` directly. After each
/// insert the material row is re-fetched so what's shown reflects the
/// trigger's server-side arithmetic, not a client-side guess.
///
/// `balance_after` (stored on the movement row for the history list) IS
/// computed client-side from the material's last-known quantity — there's
/// no atomic RPC for this in migration 005, so under real concurrent writes
/// it could be briefly wrong for the history display; `materials.quantity`
/// itself is unaffected either way since the trigger does the real
/// arithmetic server-side.
Future<void> showMaterialDetailSheet(BuildContext context, String materialId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MaterialDetailSheet(materialId: materialId),
  );
}

class _MaterialDetailSheet extends StatefulWidget {
  const _MaterialDetailSheet({required this.materialId});
  final String materialId;

  @override
  State<_MaterialDetailSheet> createState() => _MaterialDetailSheetState();
}

class _MaterialDetailSheetState extends State<_MaterialDetailSheet> {
  MaterialsRow? _material;
  List<StockMovementsRow> _history = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await MaterialsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('id', widget.materialId),
    );
    final history = await StockMovementsTable().queryRows(
      queryFn: (q) => OrgScope.read(q)
          .eq('material_id', widget.materialId)
          .order('movement_date', ascending: false)
          .order('created_at', ascending: false),
    );
    if (!mounted) return;
    setState(() {
      _material = rows.isNotEmpty ? rows.first : null;
      _history = history;
      _loading = false;
    });
  }

  String _rupees(num v) => '₹${v.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  /// Inserts one stock_movements row and reloads. Shared by all three
  /// actions — the only thing that differs between Stock In/Out/Adjust is
  /// the dialog that collects [quantity]/[rate]/[note]/[orderId].
  Future<void> _recordMovement({
    required String movementType,
    required double quantity,
    double rate = 0,
    String? note,
    String? orderId,
  }) async {
    final m = _material;
    if (m == null || m.id == null) return;
    setState(() => _busy = true);
    try {
      final orgId = OrgScope.currentOrgId!;
      final before = m.quantity ?? 0;
      await StockMovementsTable().insert({
        'org_id': orgId,
        'material_id': m.id,
        'movement_type': movementType,
        'quantity': quantity,
        'rate': rate,
        'value': (quantity * rate).abs(),
        if (orderId != null && orderId.isNotEmpty) ...{
          'order_id': orderId,
          'ref_type': 'order',
        },
        'branch': m.branch,
        'balance_after': before + quantity,
        'note': note,
        'created_by': AppSession.instance.currentStaffName ?? 'Owner',
      });
      await AuditLogService.log(
        entityType: 'materials',
        entityId: m.id!,
        action: 'stock_movement',
        newValue: {
          'movement_type': movementType,
          'quantity': quantity,
          if (orderId != null) 'order_id': orderId,
        },
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Stock updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not record: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stockIn() async {
    final result = await showDialog<_MovementInput>(
      context: context,
      builder: (_) => const _StockInDialog(),
    );
    if (result == null) return;
    await _recordMovement(
      movementType: 'purchase',
      quantity: result.quantity,
      rate: result.rate,
      note: result.note,
    );
  }

  Future<void> _stockOut() async {
    final m = _material;
    if (m == null) return;
    final result = await showDialog<_MovementInput>(
      context: context,
      builder: (_) => _StockOutDialog(
          available: m.quantity ?? 0,
          sellingPrice: m.sellingPrice ?? 0),
    );
    if (result == null) return;
    await _recordMovement(
      movementType: 'consumption',
      // Always recorded at COST. The stock movement is what the material
      // cost the business; what the customer pays is a separate thing
      // and is billed below. Conflating them would make the P&L's
      // Materials line show a margin instead of a cost.
      quantity: -result.quantity,
      rate: m.costPerUnit ?? 0,
      note: result.note,
      orderId: result.orderId,
    );
    if (result.billToCustomer && (result.orderId ?? '').isNotEmpty) {
      await _billMaterialToCustomer(m, result.quantity, result.orderId!);
    }
  }

  /// Charges the customer for materials they are buying, at the
  /// material's own selling price.
  ///
  /// Arun, 3 Sept 2026: "sometimes customer will pay for the cartoons how
  /// will we track that and get that money inside the order".
  ///
  /// Before this, `materials.selling_price` was captured on every
  /// material and READ BY NOTHING. Stock going out was recorded purely as
  /// a cost, so a vendor who sold 12 cartons to a customer took the
  /// Rs1,080 hit and had no way to collect the Rs1,680 — the job looked
  /// less profitable than it was, and the money was simply never asked
  /// for.
  ///
  /// **Written as an ADD-ON, not a new revenue path.** Add-ons already
  /// flow into Revenue (Final) on the P&L, into the balance Close Order
  /// warns about, and into the Operations queue. Inventing a second way
  /// for materials to become revenue would give this app two answers to
  /// "what does this job earn", which is the disease this codebase keeps
  /// having to cure.
  ///
  /// Marked `completed` immediately: unlike an AC install booked for
  /// tomorrow, the goods have already changed hands. It is money owed,
  /// not work outstanding.
  Future<void> _billMaterialToCustomer(
      MaterialsRow m, double qty, String orderId) async {
    final unit = m.sellingPrice ?? 0;
    if (unit <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${m.name} has no selling price set, so it was '
                'recorded as used but not charged. Set one on the material '
                'to bill it.')));
      }
      return;
    }
    try {
      await SupaFlow.client.from('addons').insert({
        ...OrgScope.stamp(),
        'order_id': orderId,
        'description':
            '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)} x '
            '${m.name}',
        'amount': unit * qty,
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Charged to the order: '
                '${qty.toStringAsFixed(0)} x ${m.name}')));
      }
    } catch (e) {
      // Reported, never silent: the stock has already left and the
      // vendor needs to know the charge did not land so they can add it
      // by hand.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Stock recorded, but the charge could not be '
                'added to the order: $e')));
      }
    }
  }

  Future<void> _adjust() async {
    final result = await showDialog<_AdjustInput>(
      context: context,
      builder: (_) => const _AdjustDialog(),
    );
    if (result == null) return;
    await _recordMovement(
      movementType: result.isDamage ? 'damage' : 'adjustment',
      quantity: result.delta,
      note: result.note,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final m = _material;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : m == null
                ? const Center(child: Text('Material not found.'))
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
                      Text(m.name,
                          style: GoogleFonts.interTight(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: theme.primaryText)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if ((m.sku ?? '').isNotEmpty)
                            _tag('SKU: ${m.sku}', theme),
                          if ((m.category ?? '').isNotEmpty)
                            _tag(m.category!, theme),
                          if ((m.hsnCode ?? '').isNotEmpty)
                            _tag('HSN ${m.hsnCode}', theme),
                          if ((m.branch ?? '').isNotEmpty)
                            _tag(m.branch!, theme),
                          if (m.isReturnable ?? false) _tag('Returnable', theme),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Current Stock (read-only)',
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: theme.secondaryText)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${(m.quantity ?? 0).toStringAsFixed((m.quantity ?? 0) == (m.quantity ?? 0).roundToDouble() ? 0 : 1)} ${m.unit ?? ''}',
                                    style: GoogleFonts.interTight(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: theme.primaryText),
                                  ),
                                ],
                              ),
                            ),
                            if ((m.costPerUnit ?? 0) > 0)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Cost/Unit',
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: theme.secondaryText)),
                                  Text(_rupees(m.costPerUnit!),
                                      style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            if ((m.sellingPrice ?? 0) > 0) ...[
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Selling Price',
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: theme.secondaryText)),
                                  Text(_rupees(m.sellingPrice!),
                                      style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _stockIn,
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 18, color: Colors.green),
                              label: const Text('Stock In'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _stockOut,
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 18, color: Colors.orange),
                              label: const Text('Stock Out'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _adjust,
                              icon: const Icon(Icons.tune, size: 18),
                              label: const Text('Adjust'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text('Movement History',
                          style: GoogleFonts.interTight(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: theme.primaryText)),
                      const SizedBox(height: 8),
                      if (_history.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('No movements recorded yet.',
                              style: GoogleFonts.inter(
                                  fontSize: 12.5, color: theme.secondaryText)),
                        )
                      else
                        ..._history.map((h) => _historyRow(h, theme)),
                    ],
                  ),
      ),
    );
  }

  Widget _tag(String text, FlutterFlowTheme theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style:
                GoogleFonts.inter(fontSize: 10.5, color: theme.secondaryText)),
      );

  Widget _historyRow(StockMovementsRow h, FlutterFlowTheme theme) {
    final inbound = h.quantity >= 0;
    final dateStr = h.movementDate != null
        ? DateFormat('d MMM yyyy').format(h.movementDate!)
        : '—';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            inbound ? Icons.arrow_downward : Icons.arrow_upward,
            size: 16,
            color: inbound ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_movementLabel(h.movementType)} · ${h.quantity > 0 ? '+' : ''}${h.quantity.toStringAsFixed(h.quantity == h.quantity.roundToDouble() ? 0 : 1)}',
                  style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryText),
                ),
                Text(
                  [
                    dateStr,
                    if ((h.createdBy ?? '').isNotEmpty) h.createdBy,
                    if ((h.orderId ?? '').isNotEmpty) 'Order ${h.orderId}',
                    if ((h.note ?? '').isNotEmpty) h.note,
                  ].whereType<String>().join(' · '),
                  style: GoogleFonts.inter(
                      fontSize: 11, color: theme.secondaryText),
                ),
              ],
            ),
          ),
          if (h.balanceAfter != null)
            Text(
              'Bal: ${h.balanceAfter!.toStringAsFixed(h.balanceAfter == h.balanceAfter!.roundToDouble() ? 0 : 1)}',
              style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: theme.secondaryText),
            ),
        ],
      ),
    );
  }

  String _movementLabel(String type) {
    switch (type) {
      case 'purchase':
        return 'Stock In';
      case 'consumption':
        return 'Consumption';
      case 'return':
        return 'Return';
      case 'adjustment':
        return 'Adjustment';
      case 'transfer_in':
        return 'Transfer In';
      case 'transfer_out':
        return 'Transfer Out';
      case 'damage':
        return 'Damage';
      case 'opening':
        return 'Opening Stock';
      default:
        return type;
    }
  }
}

class _MovementInput {
  const _MovementInput(
      {required this.quantity,
      this.rate = 0,
      this.note,
      this.orderId,
      this.billToCustomer = false});
  final double quantity;
  final double rate;
  final String? note;
  final String? orderId;

  /// True when the customer is buying these, not just having them used
  /// on their job. See _stockOut for why this is a separate flag rather
  /// than something inferred from the material.
  final bool billToCustomer;
}

class _AdjustInput {
  const _AdjustInput(
      {required this.delta, required this.isDamage, this.note});
  final double delta;
  final bool isDamage;
  final String? note;
}

class _StockInDialog extends StatefulWidget {
  const _StockInDialog();
  @override
  State<_StockInDialog> createState() => _StockInDialogState();
}

class _StockInDialogState extends State<_StockInDialog> {
  final _qtyCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Stock In (Purchase)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantity received'),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Rate per unit (₹)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final qty = double.tryParse(_qtyCtrl.text.trim());
            if (qty == null || qty <= 0) return;
            final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0;
            Navigator.of(context).pop(_MovementInput(
                quantity: qty,
                rate: rate,
                note: _noteCtrl.text.trim().isEmpty
                    ? null
                    : _noteCtrl.text.trim()));
          },
          child: const Text('Add Stock'),
        ),
      ],
    );
  }
}

class _StockOutDialog extends StatefulWidget {
  const _StockOutDialog({required this.available, required this.sellingPrice});
  final double available;

  /// Shown on the "customer pays" row so the vendor sees what will be
  /// charged before ticking it, rather than after.
  final double sellingPrice;
  @override
  State<_StockOutDialog> createState() => _StockOutDialogState();
}

class _StockOutDialogState extends State<_StockOutDialog> {
  final _qtyCtrl = TextEditingController();
  final _orderCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _billToCustomer = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _orderCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Stock Out / Consumption'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available: ${widget.available.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantity used'),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _orderCtrl,
            decoration: const InputDecoration(
                labelText: 'Order ID (optional)',
                hintText: 'Feeds that order\'s P&L Materials line'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 4),
          // OFF by default. Materials used on a job are the normal case;
          // the customer buying them is the exception, and defaulting to
          // "charge them" would put money on a bill nobody agreed.
          CheckboxListTile(
            value: _billToCustomer,
            onChanged: (v) => setState(() => _billToCustomer = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('Customer is paying for these'),
            subtitle: Text(widget.sellingPrice > 0
                ? 'Adds a charge to the order at '
                    'Rs${widget.sellingPrice.toStringAsFixed(0)} each. '
                    'Needs an Order ID above.'
                : 'This material has no selling price set, so nothing can '
                    'be charged yet.'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final qty = double.tryParse(_qtyCtrl.text.trim());
            if (qty == null || qty <= 0) {
              setState(() => _error = 'Enter a valid quantity.');
              return;
            }
            if (qty > widget.available) {
              setState(() => _error =
                  'Only ${widget.available.toStringAsFixed(1)} available.');
              return;
            }
            if (_billToCustomer && _orderCtrl.text.trim().isEmpty) {
              setState(() => _error =
                  'Enter the Order ID to charge the customer for these.');
              return;
            }
            Navigator.of(context).pop(_MovementInput(
              quantity: qty,
              orderId:
                  _orderCtrl.text.trim().isEmpty ? null : _orderCtrl.text.trim(),
              note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
              billToCustomer: _billToCustomer,
            ));
          },
          child: const Text('Record Usage'),
        ),
      ],
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog();
  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _qtyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _increase = true;
  bool _isDamage = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adjustment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Increase')),
              ButtonSegment(value: false, label: Text('Decrease')),
            ],
            selected: {_increase},
            onSelectionChanged: (s) => setState(() => _increase = s.first),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantity'),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _isDamage,
            onChanged: (v) => setState(() => _isDamage = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Damage / write-off'),
          ),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
                labelText: 'Reason (required)',
                hintText: 'e.g. physical count correction'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final qty = double.tryParse(_qtyCtrl.text.trim());
            if (qty == null || qty <= 0) {
              setState(() => _error = 'Enter a valid quantity.');
              return;
            }
            if (_noteCtrl.text.trim().isEmpty) {
              setState(() => _error = 'A reason is required.');
              return;
            }
            Navigator.of(context).pop(_AdjustInput(
              delta: _increase ? qty : -qty,
              isDamage: _isDamage,
              note: _noteCtrl.text.trim(),
            ));
          },
          child: const Text('Save Adjustment'),
        ),
      ],
    );
  }
}
