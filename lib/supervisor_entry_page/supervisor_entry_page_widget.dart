import '/app_session.dart';
import '/backend/customer_lookup.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Session 2 Part C — Job Entry (`sup-entry`). Minimal field-side order
/// creation: customer, phone, route, date, service. Deliberately thin —
/// no pricing/quote fields, matching the brief's "minimal form" scope.
/// Reuses `CustomerLookup.findOrCreate` (Order Details Session 1) so a
/// field-entered order links to a real customer the same way the full
/// New Order form does.
class SupervisorEntryPageWidget extends StatefulWidget {
  const SupervisorEntryPageWidget({super.key});

  static String routeName = 'SupervisorEntryPage';
  static String routePath = '/sup-entry';

  @override
  State<SupervisorEntryPageWidget> createState() =>
      _SupervisorEntryPageWidgetState();
}

class _SupervisorEntryPageWidgetState
    extends State<SupervisorEntryPageWidget> {
  final _customerCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  DateTime _moveDate = DateTime.now();
  String _service = 'Household Shifting';
  bool _saving = false;
  String? _myBranch;

  @override
  void initState() {
    super.initState();
    _loadMyBranch();
  }

  Future<void> _loadMyBranch() async {
    final staffId = AppSession.instance.currentStaffId;
    if (staffId == null) return;
    final rows = await StaffTable().queryRows(
      queryFn: (q) => q.eq('id', staffId),
    );
    if (mounted) setState(() => _myBranch = rows.firstOrNull?.branch);
  }

  static const _services = [
    'Household Shifting',
    'Office Relocation',
    'Vehicle Transport',
    'Storage',
    'Other',
  ];

  @override
  void dispose() {
    _customerCtrl.dispose();
    _phoneCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<String> _nextOrderId() async {
    final prefix = AppSession.instance.currentOrgSlug?.toUpperCase() ?? 'NGV';
    const key = 'order_id_seq';
    final rows = await SettingsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('key', key),
    );
    final current = rows.isNotEmpty
        ? (int.tryParse(rows.first.value ?? '1000') ?? 1000)
        : 1000;
    final next = current + 1;
    await SettingsTable().upsert(
      {
        'key': key,
        ...OrgScope.stamp(),
        'value': next.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'org_id,key',
    );
    return '$prefix-$next';
  }

  Future<void> _save() async {
    if (_customerCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a customer name.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final orgId = OrgScope.currentOrgId!;
      final customerId = await CustomerLookup.findOrCreate(
        orgId: orgId,
        name: _customerCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      final newOrderId = await _nextOrderId();
      final created = await OrdersTable().insert({
        'id': newOrderId,
        ...OrgScope.stamp(orgId: orgId),
        'customer': _customerCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        if (customerId != null) 'customer_id': customerId,
        'from_city': _fromCtrl.text.trim(),
        'to_city': _toCtrl.text.trim(),
        'move_date': _moveDate.toIso8601String().split('T').first,
        'service': _service,
        'branch': _myBranch,
        'amount': 0.0,
        'status': 'pending',
        'payment_status': 'pending',
        'tracking_status': 'Pending',
        'advance_paid': 0.0,
        'supervisor_id': AppSession.instance.currentStaffId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order ${created.id} created.')));
      _customerCtrl.clear();
      _phoneCtrl.clear();
      _fromCtrl.clear();
      _toCtrl.clear();
      setState(() => _moveDate = DateTime.now());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create order: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        centerTitle: true,
        title: Text('Job Entry',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _customerCtrl,
              decoration: const InputDecoration(labelText: 'Customer name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _fromCtrl,
              decoration: const InputDecoration(labelText: 'From city'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _toCtrl,
              decoration: const InputDecoration(labelText: 'To city'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _service,
              items: _services
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _service = v ?? 'Household Shifting'),
              decoration: const InputDecoration(labelText: 'Service'),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _moveDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _moveDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Move date'),
                child: Text(DateFormat('d MMM y').format(_moveDate)),
              ),
            ),
            const SizedBox(height: 16),
            FFButtonWidget(
              onPressed: _saving ? null : _save,
              text: _saving ? 'Saving…' : 'Create Order',
              options: FFButtonOptions(
                width: double.infinity,
                height: 46,
                color: theme.primary,
                textStyle: TextStyle(color: theme.primaryBackground),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
