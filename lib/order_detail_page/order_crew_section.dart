import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/audit_log_service.dart';
import '/backend/tracking_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/permissions.dart';

/// Order crew management, embedded in Order Details (owner view).
///
/// Two responsibilities Arun flagged as missing from the order flow:
///   1. Assign / reassign a supervisor — writes orders.supervisor_id (and
///      bumps status to 'team_assigned' when the order was still early),
///      which also fires the DB trigger that notifies that supervisor
///      (20260717_notifications_and_settings.sql).
///   2. Labour + per-order salary — add staff to the order with a salary
///      amount into order_staff (salary_amount, is_half_day), remove them,
///      and see the labour total. This is the owner-side view; the
///      supervisor picks their team in the field via SupervisorJobPage,
///      landing in the same table.
class OrderCrewSection extends StatefulWidget {
  const OrderCrewSection({super.key, required this.orderId, this.onCrewChanged});

  final String orderId;

  /// Fired after labour is added or removed (crew salary changes) — this
  /// section is embedded inline, not pushed as its own route, so
  /// OrderDetailPage's onPageRefresh (route-pop only) can't catch it.
  /// Order Details Session 1's P&L card needs this fan-out to stay
  /// accurate; not fired for a supervisor reassignment, which doesn't
  /// affect P&L.
  final VoidCallback? onCrewChanged;

  @override
  State<OrderCrewSection> createState() => _OrderCrewSectionState();
}

