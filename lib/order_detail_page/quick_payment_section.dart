import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/audit_log_service.dart';
import '/backend/customer_lookup.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_widgets.dart';

/// Quick Payment Update — Order Details Session 1, item 2.
///
/// A lighter, order-scoped sibling of RecordPaymentPage (which already
/// exists, pre-dates this session, and stays as-is for the cross-order
/// collection workflow off the Payments tab). This section embeds the same
/// underlying mechanism directly in Order Details so recording a payment
/// doesn't require leaving the page: insert into `payment_entries`, and
/// `orders.paid_total`/`payment_status` update themselves via the DB
/// trigger from 20260718_payment_entries.sql — this widget never writes
/// those two columns directly.
///
/// Two things RecordPaymentPage's flow does NOT do, which this adds:
///   1. Mints a receipt number via `next_doc_number(org, 'receipt', branch,
///      fy)` for the confirmation toast and the ledger narration. The
///      kickoff brief is explicit that this session ships no new SQL
///      ("the schema is complete... report rather than write a
///      migration"), and `payment_entries` has no `receipt_no` column —
///      so the number is consumed from the series (it will not be handed
///      out again) but not persisted on the row. The Documents grid's
///      Money Receipt document (item 4) is the durable, printable record
///      of a specific receipt number; this is just the in-the-moment
///      confirmation.
///   2. A `ledger_entries` row (party_type customer, credit = amount
///      collected) for AR/statement reporting. Requires a real
///      `customers.id` (`party_id` is NOT NULL) — resolved via
///      [CustomerLookup.findOrCreate], same helper new_order_page now
///      calls at creation. If the order still has no usable phone, the
///      ledger post is skipped (payment + receipt still succeed) — see
///      CustomerLookup's doc comment for why a junk phone must never mint
///      a customer row.
class QuickPaymentSection extends StatefulWidget {
  const QuickPaymentSection({super.key, required this.orderId, this.onSaved});

  final String orderId;

  /// Fired after a successful save — this section is embedded inline
  /// (not pushed as its own route), so OrderDetailPage's onPageRefresh
  /// (which only fires on route pop) can't catch this write on its own.
  /// The brief calls for "single fan-out invalidation" of the P&L card
  /// after a payment; this callback is that fan-out.
  final VoidCallback? onSaved;

  @override
  State<QuickPaymentSection> createState() => QuickPaymentSectionState();
}

