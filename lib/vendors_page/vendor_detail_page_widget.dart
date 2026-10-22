import '/components/ng_widgets.dart';
import 'package:flutter/material.dart';
import '/flutter_flow/custom_functions.dart' as functions;

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';

class VendorDetailPageWidget extends StatefulWidget {
  const VendorDetailPageWidget({super.key, this.vendorId});
  final String? vendorId;

  static String routeName = 'VendorDetailPage';
  static String routePath = '/vendor-detail';

  @override
  State<VendorDetailPageWidget> createState() => _VendorDetailPageWidgetState();
}

class _VendorDetailPageWidgetState extends State<VendorDetailPageWidget> {
  bool _loading = true;
  bool _deleting = false;
  VendorsRow? _vendor;
  List<VendorBillsRow> _bills = [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.vendorId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final vendors = await VendorsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.vendorId!),
      );
      _vendor = vendors.isNotEmpty ? vendors.first : null;
      _bills = await VendorBillsTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eq('vendor_id', widget.vendorId!)
            .order('bill_date', ascending: false),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load vendor: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _billBalance(VendorBillsRow b) => b.totalAmount - b.tdsAmount - b.paidAmount;

  String _rupees(num v) => functions.inrFull(v.toDouble());

  Future<void> _editVendor() async {
    final v = _vendor;
    if (v == null) return;
    final nameCtrl = TextEditingController(text: v.name);
    final contactCtrl = TextEditingController(text: v.contactPerson ?? '');
    final phoneCtrl = TextEditingController(text: v.phone ?? '');
    final emailCtrl = TextEditingController(text: v.email ?? '');
    final gstinCtrl = TextEditingController(text: v.gstin ?? '');
    final panCtrl = TextEditingController(text: v.pan ?? '');
    final addressCtrl = TextEditingController(text: v.address ?? '');
    final cityCtrl = TextEditingController(text: v.city ?? '');
    final bankNameCtrl = TextEditingController(text: v.bankName ?? '');
    final bankAccCtrl = TextEditingController(text: v.bankAccount ?? '');
    final bankIfscCtrl = TextEditingController(text: v.bankIfsc ?? '');
    final upiCtrl = TextEditingController(text: v.upiId ?? '');
    final tdsRateCtrl =
        TextEditingController(text: v.tdsRatePct == null ? '' : '${v.tdsRatePct}');
    final termsCtrl = TextEditingController(
        text: v.paymentTermsDays == null ? '' : '${v.paymentTermsDays}');
    final notesCtrl = TextEditingController(text: v.notes ?? '');
    String type = v.vendorType ?? 'other';
    bool tdsApplicable = v.tdsApplicable;
    bool active = v.active;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Edit Vendor'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name')),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Vendor Type'),
                    items: const [
                      DropdownMenuItem(value: 'porter', child: Text('Porter')),
                      DropdownMenuItem(value: 'vehicle', child: Text('Vehicle Owner')),
                      DropdownMenuItem(
                          value: 'packing_material', child: Text('Packing Material')),
                      DropdownMenuItem(value: 'labour', child: Text('Labour Contractor')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (val) => setDialogState(() => type = val ?? 'other'),
                  ),
                  TextField(
                      controller: contactCtrl,
                      decoration: const InputDecoration(labelText: 'Contact Person')),
                  TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      keyboardType: TextInputType.phone),
                  TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email')),
                  TextField(
                      controller: gstinCtrl,
                      decoration: const InputDecoration(labelText: 'GSTIN')),
                  TextField(
                      controller: panCtrl,
                      decoration: const InputDecoration(labelText: 'PAN')),
                  TextField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(labelText: 'Address')),
                  TextField(
                      controller: cityCtrl,
                      decoration: const InputDecoration(labelText: 'City')),
                  const Divider(),
                  TextField(
                      controller: bankNameCtrl,
                      decoration: const InputDecoration(labelText: 'Bank Name')),
                  TextField(
                      controller: bankAccCtrl,
                      decoration: const InputDecoration(labelText: 'Bank Account No')),
                  TextField(
                      controller: bankIfscCtrl,
                      decoration: const InputDecoration(labelText: 'IFSC')),
                  TextField(
                      controller: upiCtrl,
                      decoration: const InputDecoration(labelText: 'UPI ID')),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('TDS Applicable'),
                    value: tdsApplicable,
                    onChanged: (val) => setDialogState(() => tdsApplicable = val),
                  ),
                  if (tdsApplicable)
                    TextField(
                        controller: tdsRateCtrl,
                        decoration: const InputDecoration(labelText: 'TDS Rate %'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  TextField(
                      controller: termsCtrl,
                      decoration: const InputDecoration(labelText: 'Payment Terms (days)'),
                      keyboardType: TextInputType.number),
                  TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      maxLines: 2),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: active,
                    onChanged: (val) => setDialogState(() => active = val),
                  ),
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
      await VendorsTable().update(
        data: {
          'name': nameCtrl.text.trim(),
          'vendor_type': type,
          'contact_person':
              contactCtrl.text.trim().isEmpty ? null : contactCtrl.text.trim(),
          'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
          'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
          'gstin': gstinCtrl.text.trim().isEmpty ? null : gstinCtrl.text.trim(),
          'pan': panCtrl.text.trim().isEmpty ? null : panCtrl.text.trim(),
          'address': addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
          'city': cityCtrl.text.trim().isEmpty ? null : cityCtrl.text.trim(),
          'bank_name':
              bankNameCtrl.text.trim().isEmpty ? null : bankNameCtrl.text.trim(),
          'bank_account':
              bankAccCtrl.text.trim().isEmpty ? null : bankAccCtrl.text.trim(),
          'bank_ifsc':
              bankIfscCtrl.text.trim().isEmpty ? null : bankIfscCtrl.text.trim(),
          'upi_id': upiCtrl.text.trim().isEmpty ? null : upiCtrl.text.trim(),
          'tds_applicable': tdsApplicable,
          'tds_rate_pct': tdsApplicable ? double.tryParse(tdsRateCtrl.text.trim()) : null,
          'payment_terms_days': int.tryParse(termsCtrl.text.trim()),
          'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          'active': active,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.vendorId!),
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

  Future<void> _addBill() async {
    if (widget.vendorId == null) return;
    final billNoCtrl = TextEditingController();
    final taxableCtrl = TextEditingController();
    final gstPctCtrl = TextEditingController(text: '0');
    final tdsCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();
    DateTime billDate = DateTime.now();
    String gstMode = 'none';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Add Vendor Bill'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: billNoCtrl,
                      decoration: const InputDecoration(labelText: 'Bill No'),
                      autofocus: true),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bill Date'),
                    subtitle: Text(DateFormat('d MMM yyyy').format(billDate)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogCtx,
                        initialDate: billDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setDialogState(() => billDate = picked);
                    },
                  ),
                  TextField(
                      controller: taxableCtrl,
                      decoration: const InputDecoration(labelText: 'Taxable Amount'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  DropdownButtonFormField<String>(
                    initialValue: gstMode,
                    decoration: const InputDecoration(labelText: 'GST Mode'),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('None')),
                      DropdownMenuItem(value: 'cgst_sgst', child: Text('CGST + SGST')),
                      DropdownMenuItem(value: 'igst', child: Text('IGST')),
                    ],
                    onChanged: (v) => setDialogState(() => gstMode = v ?? 'none'),
                  ),
                  if (gstMode != 'none')
                    TextField(
                        controller: gstPctCtrl,
                        decoration: const InputDecoration(labelText: 'GST %'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  TextField(
                      controller: tdsCtrl,
                      decoration: const InputDecoration(labelText: 'TDS Amount'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
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
                onPressed: taxableCtrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final taxable = double.tryParse(taxableCtrl.text.trim()) ?? 0;
    final gstPct = gstMode == 'none' ? 0.0 : (double.tryParse(gstPctCtrl.text.trim()) ?? 0);
    final gstAmount = taxable * gstPct / 100;
    final tds = double.tryParse(tdsCtrl.text.trim()) ?? 0;
    final total = taxable + gstAmount;
    try {
      await VendorBillsTable().insert({
        ...OrgScope.stamp(),
        'vendor_id': widget.vendorId,
        if (billNoCtrl.text.trim().isNotEmpty) 'bill_no': billNoCtrl.text.trim(),
        'bill_date': billDate.toIso8601String().split('T').first,
        'taxable_amount': taxable,
        'gst_mode': gstMode,
        'gst_pct': gstPct,
        'gst_amount': gstAmount,
        'tds_amount': tds,
        'total_amount': total,
        'paid_amount': 0,
        'status': 'unpaid',
        if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
      });
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add bill: $e')));
      }
    }
  }

  Future<void> _openBill(VendorBillsRow bill) async {
    List<VendorPaymentsRow> payments = [];
    try {
      if (bill.id != null) {
        payments = await VendorPaymentsTable().queryRows(
          queryFn: (q) =>
              OrgScope.read(q).eq('bill_id', bill.id!).order('paid_at', ascending: false),
        );
      }
    } catch (_) {}
    if (!mounted) return;
    final ng = NgPalette.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (sheetCtx, scrollController) => Container(
          decoration: BoxDecoration(
            color: ng.sheet,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(NgRadius.sheet)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: ng.w15, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(bill.billNo ?? '(no bill no)',
                        style: NgFonts.mono(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: ng.text)),
                  ),
                  NgPill(
                      switch (bill.status) {
                        'paid' => 'Paid',
                        'partial' => 'Part paid',
                        _ => 'Unpaid',
                      },
                      status: switch (bill.status) {
                        'paid' => NgStatus.green,
                        'partial' => NgStatus.amber,
                        _ => NgStatus.red,
                      }),
                ],
              ),
              const SizedBox(height: 14),
              NgRowsCard(rows: [
                NgKvRow(
                    'Date',
                    bill.billDate == null
                        ? '—'
                        : DateFormat('d MMM yyyy').format(bill.billDate!)),
                NgKvRow('Taxable', _rupees(bill.taxableAmount), mono: true),
                NgKvRow('GST',
                    '${bill.gstMode ?? '—'} · ${_rupees(bill.gstAmount)}'),
                NgKvRow('TDS', _rupees(bill.tdsAmount), mono: true),
                NgKvRow('Total', _rupees(bill.totalAmount), mono: true),
                NgKvRow('Paid', _rupees(bill.paidAmount), mono: true),
                NgKvRow('Balance', _rupees(_billBalance(bill)), mono: true),
                if ((bill.notes ?? '').isNotEmpty) NgKvRow('Notes', bill.notes!),
              ]),
              const SizedBox(height: 18),
              NgGroupTitle(
                'Payments',
                actionLabel: 'Record payment',
                onAction: _billBalance(bill) > 0.01
                    ? () async {
                        Navigator.of(sheetCtx).pop();
                        await _recordPayment(bill);
                      }
                    : null,
              ),
              NgRowsCard(rows: [
                for (final p in payments)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                    child: Row(
                      children: [
                        Icon(Icons.payments_outlined, size: 18, color: ng.faint),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${p.mode ?? '—'}${(p.reference ?? '').isNotEmpty ? ' · ${p.reference}' : ''}',
                            style: NgFonts.geist(fontSize: 13.5, color: ng.text),
                          ),
                        ),
                        Text(_rupees(p.amount),
                            style: NgFonts.mono(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: ng.text)),
                        IconButton(
                          tooltip: 'Delete payment',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 18, color: ng.red),
                          onPressed: () async {
                            Navigator.of(sheetCtx).pop();
                            await _deleteVendorPayment(bill, p);
                          },
                        ),
                      ],
                    ),
                  ),
              ], empty: 'No payments recorded.'),
              const SizedBox(height: 18),
              NgWideButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete bill',
                danger: true,
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  if (bill.id == null) return;
                  final deleted = await DeleteAction.run(
                    context,
                    table: 'vendor_bills',
                    id: bill.id!,
                    entityLabel: 'bill',
                    check: () async => DeleteCheck.allow,
                    onDeleted: () {
                      _changed = true;
                      _load();
                    },
                  );
                  if (deleted && mounted) _load();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Item 11 sweep (16 Aug 2026): vendor_payments had soft-delete columns
  // and a recycle-bin-eligible row shape (added to kSoftDeleteTables
  // alongside vendors/vendor_bills) but no delete UI. Mirrors
  // _recordPayment's own bill.paid_amount/status maintenance in reverse —
  // there's no DB trigger for this, so a delete that skipped this step
  // would leave the bill's paid_amount overstated.
  Future<void> _deleteVendorPayment(
      VendorBillsRow bill, VendorPaymentsRow payment) async {
    if (bill.id == null) return;
    final deleted = await DeleteAction.run(
      context,
      table: 'vendor_payments',
      id: payment.id!,
      entityLabel: 'payment',
      check: () async => DeleteCheck.allow,
    );
    if (!deleted) return;
    try {
      final newPaid = (bill.paidAmount - payment.amount).clamp(0, double.infinity);
      final balance = bill.totalAmount - bill.tdsAmount - newPaid;
      final newStatus = balance <= 0.01 ? 'paid' : (newPaid > 0 ? 'partial' : 'unpaid');
      await VendorBillsTable().update(
        data: {
          'paid_amount': newPaid,
          'status': newStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', bill.id!),
      );
    } catch (_) {
      // The payment is already deleted (recoverable via the recycle bin);
      // a failure to resync the bill's rollup shouldn't look like the
      // whole action failed. _load() below will still show the stale
      // paid_amount until the next successful write touches it.
    }
    _changed = true;
    await _load();
  }

  Future<void> _recordPayment(VendorBillsRow bill) async {
    final amountCtrl =
        TextEditingController(text: _billBalance(bill).toStringAsFixed(0));
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String mode = 'cash';
    DateTime paidAt = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Record Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                ],
                onChanged: (v) => setDialogState(() => mode = v ?? 'cash'),
              ),
              TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(labelText: 'Reference No')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(DateFormat('d MMM yyyy').format(paidAt)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogCtx,
                    initialDate: paidAt,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setDialogState(() => paidAt = picked);
                },
              ),
              TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Note')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: (double.tryParse(amountCtrl.text.trim()) ?? 0) <= 0
                    ? null
                    : () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || bill.id == null) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    try {
      await VendorPaymentsTable().insert({
        ...OrgScope.stamp(),
        'vendor_id': widget.vendorId,
        'bill_id': bill.id,
        'amount': amount,
        'mode': mode,
        if (refCtrl.text.trim().isNotEmpty) 'reference': refCtrl.text.trim(),
        'paid_at': paidAt.toIso8601String(),
        if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
      });
      final newPaid = bill.paidAmount + amount;
      final balance = bill.totalAmount - bill.tdsAmount - newPaid;
      final newStatus = balance <= 0.01 ? 'paid' : (newPaid > 0 ? 'partial' : 'unpaid');
      await VendorBillsTable().update(
        data: {
          'paid_amount': newPaid,
          'status': newStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', bill.id!),
      );
      _changed = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Payment recorded')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not record payment: $e')));
      }
    }
  }

  Future<void> _deleteVendor(VendorsRow v) async {
    setState(() => _deleting = true);
    final deleted = await DeleteAction.run(
      context,
      table: 'vendors',
      id: v.id!,
      entityLabel: 'vendor',
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
    final v = _vendor;
    final outstanding = _bills
        .where((b) => b.status != 'paid')
        .fold<double>(0, (s, b) => s + (b.totalAmount - b.paidAmount));
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
              : v == null
                  ? Center(
                      child: NgEmptyState(
                        icon: Icons.storefront_outlined,
                        title: 'Vendor not found',
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
                          title: v.name,
                          avatar: v.name,
                          subtitle: [
                            if ((v.vendorType ?? '').isNotEmpty) v.vendorType!,
                            if ((v.city ?? '').isNotEmpty) v.city!,
                            if (!v.active) 'Inactive',
                          ].join(' · '),
                          onBack: () => Navigator.of(context).pop(_changed),
                          actions: [
                            NgHeaderButtonBox(
                                icon: Icons.edit_outlined, onTap: _editVendor),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: outstanding > 0 ? ng.redBg : ng.s1,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('Outstanding',
                                    style: NgFonts.geist(
                                        fontSize: 13, color: ng.mute)),
                              ),
                              Text(_rupees(outstanding),
                                  style: NgFonts.mono(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: outstanding > 0
                                          ? ng.red
                                          : ng.green)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        NgRowsCard(rows: [
                          if ((v.vendorType ?? '').isNotEmpty)
                            NgKvRow('Type', v.vendorType!),
                          if ((v.contactPerson ?? '').isNotEmpty)
                            NgKvRow('Contact', v.contactPerson!),
                          if ((v.phone ?? '').isNotEmpty)
                            NgKvRow('Phone', v.phone!, mono: true),
                          if ((v.email ?? '').isNotEmpty)
                            NgKvRow('Email', v.email!),
                          if ((v.gstin ?? '').isNotEmpty)
                            NgKvRow('GSTIN', v.gstin!, mono: true),
                          if ((v.city ?? '').isNotEmpty) NgKvRow('City', v.city!),
                          if (v.tdsApplicable)
                            NgKvRow('TDS',
                                '${v.tdsRatePct ?? 0}% ${v.tdsSection ?? ''}'),
                          if (v.paymentTermsDays != null)
                            NgKvRow('Terms', '${v.paymentTermsDays} days'),
                        ], empty: 'No details added.'),
                        const SizedBox(height: 20),
                        NgGroupTitle('Bills',
                            actionLabel: 'Add bill', onAction: _addBill),
                        NgRowsCard(rows: [
                          for (final b in _bills) _billRow(ng, b),
                        ], empty: 'No bills yet.'),
                        const SizedBox(height: 22),
                        NgWideButton(
                          icon: Icons.delete_outline_rounded,
                          label: _deleting ? 'Deleting…' : 'Delete vendor',
                          danger: true,
                          onTap: _deleting ? null : () => _deleteVendor(v),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _billRow(NgPalette ng, VendorBillsRow b) {
    final (label, tone) = switch (b.status) {
      'paid' => ('Paid', NgStatus.green),
      'partial' => ('Part paid', NgStatus.amber),
      _ => ('Unpaid', NgStatus.red),
    };
    return InkWell(
      onTap: () => _openBill(b),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.billNo ?? '(no bill no)',
                      style: NgFonts.mono(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ng.text)),
                  const SizedBox(height: 2),
                  Text(
                    b.billDate == null
                        ? '—'
                        : DateFormat('d MMM yyyy').format(b.billDate!),
                    style: NgFonts.geist(fontSize: 12.5, color: ng.mute),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_rupees(b.totalAmount),
                    style: NgFonts.mono(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ng.text)),
                const SizedBox(height: 4),
                NgPill(label, status: tone),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: ng.faint),
          ],
        ),
      ),
    );
  }
}