class _OrderCrewSectionState extends State<OrderCrewSection> {
  List<StaffRow> _staff = [];
  List<OrderStaffRow> _crew = [];
  OrdersRow? _order;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        StaffTable().queryRows(
          queryFn: (q) =>
              OrgScope.read(q).eq('active', true).order('name'),
        ),
        OrderStaffTable().queryRows(
          queryFn: (q) =>
              OrgScope.read(q).eq('order_id', widget.orderId),
        ),
        OrdersTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId),
        ),
      ]);
      _staff = (results[0] as List).cast<StaffRow>();
      _crew = (results[1] as List).cast<OrderStaffRow>();
      final orders = (results[2] as List).cast<OrdersRow>();
      _order = orders.isNotEmpty ? orders.first : null;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<StaffRow> get _supervisors => _staff
      .where((s) => (s.role ?? '').toLowerCase() == 'supervisor')
      .toList();

  StaffRow? _staffById(String? id) {
    for (final s in _staff) {
      if (s.id == id) return s;
    }
    return null;
  }

  double get _labourTotal =>
      _crew.fold(0.0, (sum, c) => sum + (c.salaryAmount ?? 0));

  /// Order Details Session 1, item 5: once Mark Order Complete closes the
  /// order, its P&L inputs stop accepting changes — this is the "lock"
  /// half of "lock the P&L" (see _markComplete's doc comment for why
  /// there's no DB-level lock flag).
  bool get _locked => (_order?.status ?? '').toLowerCase() == 'closed';

  Future<void> _assignSupervisor(String staffId) async {
    setState(() => _busy = true);
    try {
      final st = (_order?.status ?? '').toLowerCase();
      final bumpStatus = st == 'pending' || st == 'confirmed' || st.isEmpty;
      await OrdersTable().update(
        data: {
          'supervisor_id': staffId,
          // Match the reference app's vocabulary: assigning a team moves an
          // early-stage order to Team Assigned; later stages keep status.
          if (bumpStatus) 'status': 'team_assigned',
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId),
      );
      // Item 6: every status change feeds the customer-facing timeline.
      if (bumpStatus) {
        await TrackingService.logStatus(
          orderId: widget.orderId,
          status: 'team_assigned',
          note: 'Crew assigned',
        );
      }
      await _load();
      if (mounted) {
        final name = _staffById(staffId)?.name ?? 'Supervisor';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$name assigned — they have been notified.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not assign: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addLabour() async {
    final available = _staff
        .where((s) =>
            (s.role ?? '').toLowerCase() != 'supervisor' &&
            !_crew.any((c) => c.staffId == s.id))
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No more active staff to add. Add staff on the Staff page first.')));
      return;
    }
    String selectedId = available.first.id!;
    final salaryCtrl = TextEditingController(
        text: available.first.salary == null
            ? ''
            : (available.first.salary! / 26).round().toString());
    bool halfDay = false;

    final theme = FlutterFlowTheme.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: theme.secondaryBackground,
          title: const Text('Add Labour'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: selectedId,
                dropdownColor: theme.secondaryBackground,
                decoration: const InputDecoration(labelText: 'Staff'),
                items: [
                  for (final s in available)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text('${s.name} (${s.role ?? '—'})'),
                    ),
                ],
                onChanged: (v) => setDialogState(() {
                  selectedId = v!;
                  final s =
                      available.firstWhere((x) => x.id == selectedId);
                  // Suggest a day rate from the monthly salary (26 working
                  // days) — editable, just a starting point.
                  salaryCtrl.text = s.salary == null
                      ? ''
                      : (s.salary! / 26).round().toString();
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: salaryCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Salary for this job (₹)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Half day'),
                value: halfDay,
                onChanged: (v) =>
                    setDialogState(() => halfDay = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    setState(() => _busy = true);
    try {
      await OrderStaffTable().insert({
        ...OrgScope.stamp(),
        'order_id': widget.orderId,
        'staff_id': selectedId,
        'salary_amount': double.tryParse(salaryCtrl.text.trim()) ?? 0,
        'is_half_day': halfDay,
        'team_type': 'labour',
      });
      await _load();
      widget.onCrewChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeLabour(OrderStaffRow c) async {
    setState(() => _busy = true);
    try {
      await OrderStaffTable().delete(
        matchingRows: (q) => OrgScope.write(q).eq('id', c.id!),
      );
      await _load();
      widget.onCrewChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not remove: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    // Supervisors manage their team from the field job page, not here.
    if (AppSession.instance.currentStaffId != null) {
      return const SizedBox.shrink();
    }
    if (_loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
            child: SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator())),
      );
    }
    final supervisor = _staffById(_order?.supervisorId);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Team & Salary',
              style: GoogleFonts.interTight(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryText)),
          const SizedBox(height: 12),
          // --- Supervisor -----------------------------------------------
          Row(
            children: [
              Icon(Icons.engineering, color: theme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: _supervisors.isEmpty
                    ? Text(
                        'No supervisors yet — add one on the Staff page with role "Supervisor".',
                        style: GoogleFonts.inter(
                            fontSize: 12.5, color: theme.secondaryText),
                      )
                    : DropdownButtonFormField<String>(
                        value: supervisor?.id,
                        dropdownColor: theme.secondaryBackground,
                        decoration: InputDecoration(
                          labelText: 'Supervisor',
                          labelStyle: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: theme.secondaryText),
                          isDense: true,
                        ),
                        hint: const Text('Assign supervisor'),
                        items: [
                          for (final s in _supervisors)
                            DropdownMenuItem(
                                value: s.id, child: Text(s.name)),
                        ],
                        onChanged: _busy || _locked
                            ? null
                            : (v) {
                                if (v != null) _assignSupervisor(v);
                              },
                      ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // --- Labour ---------------------------------------------------
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Labour (${_crew.length})',
                  style: GoogleFonts.interTight(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryText)),
              TextButton.icon(
                onPressed: _busy || _locked ? null : _addLabour,
                icon: const Icon(Icons.person_add, size: 17),
                label: const Text('Add Labour'),
              ),
            ],
          ),
          if (_crew.isEmpty)
            Text('No labour assigned yet.',
                style: GoogleFonts.inter(
                    fontSize: 12.5, color: theme.secondaryText))
          else ...[
            ..._crew.map((c) {
              final s = _staffById(c.staffId);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(Icons.person,
                        size: 16, color: theme.secondaryText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${s?.name ?? 'Staff'}'
                        '${(s?.role ?? '').isEmpty ? '' : ' · ${s!.role}'}'
                        '${(c.isHalfDay ?? false) ? ' · half day' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 12.5, color: theme.primaryText),
                      ),
                    ),
                    Text('₹${(c.salaryAmount ?? 0).toStringAsFixed(0)}',
                        style: GoogleFonts.interTight(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: theme.primary)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close,
                          size: 15, color: theme.error),
                      onPressed: _busy || _locked ? null : () => _removeLabour(c),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Labour total',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: theme.secondaryText)),
                Text('₹${_labourTotal.toStringAsFixed(0)}',
                    style: GoogleFonts.interTight(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryText)),
              ],
            ),
          ],
          // Order Details Session 1, item 5: Mark Order Complete — closes
          // the order FINANCIALLY, distinct from the operations stepper's
          // job-progress status. Placed below the labour list per the
          // brief, but not conditioned on labour existing (a fully
          // porter-handled order can have zero labour rows and still be
          // ready to close).
          if (StaffPermissions.canActive('orders', 'edit'))
            _markCompleteSection(theme),
        ],
      ),
    );
  }

  bool _markingComplete = false;

  Widget _markCompleteSection(FlutterFlowTheme theme) {
    final status = (_order?.status ?? '').toLowerCase();
    if (status == 'closed') {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          children: [
            Icon(Icons.lock, size: 16, color: theme.secondaryText),
            const SizedBox(width: 6),
            Text('Order closed — P&L locked',
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: theme.secondaryText)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton.icon(
          onPressed: _markingComplete ? null : _markComplete,
          style: FilledButton.styleFrom(backgroundColor: theme.success),
          icon: const Icon(Icons.task_alt, size: 19),
          label: Text(_markingComplete ? 'Closing…' : 'Mark Order Complete'),
        ),
      ),
    );
  }

  /// Closes the order financially. Distinct from job/tracking status —
  /// this never touches `status` for the transit/delivered vocabulary the
  /// rest of the app uses; it's a new terminal value, 'closed'.
  ///
  /// Schema gap flagged rather than worked around: the brief calls for
  /// "stamp closed_at" and "lock the P&L", but no `orders.closed_at`
  /// column exists in any of the 6 migrations, and the brief's own
  /// constraints say no new SQL this session. `status = 'closed'` is
  /// real and is written; the timestamp is not. "Lock the P&L" is
  /// implemented as a UI lock (this section's own Add/Remove Labour and
  /// QuickPaymentSection both check `status == 'closed'` and stop
  /// accepting writes) rather than a DB flag, for the same reason.
  Future<void> _markComplete() async {
    final o = _order;
    if (o == null || widget.orderId.isEmpty) return;

    double revenueFinal = o.quoteTotal ?? 0;
    try {
      final addonsRows = await OrgScope.read(
              SupaFlow.client.from('addons').select('amount,status'))
          .eq('order_id', widget.orderId)
          .neq('status', 'cancelled');
      revenueFinal += addonsRows.fold<double>(
          0, (s, r) => s + (num.tryParse('${r['amount']}') ?? 0));
    } catch (_) {}
    final balance = revenueFinal - o.paidTotal;
    final hasInvoice = (o.invoiceNo ?? '').isNotEmpty;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
        title: const Text('Mark Order Complete?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (balance != 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  balance > 0
                      ? '⚠ Outstanding balance of ₹${balance.toStringAsFixed(0)} — closing this order will not collect it.'
                      : '⚠ This order is over-collected by ₹${(-balance).toStringAsFixed(0)}.',
                  style: TextStyle(
                      color: FlutterFlowTheme.of(context).error,
                      fontWeight: FontWeight.w700),
                ),
              ),
            if (!hasInvoice)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '⚠ No invoice has been issued for this order yet.',
                  style: TextStyle(
                      color: FlutterFlowTheme.of(context).warning,
                      fontWeight: FontWeight.w600),
                ),
              ),
            const Text(
              'This closes the order financially and locks its P&L. This '
              'cannot be undone from here.',
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                  backgroundColor: FlutterFlowTheme.of(context).error),
              child: const Text('Close Order')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _markingComplete = true);
    try {
      await OrdersTable().update(
        data: {'status': 'closed'},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId),
      );
      await AuditLogService.log(
        entityType: 'orders',
        entityId: widget.orderId,
        action: 'marked_complete',
        oldValue: {'status': o.status},
        newValue: {'status': 'closed', 'balance_at_close': balance},
        changedFields: const ['status'],
        reason: balance != 0
            ? 'Closed with non-zero balance (₹${balance.toStringAsFixed(0)})'
            : null,
      );
      await TrackingService.logStatus(
        orderId: widget.orderId,
        status: 'closed',
        note: 'Order marked complete',
      );
      await _load();
      widget.onCrewChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order closed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not close order: $e')));
      }
    } finally {
      if (mounted) setState(() => _markingComplete = false);
    }
  }
}
