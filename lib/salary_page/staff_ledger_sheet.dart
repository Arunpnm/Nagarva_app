import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

/// Per-staff ledger sheet (Week 3b), modelled on the APC "Salary & Staff"
/// reference: four summary chips (Month Earnings / Paid Out / Balance to
/// Pay / Advance Balance), Pay Salary + Give Advance + Settle Advance
/// actions, this month's order earnings, and the payout history.
///
/// Data contract:
///   earned  = Σ order_staff.salary_amount for orders moving in [month]
///   paid    = Σ salary_payments in [month]
///   balance = earned - paid
///   advance = Σ staff_advances with status 'pending' (all-time)
/// Settle Advance flips pending advances to 'settled' — same semantics the
/// staff_advances table already used.
class StaffLedgerSheet extends StatefulWidget {
  const StaffLedgerSheet({
    super.key,
    required this.staff,
    required this.month,
    required this.monthOrderStaff,
    required this.ordersById,
    required this.monthPayments,
    required this.pendingAdvances,
  });

  final StaffRow staff;
  final DateTime month;
  final List<OrderStaffRow> monthOrderStaff;
  final Map<String, OrdersRow> ordersById;
  final List<SalaryPaymentsRow> monthPayments;
  final List<StaffAdvancesRow> pendingAdvances;

  /// Returns true when anything was written (caller reloads).
  static Future<bool> show(
    BuildContext context, {
    required StaffRow staff,
    required DateTime month,
    required List<OrderStaffRow> monthOrderStaff,
    required Map<String, OrdersRow> ordersById,
    required List<SalaryPaymentsRow> monthPayments,
    required List<StaffAdvancesRow> pendingAdvances,
  }) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StaffLedgerSheet(
        staff: staff,
        month: month,
        monthOrderStaff: monthOrderStaff,
        ordersById: ordersById,
        monthPayments: monthPayments,
        pendingAdvances: pendingAdvances,
      ),
    );
    return changed == true;
  }

  @override
  State<StaffLedgerSheet> createState() => _StaffLedgerSheetState();
}

class _StaffLedgerSheetState extends State<StaffLedgerSheet> {
  bool _busy = false;
  bool _dirty = false;

  double get earned => widget.monthOrderStaff
      .fold(0.0, (s, e) => s + (e.salaryAmount ?? 0));
  double get paid =>
      widget.monthPayments.fold(0.0, (s, e) => s + e.amount);
  double get balance => earned - paid;
  double get advance =>
      widget.pendingAdvances.fold(0.0, (s, e) => s + (e.amount ?? 0));