class QuickPaymentSectionState extends State<QuickPaymentSection> {
  bool _loading = true;
  bool _saving = false;
  bool _notFound = false;
  OrdersRow? _order;
  String _mode = 'cash';
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  double get _balance {
    final o = _order;
    if (o == null) return 0;
    return (o.amount ?? 0) - (o.advancePaid ?? 0) - o.paidTotal;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Public so OrderDetailPage's onPageRefresh can re-pull balance after an
  /// external write (e.g. an edit to orders.amount) — same GlobalKey wiring
  /// as OrderPnlSection/QuotationBreakdownSection.
  Future<void> reload() => _load();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId),
      );
      if (!mounted) return;
      setState(() {
        _order = rows.isNotEmpty ? rows.first : null;
        _notFound = rows.isEmpty;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _notFound = true;
      });
    }
  }

  // Fixed alongside OrderDetailPage.currentFy() (RLS/numbering audit, 12
  // Aug 2026) — was emitting '2627', which never matched number_series'
  // hyphenated 'YYYY-YY' seed values, so every receipt silently drew from
  // an auto-created unprefixed series instead of the intended one.
  String _currentFy() {
    final now = DateTime.now();
    final startYear = now.month >= 4 ? now.year : now.year - 1;
    return '$startYear-${((startYear + 1) % 100).toString().padLeft(2, '0')}';
  }

  Future<String?> _defaultAccountId(String orgId) async {
    try {
      final rows = await OrgScope.read(
              SupaFlow.client.from('bank_accounts').select('id,account_type'))
          .eq('is_default', true)
          .limit(1);
      if (rows.isNotEmpty) return rows.first['id'] as String?;
      // No default set — fall back to any active cash account rather than
      // leaving the payment/ledger row with no account at all.
      final cashRows = await OrgScope.read(
              SupaFlow.client.from('bank_accounts').select('id'))
          .eq('account_type', 'cash')
          .eq('active', true)
          .limit(1);
      return cashRows.isNotEmpty ? cashRows.first['id'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final o = _order;
    if (o == null) return;
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter an amount.')));
      return;
    }
    final balance = _balance;
    if (amount > balance) {
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

    setState(() => _saving = true);
    try {
      final orgId = OrgScope.currentOrgId!;
      final accountId = await _defaultAccountId(orgId);

      String? receiptNo;
      try {
        // One org-wide series per doc type per FY, not per-branch — see
        // order_detail_page_widget.dart's _nextInvoiceNo for the reasoning
        // (12 Aug 2026 numbering-scheme decision).
        receiptNo = await SupaFlow.client.rpc('next_doc_number', params: {
          'p_org': orgId,
          'p_doc_type': 'receipt',
          'p_branch': null,
          'p_fy': _currentFy(),
        }) as String?;
      } catch (_) {
        // Falls back to no receipt number rather than blocking the payment
        // itself — most likely cause is next_doc_number/number_series not
        // having been seeded for this org's 'receipt' doc_type yet.
        receiptNo = null;
      }

      await PaymentEntriesTable().insert({
        ...OrgScope.stamp(orgId: orgId),
        'order_id': o.id,
        'amount': amount,
        'mode': _mode,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        if (accountId != null) 'account_id': accountId,
      });

      // Resolve/backfill customer_id defensively — new_order_page now sets
      // it at creation, but orders created before that fix (or with no
      // usable phone at creation time) can still reach payment unlinked.
      var customerId = o.customerId;
      if (customerId == null) {
        customerId = await CustomerLookup.findOrCreate(
          orgId: orgId,
          name: o.customer,
          phone: o.phone,
        );
        if (customerId != null) {
          await OrdersTable().update(
            data: {'customer_id': customerId},
            matchingRows: (q) => OrgScope.write(q, orgId: orgId).eq('id', o.id!),
          );
        }
      }

      if (customerId != null) {
        await SupaFlow.client.from('ledger_entries').insert({
          'org_id': orgId,
          'party_type': 'customer',
          'party_id': customerId,
          'entry_type': 'payment',
          'ref_table': 'orders',
          'ref_id': o.id,
          'narration': receiptNo != null
              ? 'Payment received — receipt $receiptNo'
              : 'Payment received',
          'debit': 0,
          'credit': amount,
          if (accountId != null) 'account_id': accountId,
        });
      }

      await AuditLogService.log(
        entityType: 'orders',
        entityId: o.id!,
        action: 'payment_recorded',
        oldValue: {'paid_total': o.paidTotal},
        newValue: {
          'amount': amount,
          'mode': _mode,
          if (receiptNo != null) 'receipt_no': receiptNo,
        },
        changedFields: const ['paid_total', 'payment_status'],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(receiptNo != null
            ? '₹${amount.toStringAsFixed(0)} recorded — receipt $receiptNo.'
            : '₹${amount.toStringAsFixed(0)} recorded.'),
      ));
      _amountCtrl.clear();
      _noteCtrl.clear();
      await _load();
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _modeChip(FlutterFlowTheme theme, String value, String label,
      IconData icon) {
    final selected = _mode == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _mode = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? theme.primary : theme.primaryBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color:
                      selected ? theme.primaryBackground : theme.secondaryText),
              const SizedBox(width: 5),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? theme.primaryBackground
                          : theme.primaryText)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    if (_loading) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
            child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_notFound || _order == null) return const SizedBox.shrink();
    if (_balance <= 0) {
      // Fully paid (or overpaid) — nothing to quick-collect. History lives
      // on RecordPaymentPage/PaymentsPage; this section is entry-only.
      return const SizedBox.shrink();
    }
    // Order Details Session 1, item 5: Mark Order Complete locks the P&L —
    // a closed order (even one Mark Complete let through with a non-zero
    // balance) must not still be quietly collectible from here.
    if ((_order!.status ?? '').toLowerCase() == 'closed') {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Quick Payment',
                  style: GoogleFonts.interTight(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryText)),
              Text('Balance ₹${_balance.toStringAsFixed(0)}',
                  style: GoogleFonts.interTight(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: theme.primary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: GoogleFonts.inter(
                      color: theme.primaryText, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Amount received (₹)',
                    labelStyle: GoogleFonts.inter(
                        color: theme.secondaryText, fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: theme.primaryBackground,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _modeChip(theme, 'cash', 'Cash', Icons.payments),
              const SizedBox(width: 6),
              _modeChip(theme, 'upi', 'UPI', Icons.qr_code),
              const SizedBox(width: 6),
              _modeChip(theme, 'bank', 'Bank', Icons.account_balance),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteCtrl,
            style: GoogleFonts.inter(color: theme.primaryText, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              labelStyle:
                  GoogleFonts.inter(color: theme.secondaryText, fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: theme.primaryBackground,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          FFButtonWidget(
            onPressed: _saving ? null : _save,
            text: _saving ? 'Saving…' : 'Record Payment',
            icon: const Icon(Icons.check_circle, size: 18),
            options: FFButtonOptions(
              width: double.infinity,
              height: 44,
              iconColor: theme.primaryBackground,
              color: theme.primary,
              textStyle: TextStyle(color: theme.primaryBackground),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ],
      ),
    );
  }
}
