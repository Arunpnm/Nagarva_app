import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/flutter_flow_theme.dart';
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

  String _rupees(num v) => '₹${v.toStringAsFixed(0)}';

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
    final theme = FlutterFlowTheme.of(context);
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
            color: theme.primaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Text(bill.billNo ?? '(no bill no)',
                  style: GoogleFonts.interTight(
                      fontSize: 17, fontWeight: FontWeight.w700, color: theme.primaryText)),
              _statusChip(theme, bill.status),
              const SizedBox(height: 10),
              _kv('Date', bill.billDate == null
                  ? '—'
                  : DateFormat('d MMM yyyy').format(bill.billDate!)),
              _kv('Taxable Amount', _rupees(bill.taxableAmount)),
              _kv('GST', '${bill.gstMode ?? '—'} · ${_rupees(bill.gstAmount)}'),
              _kv('TDS', _rupees(bill.tdsAmount)),
              _kv('Total', _rupees(bill.totalAmount)),
              _kv('Paid', _rupees(bill.paidAmount)),
              _kv('Balance', _rupees(_billBalance(bill))),
              if ((bill.notes ?? '').isNotEmpty) _kv('Notes', bill.notes!),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Payments',
                      style: GoogleFonts.interTight(fontSize: 13, fontWeight: FontWeight.w700)),
                  if (_billBalance(bill) > 0.01)
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Record Payment'),
                      onPressed: () async {
                        Navigator.of(sheetCtx).pop();
                        await _recordPayment(bill);
                      },
                    ),
                ],
              ),
              if (payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No payments recorded.',
                      style: GoogleFonts.inter(fontSize: 12, color: theme.secondaryText)),
                )
              else
                for (final p in payments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${p.mode ?? '—'} ${(p.reference ?? '').isNotEmpty ? '· ${p.reference}' : ''}',
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                        ),
                        Text(_rupees(p.amount),
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: Icon(Icons.delete_outline, size: 18, color: theme.error),
                label: Text('Delete Bill', style: TextStyle(color: theme.error)),
                onPressed: () async {
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

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 120, child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey))),
            Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 12.5))),
          ],
        ),
      );

  Widget _statusChip(FlutterFlowTheme theme, String status) {
    final color = {
          'unpaid': Colors.red,
          'partial': Colors.orange,
          'paid': Colors.green,
        }[status] ??
        Colors.grey;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(status, style: GoogleFonts.inter(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final v = _vendor;
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
          title: Text(v?.name ?? 'Vendor',
              style: theme.titleLarge.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          centerTitle: true,
          elevation: 0,
          actions: [
            if (v != null)
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _editVendor),
          ],
        ),
        floatingActionButton: v == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _addBill,
                icon: const Icon(Icons.add),
                label: const Text('Add Bill'),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : v == null
                ? const Center(child: Text('Vendor not found.'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((v.vendorType ?? '').isNotEmpty) _kv('Type', v.vendorType!),
                            if ((v.contactPerson ?? '').isNotEmpty)
                              _kv('Contact', v.contactPerson!),
                            if ((v.phone ?? '').isNotEmpty) _kv('Phone', v.phone!),
                            if ((v.email ?? '').isNotEmpty) _kv('Email', v.email!),
                            if ((v.gstin ?? '').isNotEmpty) _kv('GSTIN', v.gstin!),
                            if ((v.city ?? '').isNotEmpty) _kv('City', v.city!),
                            if (v.tdsApplicable)
                              _kv('TDS', '${v.tdsRatePct ?? 0}% ${v.tdsSection ?? ''}'),
                            if (v.paymentTermsDays != null)
                              _kv('Terms', '${v.paymentTermsDays} days'),
                            if (!v.active) _kv('Status', 'Inactive'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Bills',
                          style: GoogleFonts.interTight(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_bills.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('No bills yet.',
                              style: GoogleFonts.inter(color: theme.secondaryText)),
                        )
                      else
                        for (final b in _bills) _billRow(theme, b),
                      DeleteAction.button(
                        context: context,
                        label: 'Delete Vendor',
                        busy: _deleting,
                        onPressed: () async {
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
                        },
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _billRow(FlutterFlowTheme theme, VendorBillsRow b) {
    return InkWell(
      onTap: () => _openBill(b),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
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
                  Text(b.billNo ?? '(no bill no)',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    b.billDate == null ? '—' : DateFormat('d MMM yyyy').format(b.billDate!),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_rupees(b.totalAmount),
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                _statusChip(theme, b.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
