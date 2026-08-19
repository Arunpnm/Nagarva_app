import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/backend/audit_log_service.dart';
import '/backend/customer_lookup.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/upi_payment.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';

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
  bool _requesting = false;
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

  // ---- Item 19 Phase 1: request payment by UPI --------------------------

  /// Builds a `upi://pay` link for this order's outstanding balance and
  /// hands it to the vendor to send on.
  ///
  /// This records NOTHING. A customer paying through the link is invisible
  /// to the app until somebody enters it above — same as cash. Phase 1 is
  /// a faster way to ask for money, not a collection pipeline, and the
  /// sheet says so rather than implying the payment will appear by itself.
  Future<void> _requestByUpi() async {
    final o = _order;
    if (o == null) return;
    setState(() => _requesting = true);
    UpiPayee? payee;
    String? error;
    try {
      payee = await resolveOrgUpiPayee();
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() => _requesting = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read your UPI ID: $error')));
      return;
    }
    if (payee == null || !isPlausibleVpa(payee.vpa)) {
      await _promptForUpiId(missing: payee == null);
      return;
    }
    await _showUpiRequestSheet(payee);
  }

  /// Shown when the org has no usable UPI ID. Arun's call (Item 19): the
  /// empty state is "Set your UPI ID" and it must go somewhere — a dead
  /// message telling a vendor to find a setting themselves is the same
  /// dead end as a button that does nothing.
  Future<void> _promptForUpiId({required bool missing}) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set your UPI ID'),
        content: Text(missing
            ? 'You have not added a UPI ID yet, so there is nothing for a '
                'customer to pay to. Add it in Settings → Business Profile '
                'and it will also appear on your invoices and quotations.'
            : 'Your saved UPI ID does not look like a valid address '
                '(it should look like name@bank). Fix it in Settings → '
                'Business Profile.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings')),
        ],
      ),
    );
    if (go == true && mounted) {
      context.pushNamed(SettingsPageWidget.routeName);
    }
  }

  Future<void> _showUpiRequestSheet(UpiPayee payee) async {
    final o = _order!;
    // Defaults to the outstanding balance and stays editable — a customer
    // paying a part amount is normal, and forcing the full balance would
    // just push the vendor back to typing the number by hand.
    final amountCtrl =
        TextEditingController(text: _balance.toStringAsFixed(0));

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = FlutterFlowTheme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
              final uri = buildUpiUri(
                vpa: payee.vpa,
                payeeName: payee.name,
                amount: amount,
                note: 'Order ${o.id}',
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Request payment by UPI',
                      style: GoogleFonts.interTight(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.primaryText)),
                  const SizedBox(height: 4),
                  Text('Paid to ${payee.vpa}',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: theme.secondaryText)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setSheet(() {}),
                    style: GoogleFonts.inter(
                        color: theme.primaryText, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Amount to request (₹)',
                      helperText: 'Balance due ₹${_balance.toStringAsFixed(0)}',
                      labelStyle: GoogleFonts.inter(
                          color: theme.secondaryText, fontSize: 12),
                      isDense: true,
                      filled: true,
                      fillColor: theme.primaryBackground,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FFButtonWidget(
                    onPressed: amount <= 0
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await _sendUpiOnWhatsApp(payee, amount, uri);
                          },
                    text: 'Send on WhatsApp',
                    icon: const Icon(Icons.send, size: 18),
                    options: FFButtonOptions(
                      width: double.infinity,
                      height: 44,
                      iconColor: theme.primaryBackground,
                      color: theme.primary,
                      textStyle: TextStyle(color: theme.primaryBackground),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: amount <= 0
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: uri));
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('UPI link copied.')));
                          },
                    icon: const Icon(Icons.content_copy, size: 18),
                    label: const Text('Copy UPI link'),
                  ),
                  const SizedBox(height: 10),
                  // Says plainly what this does not do. A vendor who
                  // believes a sent link auto-reconciles will stop
                  // recording payments, and their books go wrong quietly.
                  Text(
                    'Opens in the customer\'s UPI app. Payments are not '
                    'detected automatically — record it above once you '
                    'receive it.',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: theme.secondaryText),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    amountCtrl.dispose();
  }

  Future<void> _sendUpiOnWhatsApp(
      UpiPayee payee, double amount, String uri) async {
    final o = _order!;
    final message = buildUpiRequestMessage(
      orgName: payee.name,
      customerName: o.customer.trim().isEmpty ? 'there' : o.customer,
      orderId: o.id ?? '',
      amount: amount,
      vpa: payee.vpa,
      upiUri: uri,
    );
    try {
      final ok = await launchUrl(
        Uri.parse(buildWhatsAppLink(phone: o.phone, message: message)),
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
    } catch (_) {
      // Fall through to the clipboard path below.
    }
    await Clipboard.setData(ClipboardData(text: message));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not open WhatsApp — message copied instead.')));
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
          // Item 19 Phase 1. Sits UNDER Record Payment deliberately:
          // recording money already received is the more common action
          // and stays the primary one. Asking for money is the secondary
          // affordance, not the headline.
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _requesting ? null : _requestByUpi,
            icon: Icon(Icons.qr_code_2, size: 18, color: theme.primary),
            label: Text(
              _requesting ? 'Preparing…' : 'Request payment by UPI',
              style: GoogleFonts.interTight(
                  fontSize: 13, fontWeight: FontWeight.w600, color: theme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
