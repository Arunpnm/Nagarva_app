import '/components/ng_widgets.dart';
import 'package:flutter/material.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import 'package:intl/intl.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/ng_tokens.dart';
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

  String _rupees(num v) => functions.inrFull(v.toDouble());

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

  Future<void> _deleteCustomer(CustomersRow c) async {
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
  }

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    final c = _customer;
    final kpi = _kpi;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: ng.bg,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : c == null
                  ? Center(
                      child: NgEmptyState(
                        icon: Icons.person_off_outlined,
                        title: 'Customer not found',
                        action: SizedBox(
                          width: 140,
                          child: NgSecondaryButton(
                              label: 'Go back',
                              onPressed: () => Navigator.of(context).pop()),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                      children: [
                        NgDetailHeader(
                          title: c.name,
                          avatar: c.name,
                          subtitle: [
                            c.customerType,
                            if ((c.city ?? '').isNotEmpty) c.city!,
                          ].where((x) => x.trim().isNotEmpty).join(' · '),
                          onBack: () => Navigator.of(context).pop(_changed),
                          actions: [
                            NgHeaderButtonBox(
                                icon: Icons.edit_outlined,
                                onTap: _editCustomer),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (c.isBlacklisted) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: ng.redBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.block_rounded,
                                    size: 18, color: ng.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Blacklisted${(c.blacklistReason ?? '').isNotEmpty ? ': ${c.blacklistReason}' : ''}',
                                    style: NgFonts.geist(
                                        fontSize: 13,
                                        height: 1.4,
                                        fontWeight: FontWeight.w500,
                                        color: ng.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _actions(ng, c),
                        if (kpi != null) ...[
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(
                                child: NgMiniTile('Orders', '${kpi.totalOrders}')),
                            const SizedBox(width: 8),
                            Expanded(
                                child: NgMiniTile('Lifetime value',
                                    _rupees(kpi.lifetimeValue))),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: NgMiniTile('Avg order',
                                    _rupees(kpi.avgOrderValue))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: NgMiniTile('Outstanding',
                                    _rupees(kpi.outstandingEstimate),
                                    color: kpi.outstandingEstimate > 0
                                        ? ng.red
                                        : null)),
                          ]),
                        ],
                        const SizedBox(height: 20),
                        NgGroupTitle('Details'),
                        NgRowsCard(rows: [
                          NgKvRow('Type', c.customerType),
                          if ((c.companyName ?? '').isNotEmpty)
                            NgKvRow('Company', c.companyName!),
                          if ((c.phone ?? '').isNotEmpty)
                            NgKvRow('Phone', c.phone!, mono: true),
                          if ((c.altPhone ?? '').isNotEmpty)
                            NgKvRow('Alt phone', c.altPhone!, mono: true),
                          if ((c.email ?? '').isNotEmpty)
                            NgKvRow('Email', c.email!),
                          if ((c.gstin ?? '').isNotEmpty)
                            NgKvRow('GSTIN', c.gstin!, mono: true),
                          if ((c.city ?? '').isNotEmpty)
                            NgKvRow('City', c.city!),
                          if (c.creditLimit != null)
                            NgKvRow('Credit',
                                '${_rupees(c.creditLimit!)} / ${c.creditDays ?? 0} days'),
                        ]),
                        const SizedBox(height: 20),
                        NgGroupTitle('Addresses', onAction: _addAddress),
                        NgRowsCard(rows: [
                          for (final a in _addresses) _addressRow(ng, a),
                        ], empty: 'No saved addresses.'),
                        const SizedBox(height: 20),
                        NgGroupTitle('Contacts', onAction: _addContact),
                        NgRowsCard(rows: [
                          for (final ct in _contacts) _contactRow(ng, ct),
                        ], empty: 'No additional contacts.'),
                        const SizedBox(height: 20),
                        NgGroupTitle('Orders'),
                        NgRowsCard(rows: [
                          for (final o in _orders) _orderRow(ng, o),
                        ], empty: 'No orders yet.'),
                        const SizedBox(height: 22),
                        NgWideButton(
                          icon: c.isBlacklisted
                              ? Icons.check_circle_outline_rounded
                              : Icons.block_rounded,
                          label: c.isBlacklisted
                              ? 'Remove from blacklist'
                              : 'Blacklist customer',
                          onTap: _toggleBlacklist,
                        ),
                        const SizedBox(height: 8),
                        NgWideButton(
                          icon: Icons.delete_outline_rounded,
                          label: _deleting ? 'Deleting…' : 'Delete customer',
                          danger: true,
                          onTap: _deleting ? null : () => _deleteCustomer(c),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _actions(NgPalette ng, CustomersRow c) {
    final phone = (c.phone ?? '').trim();
    final email = (c.email ?? '').trim();
    Widget act(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: Opacity(
            opacity: onTap == null ? 0.45 : 1,
            child: NgCard(
              radius: 14,
              padding: EdgeInsets.zero,
              onTap: onTap,
              child: SizedBox(
                height: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 20, color: ng.acc),
                    const SizedBox(height: 2),
                    Text(label,
                        style: NgFonts.geist(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ng.text)),
                  ],
                ),
              ),
            ),
          ),
        );
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final wa = digits.length == 10 ? '91$digits' : digits;
    return Row(children: [
      act(Icons.call_rounded, 'Call',
          phone.isEmpty ? null : () => launchURL('tel:$phone')),
      const SizedBox(width: 8),
      act(Icons.chat_rounded, 'WhatsApp',
          wa.isEmpty ? null : () => launchURL('https://wa.me/$wa')),
      const SizedBox(width: 8),
      act(Icons.mail_outline_rounded, 'Email',
          email.isEmpty ? null : () => launchURL('mailto:$email')),
    ]);
  }

  Widget _addressRow(NgPalette ng, CustomerAddressesRow a) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
        child: Row(
          children: [
            Icon(Icons.location_on_outlined, size: 19, color: ng.faint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        (a.label ?? '').isEmpty ? 'Address' : a.label!,
                        style: NgFonts.geist(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: ng.soft),
                      ),
                    ),
                    if (a.isPrimary) ...[
                      const SizedBox(width: 6),
                      const NgPill('Primary', status: NgStatus.accent),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    [
                      a.address ?? '',
                      if ((a.city ?? '').isNotEmpty) a.city,
                      if (a.floor != null) 'Floor ${a.floor}',
                      if (a.hasLift) 'Lift',
                    ].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                    style: NgFonts.geist(
                        fontSize: 13.5, height: 1.35, color: ng.text),
                  ),
                ],
              ),
            ),
            IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 19, color: ng.mute),
                onPressed: () => _deleteAddress(a)),
          ],
        ),
      );

  Widget _contactRow(NgPalette ng, CustomerContactsRow ct) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
        child: Row(
          children: [
            Icon(Icons.person_outline_rounded, size: 19, color: ng.faint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ct.name,
                      style: NgFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ng.text)),
                  Text(
                    [
                      if ((ct.designation ?? '').isNotEmpty) ct.designation,
                      if ((ct.phone ?? '').isNotEmpty) ct.phone,
                    ].whereType<String>().join(' · '),
                    style: NgFonts.geist(fontSize: 12.5, color: ng.mute),
                  ),
                ],
              ),
            ),
            IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 19, color: ng.mute),
                onPressed: () => _deleteContact(ct)),
          ],
        ),
      );

  Widget _orderRow(NgPalette ng, OrdersRow o) {
    final paid = (o.paymentStatus ?? '').toLowerCase();
    final (label, tone) = switch (paid) {
      'paid' => ('Paid', NgStatus.green),
      'partial' => ('Part paid', NgStatus.amber),
      _ => ((o.status ?? '—'), NgStatus.neutral),
    };
    final date = o.moveDateOrNull ?? o.createdAt;
    return InkWell(
      onTap: () => _openOrder(o),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text('${o.fromCity ?? '—'} → ${o.toCity ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ng.text)),
              ),
              Text(_rupees(o.amount ?? 0),
                  style: NgFonts.mono(
                      fontSize: 14, fontWeight: FontWeight.w600, color: ng.text)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(
                    '${o.id ?? ''}${date == null ? '' : ' · ${DateFormat('d MMM yy').format(date)}'}',
                    style: NgFonts.mono(fontSize: 12, color: ng.faint)),
              ),
              NgPill(label, status: tone),
            ]),
          ],
        ),
      ),
    );
  }
}
