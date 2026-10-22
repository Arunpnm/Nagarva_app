import '/components/ng_widgets.dart';
import '/backend/whatsapp_cloud.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/keyboard_scroll_view.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'record_payment_page_model.dart';
export 'record_payment_page_model.dart';

/// Record Payment (Week 3a rewrite).
///
/// Collections are payment_entries rows — amount + mode (cash/UPI/bank) +
/// note + date — so an order can take any number of part-payments, exactly
/// like APC's receipts. orders.paid_total and payment_status update via DB
/// trigger (20260718_payment_entries.sql); the old page overwrote
/// advance_paid and let the user hand-pick the status, both of which are
/// gone. Accepts ?orderId= to preselect (used by the Payments page's
/// per-order Record button).
class RecordPaymentPageWidget extends StatefulWidget {
  const RecordPaymentPageWidget({super.key, this.orderId});

  final String? orderId;

  static String routeName = 'RecordPaymentPage';
  static String routePath = '/record-payment';

  @override
  State<RecordPaymentPageWidget> createState() =>
      _RecordPaymentPageWidgetState();
}

class _RecordPaymentPageWidgetState extends State<RecordPaymentPageWidget> {
  late RecordPaymentPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  // paid_total alone: money received lives in payment_entries and is
  // summed onto it by trigger. The `- advance_paid` term was dropped
  // 16 Sept 2026 (CLAUDE.md, "REPLACE, NOT REVIVE") - that column was 0
  // on every live order, so no balance on this screen moves.
  double _balance(OrdersRow o) => (o.amount ?? 0) - o.paidTotal;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => RecordPaymentPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) => _load());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  Future<void> _load() async {
    // Keep whatever was selected before this (re)load — either the nav
    // param on first load, or the dropdown's current pick on a reload after
    // Save Payment — so a refresh doesn't silently drop the user's choice.
    final keepId = _model.selected?.id ?? widget.orderId;
    final rows = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q)
          .neqOrNull('payment_status', 'paid')
          .order('move_date', ascending: true),
    );
    _model.unpaidOrders =
        rows.where((o) => _balance(o) > 0).toList().cast<OrdersRow>();
    // Bug found live-testing the parity brief's Part 1 verify step: a
    // payment that fully settles the balance (payment_status -> 'paid')
    // drops that order out of unpaidOrders, but `_model.selected` — and so
    // the DropdownButtonFormField's `value` — kept the old id, which no
    // longer matched any item. That's not "stale UI", it's a hard crash:
    // "There should be exactly one item with [DropdownButton]'s value" ...
    // "Either zero or 2 or more DropdownMenuItems were detected with the
    // same value". Re-resolving by id here (instead of only reassigning
    // when widget.orderId was set) fixes both the orderId-preselected path
    // and the generic Quick-Entry path, and falls back to no selection
    // (the dropdown's placeholder) when the order paid off completely.
    _model.selected = keepId == null
        ? null
        : _model.unpaidOrders.where((o) => o.id == keepId).firstOrNull;
    if (_model.selected != null) {
      await _loadHistory();
    } else {
      _model.history = [];
    }
    _model.loading = false;
    safeSetState(() {});
  }

  Future<void> _loadHistory() async {
    final o = _model.selected;
    if (o == null) {
      _model.history = [];
      return;
    }
    final rows = await PaymentEntriesTable().queryRows(
      queryFn: (q) =>
          OrgScope.read(q).eq('order_id', o.id!).order('created_at'),
    );
    _model.history = rows.toList().cast<PaymentEntriesRow>();
  }

  Future<void> _save() async {
    final o = _model.selected;
    if (o == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select an order before saving a payment.')));
      return;
    }
    final amount =
        double.tryParse(_model.amountController!.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a payment amount.')));
      return;
    }
    final balance = _balance(o);
    if (amount > balance) {
      // Over-collection can be legit (tips, rounding) but is worth a
      // confirmation — mirrors the APC over-collection flow's spirit
      // without the full reason-chip machinery (that's a Week-4 refinement).
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('More than balance due'),
          content: Text(
              'Balance due is ₹${balance.toStringAsFixed(0)} but you entered '
              '₹${amount.toStringAsFixed(0)}. Record anyway?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Record')),
          ],
        ),
      );
      if (ok != true) return;
    }
    safeSetState(() => _model.saving = true);
    try {
      await PaymentEntriesTable().insert({
        ...OrgScope.stamp(),
        'order_id': o.id,
        'amount': amount,
        'mode': _model.mode,
        'note': _model.noteController!.text.trim().isEmpty
            ? null
            : _model.noteController!.text.trim(),
      });
      WhatsAppCloud.paymentReceived(
          orderId: o.id, customer: o.customer, phone: o.phone, amount: amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '₹${amount.toStringAsFixed(0)} recorded for ${o.customer}.')));
      _model.amountController!.clear();
      _model.noteController!.clear();
      // Refresh: order paid_total changed via trigger.
      await _load();
      await _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save: $e. '
                'Has 20260718_payment_entries.sql been run?')));
      }
    } finally {
      if (mounted) safeSetState(() => _model.saving = false);
    }
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) {
    final ng = NgPalette.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle:
          NgFonts.geist(color: ng.mute, fontSize: 12.5),
      filled: true,
      fillColor: ng.s1,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: ng.mute.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: ng.mute.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: ng.acc, width: 1.5),
      ),
    );
  }

  Widget _modeChip(String value, String label, IconData icon) {
    final ng = NgPalette.of(context);
    final selected = _model.mode == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => safeSetState(() => _model.mode = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? ng.acc : ng.s1,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected
                      ? ng.bg
                      : ng.mute),
              const SizedBox(width: 6),
              Text(
                label,
                style: NgFonts.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? ng.bg
                      : ng.text,
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
    final ng = NgPalette.of(context);
    final selected = _model.selected;
    final balance = selected == null ? 0.0 : _balance(selected);

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: ng.bg,
        appBar: NgSimpleBar(title: 'Record Payment', close: true),
        body: SafeArea(
          top: true,
          child: _model.loading
              ? const Center(child: CircularProgressIndicator())
              : KeyboardScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ---- Order picker -----------------------------------
                      DropdownButtonFormField<String>(
                        value: selected?.id,
                        isExpanded: true,
                        dropdownColor: ng.s1,
                        style: NgFonts.geist(
                            color: ng.text, fontSize: 13.5),
                        decoration: _dec('Order'),
                        hint: Text(
                          _model.unpaidOrders.isEmpty
                              ? 'No orders with balance due'
                              : 'Select order',
                          style: NgFonts.geist(
                              color: ng.mute, fontSize: 13),
                        ),
                        items: [
                          for (final o in _model.unpaidOrders)
                            DropdownMenuItem(
                              value: o.id,
                              child: Text(
                                '${o.customer} · ${o.fromCity ?? ''} to ${o.toCity ?? ''} · due ₹${_balance(o).toStringAsFixed(0)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) async {
                          _model.selected = _model.unpaidOrders
                              .where((o) => o.id == v)
                              .firstOrNull;
                          await _loadHistory();
                          safeSetState(() {});
                        },
                      ),
                      if (selected != null) ...[
                        const SizedBox(height: 12),
                        // ---- Balance summary ------------------------------
                        NgCard(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              _sumCol('Total',
                                  '₹${(selected.amount ?? 0).toStringAsFixed(0)}'),
                              _sumCol('Collected',
                                  '₹${selected.paidTotal.toStringAsFixed(0)}'),
                              _sumCol(
                                  'Balance Due',
                                  '₹${balance.toStringAsFixed(0)}',
                                  highlight: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ---- Entry form -----------------------------------
                        TextField(
                          controller: _model.amountController,
                          focusNode: _model.amountFocusNode,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: NgFonts.geist(
                              color: ng.text, fontSize: 15),
                          decoration: _dec('Amount received (₹)'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _modeChip('cash', 'Cash', Icons.payments),
                            const SizedBox(width: 8),
                            _modeChip('upi', 'UPI', Icons.qr_code),
                            const SizedBox(width: 8),
                            _modeChip(
                                'bank', 'Bank', Icons.account_balance),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _model.noteController,
                          focusNode: _model.noteFocusNode,
                          style: NgFonts.geist(
                              color: ng.text, fontSize: 13.5),
                          decoration: _dec('Note (optional)',
                              hint: 'e.g. UPI ref, received by'),
                        ),
                        const SizedBox(height: 16),
                        FFButtonWidget(
                          onPressed: _model.saving ? null : _save,
                          text: _model.saving ? 'Saving…' : 'Save Payment',
                          icon: const Icon(Icons.check_circle, size: 20.0),
                          options: FFButtonOptions(
                            width: double.infinity,
                            height: 48,
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 0.0, 0.0),
                            iconPadding:
                                const EdgeInsetsDirectional.fromSTEB(
                                    0.0, 0.0, 0.0, 0.0),
                            iconColor: ng.bg,
                            color: ng.acc,
                            textStyle:
                                TextStyle(color: ng.bg),
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                        ),
                        // ---- History --------------------------------------
                        const SizedBox(height: 20),
                        Text(
                          'Payment History (${_model.history.length})',
                          style: NgFonts.geist(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: ng.text),
                        ),
                        const SizedBox(height: 8),
                        if (_model.history.isEmpty)
                          Text('No payments recorded yet for this order.',
                              style: NgFonts.geist(
                                  fontSize: 12.5,
                                  color: ng.mute))
                        else
                          ..._model.history.map((e) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: ng.s1,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      e.mode == 'upi'
                                          ? Icons.qr_code
                                          : e.mode == 'bank'
                                              ? Icons.account_balance
                                              : Icons.payments,
                                      size: 17,
                                      color: ng.acc,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '₹${e.amount.toStringAsFixed(0)} · ${e.mode.toUpperCase()}',
                                            style: NgFonts.geist(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                                color: ng.text),
                                          ),
                                          Text(
                                            [
                                              if (e.receivedAt != null)
                                                dateTimeFormat('d MMM y',
                                                    e.receivedAt),
                                              if ((e.note ?? '')
                                                  .isNotEmpty)
                                                e.note!,
                                            ].join(' · '),
                                            style: NgFonts.geist(
                                                fontSize: 11.5,
                                                color:
                                                    ng.mute),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _sumCol(String label, String value, {bool highlight = false}) {
    final ng = NgPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: NgFonts.geist(
                fontSize: 10.5, color: ng.mute)),
        const SizedBox(height: 2),
        Text(value,
            style: NgFonts.geist(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: highlight ? ng.acc : ng.text)),
      ],
    );
  }
}
