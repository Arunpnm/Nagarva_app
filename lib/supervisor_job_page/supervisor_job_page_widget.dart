import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'supervisor_job_page_model.dart';
export 'supervisor_job_page_model.dart';

const List<String> kJobExpenseCategories = [
  'Fuel',
  'Toll',
  'Loading/Unloading',
  'Packing Material',
  'Food',
  'Miscellaneous',
];

/// On-site field job workflow for a single order: accept the job, pick the
/// labour team, work through shifting, generate a completion OTP, and hand
/// off to the owner for approval.
///
/// Ported from apc_webapp App.jsx's SupervisorJobPage (lines ~10369-10597)
/// — see supervisor_job_page_model.dart's SupervisorJobStep doc comment for
/// how the step machine and DB writes were adapted to this app's actual
/// schema (status vocabulary, job_start_time/job_end_time instead of
/// odometer readings).
///
/// One deliberate fix vs. the reference app: OTP verification here
/// re-fetches `orders.job_otp` from the DB and checks against that, not
/// just the in-memory value — the reference app only checks in-memory
/// state, which a previous CLAUDE.md pass flagged as a security gap worth
/// not copying.
class SupervisorJobPageWidget extends StatefulWidget {
  const SupervisorJobPageWidget({super.key, this.orderId});

  final String? orderId;

  static String routeName = 'SupervisorJobPage';
  static String routePath = '/supervisor-job';

  @override
  State<SupervisorJobPageWidget> createState() =>
      _SupervisorJobPageWidgetState();
}

