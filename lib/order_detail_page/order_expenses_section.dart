import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/field_expenses.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// What this job COST — fuel, tolls, a carpenter, an extra vehicle.
///
/// Arun, 3 Sept 2026: *"in order expense i think we have all typr of
/// expense like ac uninstall and install plumber extra veh, diesel etc
/// etc"*. He was right that the categories existed; the problem was
/// WHERE. They lived only on the supervisor's Field Job screen, so an
/// owner looking at an order could see "Order Expenses (0 items)" on the
/// P&L and have no way to add one. The owner's only route was Quick
/// Expense, then remembering to link the order.
///
/// **This is the cost side. `OrderAddonsSection` is the charge side.**
/// The same words appear in both and that is correct, not a duplication:
/// on one job you pay the AC technician 800 and charge the customer
/// 2,500. One is money out, the other money in, and a job needs both
/// recorded or its profit is fiction. The two sections sit next to each
/// other so the pair is obvious.
///
/// **Two stores, deliberately read together.** A supervisor's on-site
/// entries land in `orders.field_expenses` (jsonb); anything captured in
/// the office lands in the `expenses` table with `order_id` set. The P&L
/// already sums both, so this section shows both — otherwise the section
/// and the P&L line directly above it would disagree, which is the
/// disease this codebase keeps curing.
///
/// New entries are written to the `expenses` TABLE, not the jsonb: a real
/// row also reaches the Expenses page, the Daily Accounts Register and
/// the P&L report. The jsonb is the supervisor's field capture and stays
/// read-only here.
class OrderExpensesSection extends StatefulWidget {
  const OrderExpensesSection({
    super.key,
    required this.orderId,
    this.onChanged,
    this.readOnly = false,
  });

  final String orderId;
  final VoidCallback? onChanged;
  final bool readOnly;

  @override
  State<OrderExpensesSection> createState() => OrderExpensesSectionState();
}

/// The categories a mover actually spends on.
///
/// Same list the supervisor's Field Job screen offers, so the two
/// capture paths cannot describe the same spend differently — an
/// expense typed as "Diesel" in one place and "Fuel" in the other is
/// two lines in a report that should have been one.
const kOrderExpenseCategories = <String>[
  'Fuel',
  'Toll',
  'Loading/Unloading',
  'Packing Material',
  'Food',
  'Extra vehicle',
  'AC install/uninstall',
  'TV install/uninstall',
  'Geyser install/uninstall',
  'Carpenter',
  'Plumber',
  'Crane/hydra',
  'Parking',
  'Vehicle repair',
  'Cleaning',
  'Miscellaneous',
];

class OrderExpensesSectionState extends State<OrderExpensesSection> {
  bool _loading = true;
  String? _error;

  /// (label, amount, fromField) — fromField marks a supervisor entry,
  /// which is shown but not editable here.
  List<({String label, double amount, bool fromField})> _rows = const [];

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
      final expenses = await ExpensesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId),
      );
      final orders = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId),
        limit: 1,
      );

      final out = <({String label, double amount, bool fromField})>[];
      for (final e in expenses) {
        out.add((
          label: (e.category ?? '').trim().isEmpty
              ? 'Expense'
              : e.category!.trim(),
          amount: e.amount ?? 0,
          fromField: false,
        ));
      }
      if (orders.isNotEmpty) {
        final raw = orders.first.data['field_expenses'];
        if (raw is List) {
          for (final e in raw) {
            if (e is! Map) continue;
            final amt = num.tryParse('${e['amount']}')?.toDouble() ?? 0;
            if (amt == 0) continue;
            out.add((
              label: '${e['type'] ?? 'Field expense'}',
              amount: amt,
              fromField: true,
            ));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load expenses: $e';
        _loading = false;
      });
    }
  }

  double get _total => _rows.fold(0.0, (s, r) => s + r.amount);

  Future<void> _add() async {
    final picked = await showDialog<({String category, double amount, String? note})>(
      context: context,
      builder: (_) => const _AddExpenseDialog(),
    );
    if (picked == null) return;
    try {
      await ExpensesTable().insert({
        ...OrgScope.stamp(),
        'amount': picked.amount,
        'category': picked.category,
        'date': DateTime.now().toIso8601String().split('T').first,
        'order_id': widget.orderId,
        if ((picked.note ?? '').trim().isNotEmpty)
          'description': picked.note!.trim(),
      });
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save expense: $e');
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
              Icon(Icons.receipt_long_outlined, size: 18, color: theme.error),
              const SizedBox(width: 8),
              Text('Job Expenses',
                  style: GoogleFonts.interTight(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryText)),
              const Spacer(),
              if (!widget.readOnly)
                TextButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
            ],
          ),
          Text('What this job cost you — not what the customer is charged.',
              style:
                  GoogleFonts.inter(fontSize: 11, color: theme.secondaryText)),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Diesel, tolls, a carpenter, an extra vehicle. Recorded here '
                'they come off this job\'s profit.',
                style:
                    GoogleFonts.inter(fontSize: 12, color: theme.secondaryText),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            for (final r in _rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(r.label,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: theme.primaryText)),
                          ),
                          if (r.fromField) ...[
                            const SizedBox(width: 6),
                            // Marked so the owner knows this came from the
                            // crew on site and is not editable here.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('from site',
                                  style: GoogleFonts.inter(
                                      fontSize: 9, color: theme.primary)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text('₹${r.amount.toStringAsFixed(0)}',
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
                  child: Text('Total spent on this job',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: theme.secondaryText)),
                ),
                Text('₹${_total.toStringAsFixed(0)}',
                    style: GoogleFonts.interTight(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.error)),
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
}

class _AddExpenseDialog extends StatefulWidget {
  const _AddExpenseDialog();
  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  String _category = kOrderExpenseCategories.first;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      title: const Text('Add job expense'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'What was it for?'),
            items: [
              for (final c in kOrderExpenseCategories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // No suggested figure - what a carpenter or a tank of diesel
            // cost is the vendor's own number.
            decoration: const InputDecoration(labelText: 'Amount paid'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
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
            final a = double.tryParse(_amountCtrl.text.trim());
            if (a == null || a <= 0) {
              setState(() => _error = 'Enter the amount paid.');
              return;
            }
            Navigator.of(context).pop((
              category: _category,
              amount: a,
              note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim()
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
