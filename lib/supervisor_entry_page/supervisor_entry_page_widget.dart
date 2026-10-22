import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/app_session.dart';
import '/backend/customer_lookup.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/backend/order_id_allocator.dart';

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
      final newOrderId = await OrderIdAllocator.next();
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _moveDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _moveDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    const gap = SizedBox(height: 22);
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: const NgSimpleBar(title: 'New job', close: true),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const NgFieldLabel('Customer name'),
            NgInput(controller: _customerCtrl, hint: 'Customer name'),
            gap,
            const NgFieldLabel('Phone'),
            NgInput(
              controller: _phoneCtrl,
              hint: '+91 98xxx xxxxx',
              keyboardType: TextInputType.phone,
              mono: true,
            ),
            gap,
            const NgFieldLabel('Route'),
            NgRouteFields(
                from: _fromCtrl,
                to: _toCtrl,
                fromHint: 'From city',
                toHint: 'To city'),
            gap,
            const NgFieldLabel('Service'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in _services)
                NgChip(
                  label: s,
                  selected: _service == s,
                  onTap: () => setState(() => _service = s),
                ),
            ]),
            gap,
            const NgFieldLabel('Move date'),
            NgPickerField(
              icon: Icons.event_outlined,
              value: DateFormat('EEE, d MMM y').format(_moveDate),
              onTap: _pickDate,
            ),
          ],
        ),
        bottomNavigationBar: NgBottomActionBar(
          child: NgPrimaryButton(
            label: _saving ? 'Saving…' : 'Create order',
            icon: Icons.check_rounded,
            height: 54,
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
    );
  }
}
