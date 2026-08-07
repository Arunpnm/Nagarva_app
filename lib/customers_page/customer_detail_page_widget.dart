import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

class CustomerDetailPageWidget extends StatefulWidget {
  const CustomerDetailPageWidget({super.key, this.customerId});
  final String? customerId;

  static String routeName = 'CustomerDetailPage';
  static String routePath = '/customer-detail';

  @override
  State<CustomerDetailPageWidget> createState() =>
      _CustomerDetailPageWidgetState();
}

class _CustomerDetailPageWidgetState extends State<CustomerDetailPageWidget> {
  bool _loading = true;
  bool _deleting = false;
  CustomersRow? _customer;
  Customer360ViewRow? _kpi;
  List<CustomerAddressesRow> _addresses = [];
  List<CustomerContactsRow> _contacts = [];
  List<OrdersRow> _orders = [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.customerId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final customers = await CustomersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.customerId!),
      );
      _customer = customers.isNotEmpty ? customers.first : null;
      final kpis = await Customer360ViewTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('customer_id', widget.customerId!),
      );
      _kpi = kpis.isNotEmpty ? kpis.first : null;
      _addresses = await CustomerAddressesTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eq('customer_id', widget.customerId!)
            .order('is_primary', ascending: false),
      );
      _contacts = await CustomerContactsTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eq('customer_id', widget.customerId!)
            .order('is_primary', ascending: false),
      );
      _orders = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eq('customer_id', widget.customerId!)
            .order('created_at', ascending: false),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load customer: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _rupees(num v) => '₹${v.toStringAsFixed(0)}';

  Future<void> _editCustomer() async {
    final c = _customer;
    if (c == null) return;
    final nameCtrl = TextEditingController(text: c.name);
    final companyCtrl = TextEditingController(text: c.companyName ?? '');
    final phoneCtrl = TextEditingController(text: c.phone ?? '');
    final altPhoneCtrl = TextEditingController(text: c.altPhone ?? '');
    final emailCtrl = TextEditingController(text: c.email ?? '');
    final gstinCtrl = TextEditingController(text: c.gstin ?? '');
    final billingCtrl = TextEditingController(text: c.billingAddress ?? '');
    final cityCtrl = TextEditingController(text: c.city ?? '');
    final stateCtrl = TextEditingController(text: c.state ?? '');
    final pincodeCtrl = TextEditingController(text: c.pincode ?? '');
    final creditLimitCtrl =
        TextEditingController(text: c.creditLimit == null ? '' : '${c.creditLimit}');
    final creditDaysCtrl =
        TextEditingController(text: c.creditDays == null ? '' : '${c.creditDays}');
    final notesCtrl = TextEditingController(text: c.notes ?? '');
    String type = c.customerType;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Edit Customer'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Customer Type'),
                    items: const [
                      DropdownMenuItem(value: 'individual', child: Text('Individual')),
                      DropdownMenuItem(value: 'corporate', child: Text('Corporate')),
                    ],
                    onChanged: (v) => setDialogState(() => type = v ?? 'individual'),
                  ),
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name')),
                  if (type == 'corporate')
                    TextField(
                        controller: companyCtrl,
                        decoration: const InputDecoration(labelText: 'Company Name')),
                  TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      keyboardType: TextInputType.phone),
                  TextField(
                      controller: altPhoneCtrl,
                      decoration: const InputDecoration(labelText: 'Alt Phone'),
                      keyboardType: TextInputType.phone),
                  TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email')),
                  TextField(
                      controller: gstinCtrl,
                      decoration: const InputDecoration(labelText: 'GSTIN')),
                  TextField(
                      controller: billingCtrl,
                      decoration: const InputDecoration(labelText: 'Billing Address')),
                  TextField(
                      controller: cityCtrl,
                      decoration: const InputDecoration(labelText: 'City')),
                  TextField(
                      controller: stateCtrl,
                      decoration: const InputDecoration(labelText: 'State')),
                  TextField(
                      controller: pincodeCtrl,
                      decoration: const InputDecoration(labelText: 'Pincode')),
                  TextField(
                      controller: creditLimitCtrl,
                      decoration: const InputDecoration(labelText: 'Credit Limit'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  TextField(
                      controller: creditDaysCtrl,
                      decoration: const InputDecoration(labelText: 'Credit Days'),
                      keyboardType: TextInputType.number),
                  TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      maxLines: 2),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: nameCtrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await CustomersTable().update(
        data: {
          'customer_type': type,
          'name': nameCtrl.text.trim(),
          'company_name': companyCtrl.text.trim().isEmpty ? null : companyCtrl.text.trim(),
          'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
          'alt_phone': altPhoneCtrl.text.trim().isEmpty ? null : altPhoneCtrl.text.trim(),
          'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
          'gstin': gstinCtrl.text.trim().isEmpty ? null : gstinCtrl.text.trim(),
          'billing_address':
              billingCtrl.text.trim().isEmpty ? null : billingCtrl.text.trim(),
          'city': cityCtrl.text.trim().isEmpty ? null : cityCtrl.text.trim(),
          'state': stateCtrl.text.trim().isEmpty ? null : stateCtrl.text.trim(),
          'pincode': pincodeCtrl.text.trim().isEmpty ? null : pincodeCtrl.text.trim(),
          'credit_limit': double.tryParse(creditLimitCtrl.text.trim()),
          'credit_days': int.tryParse(creditDaysCtrl.text.trim()),
          'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.customerId!),
      );
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _toggleBlacklist() async {
    final c = _customer;
    if (c == null) return;
    if (c.isBlacklisted) {
      await CustomersTable().update(
        data: {'is_blacklisted': false, 'blacklist_reason': null},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.customerId!),
      );
      _changed = true;
      await _load();
      return;
    }
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Blacklist Customer'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Blacklist')),
        ],
      ),
    );
    if (ok != true) return;
    await CustomersTable().update(
      data: {
        'is_blacklisted': true,
        'blacklist_reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      },
      matchingRows: (q) => OrgScope.write(q).eq('id', widget.customerId!),
    );
    _changed = true;
    await _load();
  }

  Future<void> _addAddress() async {
    final labelCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final floorCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();
    bool hasLift = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Add Address'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: 'Label (e.g. Home, Office)'),
                  autofocus: true),
              TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address'),
                  maxLines: 2),
              TextField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(labelText: 'City')),
              TextField(
                  controller: floorCtrl,
                  decoration: const InputDecoration(labelText: 'Floor'),
                  keyboardType: TextInputType.number),
              TextField(
                  controller: pincodeCtrl,
                  decoration: const InputDecoration(labelText: 'Pincode')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Has Lift'),
                value: hasLift,
                onChanged: (v) => setDialogState(() => hasLift = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: addressCtrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await CustomerAddressesTable().insert({
        ...OrgScope.stamp(),
        'customer_id': widget.customerId,
        if (labelCtrl.text.trim().isNotEmpty) 'label': labelCtrl.text.trim(),
        'address': addressCtrl.text.trim(),
        if (cityCtrl.text.trim().isNotEmpty) 'city': cityCtrl.text.trim(),
        'floor': int.tryParse(floorCtrl.text.trim()),
        'has_lift': hasLift,
        if (pincodeCtrl.text.trim().isNotEmpty) 'pincode': pincodeCtrl.text.trim(),
        'is_primary': _addresses.isEmpty,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add address: $e')));
      }
    }
  }

  Future<void> _deleteAddress(CustomerAddressesRow a) async {
    if (a.id == null) return;
    try {
      await SupaFlow.client.from('customer_addresses').delete().eq('id', a.id!);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  Future<void> _addContact() async {
    final nameCtrl = TextEditingController();
    final designationCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Add Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true),
            TextField(
                controller: designationCtrl,
                decoration: const InputDecoration(labelText: 'Designation')),
            TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone),
            TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: nameCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CustomerContactsTable().insert({
        ...OrgScope.stamp(),
        'customer_id': widget.customerId,
        'name': nameCtrl.text.trim(),
        if (designationCtrl.text.trim().isNotEmpty) 'designation': designationCtrl.text.trim(),
        if (phoneCtrl.text.trim().isNotEmpty) 'phone': phoneCtrl.text.trim(),
        if (emailCtrl.text.trim().isNotEmpty) 'email': emailCtrl.text.trim(),
        'is_primary': _contacts.isEmpty,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add contact: $e')));
      }
    }
  }

  Future<void> _deleteContact(CustomerContactsRow c) async {
    if (c.id == null) return;
    try {
      await SupaFlow.client.from('customer_contacts').delete().eq('id', c.id!);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  void _openOrder(OrdersRow o) {
    context.pushNamed(
      OrderDetailPageWidget.routeName,
      queryParameters: {
        'orderId': serializeParam(o.id, ParamType.String),
        'orderCustomer': serializeParam(o.customer, ParamType.String),
        'orderPhone': serializeParam(o.phone, ParamType.String),
        'orderFromCity': serializeParam(o.fromCity, ParamType.String),
        'orderToCity': serializeParam(o.toCity, ParamType.String),
        'orderFromAddress': serializeParam(o.fromAddress, ParamType.String),
        'orderToAddress': serializeParam(o.toAddress, ParamType.String),
        'orderFromFloor': serializeParam(o.fromFloor?.toString(), ParamType.String),
        'orderToFloor': serializeParam(o.toFloor?.toString(), ParamType.String),
        'orderMoveDate': serializeParam(o.moveDateOrNull?.toString(), ParamType.String),
        'orderAmount': serializeParam(o.amount?.toString(), ParamType.String),
        'orderAdvancePaid': serializeParam(o.advancePaid?.toString(), ParamType.String),
        'orderStatus': serializeParam(o.status, ParamType.String),
        'orderPaymentStatus': serializeParam(o.paymentStatus, ParamType.String),
        'orderTrackingStatus': serializeParam(o.trackingStatus, ParamType.String),
        'orderService': serializeParam(o.service, ParamType.String),
        'orderBranch': serializeParam(o.branch, ParamType.String),
        'orderType': serializeParam(o.orderType, ParamType.String),
        'orderNotes': serializeParam(o.notes, ParamType.String),
      }.withoutNulls,
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey))),
            Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 12.5))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final c = _customer;
    final kpi = _kpi;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          title: Text(c?.name ?? 'Customer',
              style: theme.titleLarge.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          centerTitle: true,
          elevation: 0,
          actions: [
            if (c != null)
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _editCustomer),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : c == null
                ? const Center(child: Text('Customer not found.'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (c.isBlacklisted)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.block, size: 16, color: theme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Blacklisted${(c.blacklistReason ?? '').isNotEmpty ? ': ${c.blacklistReason}' : ''}',
                                  style: GoogleFonts.inter(fontSize: 12, color: theme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (kpi != null)
                        Row(
                          children: [
                            Expanded(child: _kpiCard(theme, 'Orders', '${kpi.totalOrders}')),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _kpiCard(theme, 'Lifetime Value', _rupees(kpi.lifetimeValue))),
                          ],
                        ),
                      if (kpi != null) const SizedBox(height: 8),
                      if (kpi != null)
                        Row(
                          children: [
                            Expanded(
                                child: _kpiCard(theme, 'Avg Order', _rupees(kpi.avgOrderValue))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _kpiCard(theme, 'Outstanding', _rupees(kpi.outstandingEstimate))),
                          ],
                        ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv('Type', c.customerType),
                            if ((c.companyName ?? '').isNotEmpty) _kv('Company', c.companyName!),
                            if ((c.phone ?? '').isNotEmpty) _kv('Phone', c.phone!),
                            if ((c.altPhone ?? '').isNotEmpty) _kv('Alt Phone', c.altPhone!),
                            if ((c.email ?? '').isNotEmpty) _kv('Email', c.email!),
                            if ((c.gstin ?? '').isNotEmpty) _kv('GSTIN', c.gstin!),
                            if ((c.city ?? '').isNotEmpty) _kv('City', c.city!),
                            if (c.creditLimit != null)
                              _kv('Credit', '${_rupees(c.creditLimit!)} / ${c.creditDays ?? 0} days'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: Icon(c.isBlacklisted ? Icons.check_circle_outline : Icons.block,
                            size: 16),
                        label: Text(c.isBlacklisted ? 'Remove Blacklist' : 'Blacklist Customer'),
                        onPressed: _toggleBlacklist,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Addresses',
                              style: GoogleFonts.interTight(fontSize: 14, fontWeight: FontWeight.w700)),
                          TextButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add'),
                              onPressed: _addAddress),
                        ],
                      ),
                      if (_addresses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text('No saved addresses.',
                              style: GoogleFonts.inter(fontSize: 12, color: theme.secondaryText)),
                        )
                      else
                        for (final a in _addresses) _addressRow(theme, a),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Contacts',
                              style: GoogleFonts.interTight(fontSize: 14, fontWeight: FontWeight.w700)),
                          TextButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add'),
                              onPressed: _addContact),
                        ],
                      ),
                      if (_contacts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text('No additional contacts.',
                              style: GoogleFonts.inter(fontSize: 12, color: theme.secondaryText)),
                        )
                      else
                        for (final ct in _contacts) _contactRow(theme, ct),
                      const SizedBox(height: 16),
                      Text('Orders',
                          style: GoogleFonts.interTight(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      if (_orders.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text('No orders yet.',
                              style: GoogleFonts.inter(fontSize: 12, color: theme.secondaryText)),
                        )
                      else
                        for (final o in _orders) _orderRow(theme, o),
                      DeleteAction.button(
                        context: context,
                        label: 'Delete Customer',
                        busy: _deleting,
                        onPressed: () async {
                          setState(() => _deleting = true);
                          final deleted = await DeleteAction.run(
                            context,
                            table: 'customers',
                            id: c.id!,
                            entityLabel: 'customer',
                            check: () async => DeleteCheck.allow,
                            reasonRequired: true,
                          );
                          if (deleted && mounted) {
                            Navigator.of(context).pop(true);
                          } else if (mounted) {
                            setState(() => _deleting = false);
                          }
                        },
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _kpiCard(FlutterFlowTheme theme, String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: theme.secondaryText)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.interTight(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _addressRow(FlutterFlowTheme theme, CustomerAddressesRow a) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if ((a.label ?? '').isNotEmpty) a.label,
                      if (a.isPrimary) '(Primary)',
                    ].whereType<String>().join(' '),
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                  Text(
                    [
                      a.address ?? '',
                      if ((a.city ?? '').isNotEmpty) a.city,
                      if (a.floor != null) 'Floor ${a.floor}',
                      if (a.hasLift) 'Lift',
                    ].whereType<String>().join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _deleteAddress(a)),
          ],
        ),
      );

  Widget _contactRow(FlutterFlowTheme theme, CustomerContactsRow ct) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ct.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  Text(
                    [
                      if ((ct.designation ?? '').isNotEmpty) ct.designation,
                      if ((ct.phone ?? '').isNotEmpty) ct.phone,
                    ].whereType<String>().join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _deleteContact(ct)),
          ],
        ),
      );

  Widget _orderRow(FlutterFlowTheme theme, OrdersRow o) => InkWell(
        onTap: () => _openOrder(o),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${o.fromCity ?? '—'} → ${o.toCity ?? '—'}',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                    Text(o.status ?? '—',
                        style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText)),
                  ],
                ),
              ),
              Text(_rupees(o.amount ?? 0),
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
            ],
          ),
        ),
      );
}