class _SupervisorJobPageWidgetState extends State<SupervisorJobPageWidget> {
  late SupervisorJobPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SupervisorJobPageModel());

    _model.notesController ??= TextEditingController();
    _model.expenseAmountController ??= TextEditingController();
    _model.expenseDescController ??= TextEditingController();
    _model.enteredOtpController ??= TextEditingController();

    SchedulerBinding.instance.addPostFrameCallback((_) => _loadData());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _loadData() async {
    if (widget.orderId == null) {
      _model.isLoading = false;
      _model.loadError = 'No order specified.';
      safeSetState(() {});
      return;
    }
    try {
      final results = await Future.wait([
        // LEAK_AUDIT.md leak #7 (Stage 1 fix): matched only on id before.
        OrdersTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
        ),
        StaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eqOrNull('active', true),
        ),
        ExpensesTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId!),
        ),
      ]);
      final orders = results[0].cast<OrdersRow>();
      if (orders.isEmpty) {
        _model.isLoading = false;
        _model.loadError = 'Order not found.';
        safeSetState(() {});
        return;
      }
      _model.order = orders.first;
      _model.staffList = results[1].cast<StaffRow>();
      _model.jobExpenses = results[2].cast<ExpensesRow>();

      final team = _model.order!.jobTeam;
      if (team is List) {
        _model.selectedTeamIds = team.map((e) => e.toString()).toSet();
      }
      _model.notesController!.text = _model.order!.supervisorNotes ?? '';
      _model.step = _inferStep(_model.order!);
      _model.isLoading = false;
      _model.loadError = null;
    } catch (e) {
      _model.isLoading = false;
      _model.loadError = e.toString();
    }
    safeSetState(() {});
  }

  SupervisorJobStep _inferStep(OrdersRow o) {
    if (o.status == 'delivered' ||
        o.status == 'closed' ||
        o.supervisorStatus == 'completed_pending' ||
        o.supervisorStatus == 'approved') {
      return SupervisorJobStep.done;
    }
    if (o.status == 'transit') return SupervisorJobStep.shifting;
    if (o.supervisorStatus == 'in_progress') return SupervisorJobStep.team;
    return SupervisorJobStep.start;
  }

  /// Mirrors the reference app's central `changeOrderStatus` helper: writes
  /// orders.status and logs an order_tracking row.
  Future<void> _changeStatus(String newStatus, String note) async {
    // LEAK_AUDIT.md write-gap fix: matched only on id before.
    await OrdersTable().update(
      data: {'status': newStatus},
      matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
    );
    await OrderTrackingTable().insert({
      ...OrgScope.stamp(),
      'order_id': widget.orderId,
      'status': newStatus,
      'note': note,
      'tracked_by': AppSession.instance.currentStaffName ?? 'Supervisor',
    });
  }

  Future<void> _startJob() async {
    setState(() => _model.saving = true);
    try {
      // LEAK_AUDIT.md write-gap fix: matched only on id before.
      await OrdersTable().update(
        data: {'supervisor_status': 'in_progress'},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
      );
      _model.order!.supervisorStatus = 'in_progress';
      _model.step = SupervisorJobStep.team;
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  Future<void> _startShifting() async {
    if (_model.selectedTeamIds.isEmpty) {
      _showError('Select at least one team member first.');
      return;
    }
    setState(() => _model.saving = true);
    try {
      // LEAK_AUDIT.md write-gap fix: matched only on id before.
      await OrdersTable().update(
        data: {
          'job_team': _model.selectedTeamIds.toList(),
          'job_start_time': DateTime.now().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
      );
      await _changeStatus('transit', '📦 Shifting started — team assigned');
      _model.order!.status = 'transit';
      _model.step = SupervisorJobStep.shifting;
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  Future<void> _addExpense() async {
    final amount = double.tryParse(_model.expenseAmountController!.text);
    if (amount == null || amount <= 0) {
      _showError('Enter a valid expense amount.');
      return;
    }
    setState(() => _model.saving = true);
    try {
      final row = await ExpensesTable().insert({
        ...OrgScope.stamp(),
        'order_id': widget.orderId,
        'category': _model.expenseCategory,
        'amount': amount,
        'description': _model.expenseDescController!.text.isEmpty
            ? _model.expenseCategory
            : _model.expenseDescController!.text,
        'expense_date': DateTime.now().toIso8601String().split('T').first,
      });
      _model.jobExpenses = [..._model.jobExpenses, row];
      _model.expenseAmountController!.clear();
      _model.expenseDescController!.clear();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  Future<void> _generateOtp() async {
    setState(() => _model.saving = true);
    try {
      final otp = (1000 + Random().nextInt(9000)).toString();
      // LEAK_AUDIT.md write-gap fix: matched only on id before.
      await OrdersTable().update(
        data: {
          'job_otp': otp,
          'job_end_time': DateTime.now().toIso8601String(),
          'supervisor_notes': _model.notesController!.text,
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
      );
      _model.displayedOtp = otp;
      _model.otpError = false;
      _model.step = SupervisorJobStep.otpEntry;
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  Future<void> _verifyAndComplete() async {
    setState(() => _model.saving = true);
    try {
      // Re-fetch from the DB rather than trusting only the in-memory OTP —
      // see the class doc comment for why this differs from the reference
      // app. LEAK_AUDIT.md leak #8 (Stage 1 fix): matched only on id before.
      final fresh = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
      );
      final dbOtp = fresh.isNotEmpty ? fresh.first.jobOtp : null;
      if (dbOtp == null || _model.enteredOtpController!.text.trim() != dbOtp) {
        setState(() => _model.otpError = true);
        return;
      }

      // LEAK_AUDIT.md write-gap fix: matched only on id before.
      await OrdersTable().update(
        data: {
          'supervisor_status': 'completed_pending',
          'supervisor_notes': _model.notesController!.text,
          'job_team': _model.selectedTeamIds.toList(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
      );
      if (_model.order!.status != 'delivered' &&
          _model.order!.status != 'closed') {
        await _changeStatus(
            'delivered', '🎉 Job completed by supervisor, OTP confirmed');
      }
      _model.order!.supervisorStatus = 'completed_pending';
      _model.step = SupervisorJobStep.done;
      _model.otpError = false;
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            'Field Job',
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                  fontSize: 22.0,
                  fontWeight: FontWeight.w600,
                ),
          ),
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: _model.isLoading
              ? Center(child: CircularProgressIndicator())
              : _model.loadError != null
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(_model.loadError!, textAlign: TextAlign.center),
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.all(16.0),
                      child: ListView(
                        children: [
                          _orderSummaryCard(context),
                          SizedBox(height: 16),
                          _stepBody(context),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _orderSummaryCard(BuildContext context) {
    final o = _model.order!;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(o.customer,
              style: FlutterFlowTheme.of(context)
                  .titleMedium
                  .override(font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
          SizedBox(height: 4),
          Text('${o.fromCity ?? ''} → ${o.toCity ?? ''}',
              style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: FlutterFlowTheme.of(context).secondaryText)),
          SizedBox(height: 8),
          Text('Status: ${o.status ?? '—'} · Supervisor: ${o.supervisorStatus ?? 'not started'}',
              style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: FlutterFlowTheme.of(context).secondaryText)),
        ],
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    switch (_model.step) {
      case SupervisorJobStep.start:
        return _actionCard(
          context,
          title: 'Ready to start this job?',
          body: 'Accepting will let you pick the labour team and begin shifting.',
          buttonLabel: 'Accept Job',
          onPressed: _startJob,
        );
      case SupervisorJobStep.team:
        return _teamSelectionCard(context);
      case SupervisorJobStep.shifting:
        return _shiftingCard(context);
      case SupervisorJobStep.completing:
        return _actionCard(
          context,
          title: 'Ready to complete?',
          body: 'This will generate a one-time code to confirm the job with the customer.',
          buttonLabel: 'Generate Completion Code',
          onPressed: _generateOtp,
        );
      case SupervisorJobStep.otpEntry:
        return _otpCard(context);
      case SupervisorJobStep.done:
        return _doneCard(context);
    }
  }

  Widget _actionCard(BuildContext context,
      {required String title,
      required String body,
      required String buttonLabel,
      required Future<void> Function() onPressed}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: FlutterFlowTheme.of(context).titleSmall),
          SizedBox(height: 4),
          Text(body,
              style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: FlutterFlowTheme.of(context).secondaryText)),
          SizedBox(height: 12),
          FFButtonWidget(
            onPressed: _model.saving ? null : onPressed,
            text: _model.saving ? 'Please wait…' : buttonLabel,
            options: FFButtonOptions(
              width: double.infinity,
              color: FlutterFlowTheme.of(context).primary,
              textStyle:
                  TextStyle(color: FlutterFlowTheme.of(context).primaryBackground),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamSelectionCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Labour Team', style: FlutterFlowTheme.of(context).titleSmall),
          SizedBox(height: 8),
          if (_model.staffList.isEmpty)
            Text('No active staff found.',
                style: FlutterFlowTheme.of(context).bodySmall.override(
                    font: GoogleFonts.inter(),
                    color: FlutterFlowTheme.of(context).secondaryText))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _model.staffList.map((s) {
                final selected = _model.selectedTeamIds.contains(s.id);
                return FilterChip(
                  label: Text(s.name),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _model.selectedTeamIds.add(s.id ?? '');
                      } else {
                        _model.selectedTeamIds.remove(s.id);
                      }
                    });
                  },
                  selectedColor: FlutterFlowTheme.of(context).primary,
                  labelStyle: TextStyle(
                    color: selected
                        ? FlutterFlowTheme.of(context).primaryBackground
                        : FlutterFlowTheme.of(context).primaryText,
                  ),
                );
              }).toList(),
            ),
          SizedBox(height: 12),
          FFButtonWidget(
            onPressed: _model.saving ? null : _startShifting,
            text: _model.saving ? 'Please wait…' : 'Start Shifting',
            options: FFButtonOptions(
              width: double.infinity,
              color: FlutterFlowTheme.of(context).primary,
              textStyle:
                  TextStyle(color: FlutterFlowTheme.of(context).primaryBackground),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shiftingCard(BuildContext context) {
    final totalExpenses =
        _model.jobExpenses.fold(0.0, (s, e) => s + (e.amount ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).secondaryBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Job Expenses', style: FlutterFlowTheme.of(context).titleSmall),
              SizedBox(height: 8),
              ..._model.jobExpenses.map((e) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${e.category} — ${e.description ?? ''}',
                            style: FlutterFlowTheme.of(context).bodySmall),
                        Text('₹${(e.amount ?? 0).toStringAsFixed(0)}',
                            style: FlutterFlowTheme.of(context).bodySmall),
                      ],
                    ),
                  )),
              if (_model.jobExpenses.isNotEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Total: ₹${totalExpenses.toStringAsFixed(0)}',
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(fontWeight: FontWeight.w600))),
                ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _model.expenseCategory,
                      items: kJobExpenseCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _model.expenseCategory = v ?? 'Fuel'),
                      decoration: InputDecoration(labelText: 'Category'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _model.expenseAmountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Amount (₹)'),
              ),
              TextField(
                controller: _model.expenseDescController,
                decoration: InputDecoration(labelText: 'Note (optional)'),
              ),
              SizedBox(height: 8),
              FFButtonWidget(
                onPressed: _model.saving ? null : _addExpense,
                text: 'Add Expense',
                options: FFButtonOptions(
                  width: double.infinity,
                  color: FlutterFlowTheme.of(context).secondaryBackground,
                  textStyle:
                      TextStyle(color: FlutterFlowTheme.of(context).primary),
                  borderSide:
                      BorderSide(color: FlutterFlowTheme.of(context).primary),
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).secondaryBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notes', style: FlutterFlowTheme.of(context).titleSmall),
              TextField(
                controller: _model.notesController,
                maxLines: 3,
                decoration: InputDecoration(hintText: 'Any notes for the office…'),
              ),
              SizedBox(height: 8),
              FFButtonWidget(
                onPressed: () =>
                    setState(() => _model.step = SupervisorJobStep.completing),
                text: 'Ready to Complete',
                options: FFButtonOptions(
                  width: double.infinity,
                  color: FlutterFlowTheme.of(context).primary,
                  textStyle: TextStyle(
                      color: FlutterFlowTheme.of(context).primaryBackground),
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _otpCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Confirm with Customer', style: FlutterFlowTheme.of(context).titleSmall),
          SizedBox(height: 4),
          Text(
            'Show this code to the customer and ask them to confirm the job is done, then type it back in below.',
            style: FlutterFlowTheme.of(context).bodySmall.override(
                font: GoogleFonts.inter(),
                color: FlutterFlowTheme.of(context).secondaryText),
          ),
          SizedBox(height: 12),
          Center(
            child: Text(
              _model.displayedOtp ?? '----',
              style: FlutterFlowTheme.of(context).headlineMedium.override(
                  font: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700, letterSpacing: 8.0)),
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _model.enteredOtpController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(
              labelText: 'Enter code',
              errorText: _model.otpError ? 'Code does not match' : null,
            ),
          ),
          SizedBox(height: 8),
          FFButtonWidget(
            onPressed: _model.saving ? null : _verifyAndComplete,
            text: _model.saving ? 'Verifying…' : 'Verify & Complete',
            options: FFButtonOptions(
              width: double.infinity,
              color: FlutterFlowTheme.of(context).primary,
              textStyle:
                  TextStyle(color: FlutterFlowTheme.of(context).primaryBackground),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _doneCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.celebration, color: FlutterFlowTheme.of(context).primary, size: 40),
          SizedBox(height: 8),
          Text('Job complete!', style: FlutterFlowTheme.of(context).titleMedium),
          SizedBox(height: 4),
          Text(
            _model.order?.supervisorStatus == 'approved'
                ? 'Approved by the office.'
                : 'Awaiting owner approval.',
            style: FlutterFlowTheme.of(context).bodySmall.override(
                font: GoogleFonts.inter(),
                color: FlutterFlowTheme.of(context).secondaryText),
          ),
        ],
      ),
    );
  }
}