  Future<double?> _askAmount(String title,
      {double? suggested, String? noteHint, String confirmLabel = 'Save'}) {
    final amountCtrl = TextEditingController(
        text: suggested == null || suggested <= 0
            ? ''
            : suggested.toStringAsFixed(0));
    return showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
        title: Text(title),
        content: TextField(
          controller: amountCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
              labelText: 'Amount (₹)', hintText: noteHint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(amountCtrl.text.trim());
              Navigator.of(dialogContext).pop(v);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy = true);
    try {
      await op();
      _dirty = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed: $e. '
                'Has 20260718_salary_payments.sql been run?')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paySalary() async {
    final v = await _askAmount('Pay salary to ${widget.staff.name}',
        suggested: balance > 0 ? balance : null, confirmLabel: 'Pay');
    if (v == null || v <= 0) return;
    await _run(() async {
      await SalaryPaymentsTable().insert({
        ...OrgScope.stamp(),
        'staff_id': widget.staff.id,
        'amount': v,
        'note': 'Salary ${DateFormat('MMM yyyy').format(widget.month)}',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '₹${v.toStringAsFixed(0)} paid to ${widget.staff.name}.')));
        Navigator.of(context).pop(true);
      }
    });
  }

  Future<void> _giveAdvance() async {
    final v = await _askAmount('Give advance to ${widget.staff.name}',
        confirmLabel: 'Give');
    if (v == null || v <= 0) return;
    await _run(() async {
      await StaffAdvancesTable().insert({
        ...OrgScope.stamp(),
        'staff_id': widget.staff.id,
        'amount': v,
        'status': 'pending',
        'advance_date': DateTime.now().toIso8601String().substring(0, 10),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Advance of ₹${v.toStringAsFixed(0)} recorded for ${widget.staff.name}.')));
        Navigator.of(context).pop(true);
      }
    });
  }

  Future<void> _settleAdvance() async {
    if (advance <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Settle advance?'),
        content: Text(
            'Mark ₹${advance.toStringAsFixed(0)} of pending advances for '
            '${widget.staff.name} as settled (recovered from salary)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Settle')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await StaffAdvancesTable().update(
        data: {'status': 'settled'},
        matchingRows: (q) => OrgScope.write(q)
            .eq('staff_id', widget.staff.id!)
            .eq('status', 'pending'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Advance settled for ${widget.staff.name}.')));
        Navigator.of(context).pop(true);
      }
    });
  }

  /// Attendance for the month, DERIVED FROM ORDERS.
  ///
  /// Present = this person was on at least one order that moved that day.
  /// Built 3 Sept 2026 to match the reference app's Attendance tab, which
  /// states the same rule on screen so nobody mistakes it for a punch
  /// clock.
  ///
  /// **There is no separate attendance capture here on purpose.** The
  /// crew list on an order already says who worked it; a second source of
  /// truth for "was this man on this job" is exactly how the labour
  /// figure and the crew list drift apart (the same reasoning as the crew
  /// sheet's "present == an order_staff row exists").
  ///
  /// Only days up to TODAY are judged. A future date in the current month
  /// is blank, not absent — marking someone absent for a day that has not
  /// happened is a lie the vendor would have to explain to them.
  Widget _attendanceCalendar(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final month = widget.month;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    // Day-of-month -> worked. An order with no move_date cannot be placed
    // on the calendar and is skipped rather than guessed onto today.
    final worked = <int>{};
    for (final os in widget.monthOrderStaff) {
      final order = widget.ordersById[os.orderId];
      final d = order?.moveDate;
      if (d == null) continue;
      if (d.year == month.year && d.month == month.month) worked.add(d.day);
    }

    var present = 0, absent = 0;
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      if (date.isAfter(todayDay)) continue;
      if (worked.contains(day)) {
        present++;
      } else {
        absent++;
      }
    }

    // weekday: Mon=1..Sun=7. The grid starts on Sunday, as the reference
    // does, so Sunday is column 0.
    final leadingBlanks = first.weekday % 7;

    Widget cell(Widget child, {Color? bg}) => Container(
          margin: const EdgeInsets.all(2),
          height: 38,
          decoration: BoxDecoration(
            color: bg ?? theme.primaryBackground,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: child,
        );

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
    ];
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      final future = date.isAfter(todayDay);
      final didWork = worked.contains(day);
      final mark = future ? '' : (didWork ? 'P' : 'A');
      final colour = future
          ? theme.secondaryText
          : (didWork ? theme.success : theme.error);
      cells.add(cell(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$day',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.primaryText)),
            Text(mark.isEmpty ? '·' : mark,
                style: GoogleFonts.interTight(
                    fontSize: 10, fontWeight: FontWeight.w700, color: colour)),
          ],
        ),
        bg: future
            ? null
            : (didWork
                ? theme.success.withValues(alpha: 0.14)
                : theme.error.withValues(alpha: 0.10)),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attendance — ${DateFormat('MMMM yyyy').format(month)}',
            style: GoogleFonts.interTight(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.primaryText)),
        const SizedBox(height: 2),
        Text(
          'Auto-derived from orders. Present = assigned to at least one '
          'order that day.',
          style:
              GoogleFonts.inter(fontSize: 11, color: theme.secondaryText),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Center(
                  child: Text(d,
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: theme.secondaryText)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.05,
          children: cells,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.check_circle, size: 14, color: theme.success),
            const SizedBox(width: 4),
            Text('Present: $present day${present == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.primaryText)),
            const SizedBox(width: 14),
            Icon(Icons.cancel, size: 14, color: theme.error),
            const SizedBox(width: 4),
            Text('Absent: $absent day${absent == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.primaryText)),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, double value, {Color? color}) {
    final theme = FlutterFlowTheme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: (color ?? theme.secondaryText).withOpacity(0.35)),
        ),
        child: Column(
          children: [
            Text('₹${value.toStringAsFixed(0)}',
                style: GoogleFonts.interTight(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: color ?? theme.primaryText)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 9.5, color: theme.secondaryText)),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback? onTap,
      {Color? color}) {
    final theme = FlutterFlowTheme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton.icon(
          onPressed: _busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? theme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9)),
          ),
          icon: Icon(icon, size: 15),
          label: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.staff.name,
                          style: GoogleFonts.interTight(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: theme.primaryText)),
                      Text(
                        [
                          if ((widget.staff.role ?? '').isNotEmpty)
                            widget.staff.role!,
                          DateFormat('MMMM yyyy').format(widget.month),
                        ].join(' · '),
                        style: GoogleFonts.inter(
                            fontSize: 12, color: theme.secondaryText),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: theme.secondaryText),
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(_dirty),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _chip('MONTH EARNINGS', earned,
                    color: const Color(0xFF2E7D32)),
                _chip('PAID OUT', paid, color: const Color(0xFF1565C0)),
                _chip('BALANCE TO PAY', balance,
                    color: balance > 0 ? theme.primary : null),
                _chip('ADVANCE BALANCE', advance,
                    color: advance > 0 ? theme.error : null),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _actionBtn('Pay Salary', Icons.payments, _paySalary),
                _actionBtn('Give Advance', Icons.trending_up, _giveAdvance,
                    color: const Color(0xFF1565C0)),
                _actionBtn(
                    'Settle Advance',
                    Icons.check_circle,
                    advance > 0 ? _settleAdvance : null,
                    color: const Color(0xFF2E7D32)),
              ],
            ),
            const SizedBox(height: 18),
            _attendanceCalendar(context),
            const SizedBox(height: 18),
            Text('Orders This Month (${widget.monthOrderStaff.length})',
                style: GoogleFonts.interTight(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryText)),
            const SizedBox(height: 6),
            if (widget.monthOrderStaff.isEmpty)
              Text('No job earnings this month.',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: theme.secondaryText))
            else
              ...widget.monthOrderStaff.map((e) {
                final o = widget.ordersById[e.orderId];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping,
                          size: 15, color: theme.secondaryText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          o == null
                              ? 'Order'
                              : '${o.customer} · ${dateTimeFormat('d MMM', o.moveDateOrNull)}'
                                  '${(e.isHalfDay ?? false) ? ' · half day' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 12.5, color: theme.primaryText),
                        ),
                      ),
                      Text('₹${(e.salaryAmount ?? 0).toStringAsFixed(0)}',
                          style: GoogleFonts.interTight(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2E7D32))),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 14),
            Text('Payouts This Month (${widget.monthPayments.length})',
                style: GoogleFonts.interTight(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryText)),
            const SizedBox(height: 6),
            if (widget.monthPayments.isEmpty)
              Text('Nothing paid out yet this month.',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: theme.secondaryText))
            else
              ...widget.monthPayments.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.payments,
                            size: 15, color: theme.secondaryText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            [
                              if (p.paidDate != null)
                                dateTimeFormat('d MMM', p.paidDate),
                              if ((p.note ?? '').isNotEmpty) p.note!,
                            ].join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: theme.primaryText),
                          ),
                        ),
                        Text('₹${p.amount.toStringAsFixed(0)}',
                            style: GoogleFonts.interTight(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1565C0))),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
