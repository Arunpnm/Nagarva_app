import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/order_picker_dialog.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

/// Insurance & Claims (Session 4, Part C-8). Live schema confirmed
/// directly against the DB: insurance_policies + claims + claim_items.
/// Neither carries soft-delete columns — plain hard delete where offered
/// (claim items only; policies/claims stay as a permanent record once
/// created, matching how LR Register treats issued LRs).
class InsuranceClaimsPageWidget extends StatefulWidget {
  const InsuranceClaimsPageWidget({super.key});

  static String routeName = 'InsuranceClaimsPage';
  static String routePath = '/insurance-claims';

  @override
  State<InsuranceClaimsPageWidget> createState() =>
      _InsuranceClaimsPageWidgetState();
}

class _InsuranceClaimsPageWidgetState extends State<InsuranceClaimsPageWidget>
    with SingleTickerProviderStateMixin, RefreshOnPopMixin<InsuranceClaimsPageWidget> {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _loading = true;
  List<InsurancePoliciesRow> _policies = [];
  List<ClaimsRow> _claims = [];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _policies = await InsurancePoliciesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('created_at', ascending: false),
      );
      _claims = await ClaimsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('created_at', ascending: false),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _rupees(num v) => '₹${v.toStringAsFixed(0)}';

  // ---- Policies ------------------------------------------------------------

  Future<void> _newPolicy() async {
    final order = await OrderPickerDialog.show(context);
    if (order == null || !mounted) return;
    final insurerCtrl = TextEditingController();
    final policyNoCtrl = TextEditingController();
    final declaredCtrl = TextEditingController();
    final premiumPctCtrl = TextEditingController(text: '0');
    final gstCtrl = TextEditingController(text: '0');
    final excessCtrl = TextEditingController();
    String policyType = 'transit';
    DateTime coverageStart = DateTime.now();
    DateTime? coverageEnd;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text('New Policy — ${order.id}'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: policyType,
                    decoration: const InputDecoration(labelText: 'Policy Type'),
                    items: const [
                      DropdownMenuItem(value: 'transit', child: Text('Transit')),
                      DropdownMenuItem(value: 'godown', child: Text('Godown')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setDialogState(() => policyType = v ?? 'transit'),
                  ),
                  TextField(
                      controller: insurerCtrl,
                      decoration: const InputDecoration(labelText: 'Insurer Name')),
                  TextField(
                      controller: policyNoCtrl,
                      decoration: const InputDecoration(labelText: 'Policy No')),
                  TextField(
                      controller: declaredCtrl,
                      decoration: const InputDecoration(labelText: 'Declared Value'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  TextField(
                      controller: premiumPctCtrl,
                      decoration: const InputDecoration(labelText: 'Premium %'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  TextField(
                      controller: gstCtrl,
                      decoration: const InputDecoration(labelText: 'GST on Premium'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  TextField(
                      controller: excessCtrl,
                      decoration: const InputDecoration(labelText: 'Excess Amount'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Coverage Start'),
                    subtitle: Text(DateFormat('d MMM yyyy').format(coverageStart)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: dialogCtx,
                          initialDate: coverageStart,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => coverageStart = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Coverage End'),
                    subtitle: Text(coverageEnd == null
                        ? '—'
                        : DateFormat('d MMM yyyy').format(coverageEnd!)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: dialogCtx,
                          initialDate: coverageEnd ?? coverageStart,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => coverageEnd = picked);
                    },
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
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final declared = double.tryParse(declaredCtrl.text.trim()) ?? 0;
    final premiumPct = double.tryParse(premiumPctCtrl.text.trim()) ?? 0;
    final premiumAmount = declared * premiumPct / 100;
    final gst = double.tryParse(gstCtrl.text.trim()) ?? 0;
    try {
      await InsurancePoliciesTable().insert({
        ...OrgScope.stamp(),
        'order_id': order.id,
        'customer_id': order.customerId,
        'policy_type': policyType,
        if (insurerCtrl.text.trim().isNotEmpty) 'insurer_name': insurerCtrl.text.trim(),
        if (policyNoCtrl.text.trim().isNotEmpty) 'policy_no': policyNoCtrl.text.trim(),
        'declared_value': declared,
        'premium_pct': premiumPct,
        'premium_amount': premiumAmount,
        'gst_on_premium': gst,
        'total_premium': premiumAmount + gst,
        'coverage_start': coverageStart.toIso8601String().split('T').first,
        if (coverageEnd != null)
          'coverage_end': coverageEnd!.toIso8601String().split('T').first,
        'excess_amount': double.tryParse(excessCtrl.text.trim()),
        'status': 'active',
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create policy: $e')));
      }
    }
  }

  // ---- Claims ---------------------------------------------------------------

  Future<void> _newClaim() async {
    final order = await OrderPickerDialog.show(context);
    if (order == null || !mounted) return;
    InsurancePoliciesRow? matchingPolicy;
    for (final p in _policies) {
      if (p.orderId == order.id) {
        matchingPolicy = p;
        break;
      }
    }
    final descCtrl = TextEditingController();
    final claimedCtrl = TextEditingController();
    String claimType = 'damage';
    DateTime incidentDate = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text('New Claim — ${order.id}'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (matchingPolicy != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Linked to policy ${matchingPolicy.policyNo ?? matchingPolicy.id}',
                          style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey)),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: claimType,
                    decoration: const InputDecoration(labelText: 'Claim Type'),
                    items: const [
                      DropdownMenuItem(value: 'damage', child: Text('Damage')),
                      DropdownMenuItem(value: 'loss', child: Text('Loss')),
                      DropdownMenuItem(value: 'theft', child: Text('Theft')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setDialogState(() => claimType = v ?? 'damage'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Incident Date'),
                    subtitle: Text(DateFormat('d MMM yyyy').format(incidentDate)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: dialogCtx,
                          initialDate: incidentDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => incidentDate = picked);
                    },
                  ),
                  TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Description'),
                      maxLines: 2),
                  TextField(
                      controller: claimedCtrl,
                      decoration: const InputDecoration(labelText: 'Claimed Amount'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ClaimsTable().insert({
        ...OrgScope.stamp(),
        'order_id': order.id,
        'customer_id': order.customerId,
        if (matchingPolicy != null) 'policy_id': matchingPolicy.id,
        'claim_type': claimType,
        'intimated_at': DateTime.now().toUtc().toIso8601String(),
        'incident_date': incidentDate.toIso8601String().split('T').first,
        if (descCtrl.text.trim().isNotEmpty) 'description': descCtrl.text.trim(),
        'claimed_amount': double.tryParse(claimedCtrl.text.trim()) ?? 0,
        'status': 'intimated',
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create claim: $e')));
      }
    }
  }

  Future<void> _openClaim(ClaimsRow claim) async {
    if (claim.id == null) return;
    List<ClaimItemsRow> items = [];
    try {
      items = await ClaimItemsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('claim_id', claim.id!).order('created_at'),
      );
    } catch (_) {}
    if (!mounted) return;
    final theme = FlutterFlowTheme.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
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
              Text(claim.claimNo ?? claim.id ?? '(claim)',
                  style: GoogleFonts.interTight(
                      fontSize: 17, fontWeight: FontWeight.w700, color: theme.primaryText)),
              _statusChip(theme, claim.status),
              const SizedBox(height: 10),
              _kv('Order', claim.orderId ?? '—'),
              _kv('Type', claim.claimType ?? '—'),
              _kv('Incident Date', claim.incidentDate == null
                  ? '—'
                  : DateFormat('d MMM yyyy').format(claim.incidentDate!)),
              if ((claim.description ?? '').isNotEmpty) _kv('Description', claim.description!),
              _kv('Claimed', _rupees(claim.claimedAmount)),
              if (claim.assessedAmount != null) _kv('Assessed', _rupees(claim.assessedAmount!)),
              if (claim.approvedAmount != null) _kv('Approved', _rupees(claim.approvedAmount!)),
              if (claim.settledAmount != null) _kv('Settled', _rupees(claim.settledAmount!)),
              if ((claim.surveyorName ?? '').isNotEmpty) _kv('Surveyor', claim.surveyorName!),
              if ((claim.rejectionReason ?? '').isNotEmpty)
                _kv('Rejection Reason', claim.rejectionReason!),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Items',
                      style: GoogleFonts.interTight(fontSize: 13, fontWeight: FontWeight.w700)),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Item'),
                    onPressed: () async {
                      Navigator.of(sheetCtx).pop();
                      await _addClaimItem(claim);
                      if (mounted) _openClaim(claim);
                    },
                  ),
                ],
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No items added yet.',
                      style: GoogleFonts.inter(fontSize: 12, color: theme.secondaryText)),
                )
              else
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${it.itemName}${it.damageType != null ? ' (${it.damageType})' : ''}',
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                        ),
                        Text(_rupees(it.claimedAmount),
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Update Status / Settlement'),
                onPressed: () async {
                  Navigator.of(sheetCtx).pop();
                  await _updateClaim(claim);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addClaimItem(ClaimsRow claim) async {
    if (claim.id == null) return;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final declaredCtrl = TextEditingController();
    final claimedCtrl = TextEditingController();
    String damageType = 'damaged';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Add Claim Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Item Name'),
                  autofocus: true),
              TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description')),
              DropdownButtonFormField<String>(
                initialValue: damageType,
                decoration: const InputDecoration(labelText: 'Damage Type'),
                items: const [
                  DropdownMenuItem(value: 'damaged', child: Text('Damaged')),
                  DropdownMenuItem(value: 'lost', child: Text('Lost')),
                  DropdownMenuItem(value: 'broken', child: Text('Broken')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setDialogState(() => damageType = v ?? 'damaged'),
              ),
              TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              TextField(
                  controller: declaredCtrl,
                  decoration: const InputDecoration(labelText: 'Declared Value'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              TextField(
                  controller: claimedCtrl,
                  decoration: const InputDecoration(labelText: 'Claimed Amount'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
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
      ),
    );
    if (ok != true) return;
    try {
      await ClaimItemsTable().insert({
        ...OrgScope.stamp(),
        'claim_id': claim.id,
        'item_name': nameCtrl.text.trim(),
        if (descCtrl.text.trim().isNotEmpty) 'description': descCtrl.text.trim(),
        'quantity': double.tryParse(qtyCtrl.text.trim()) ?? 1,
        'declared_value': double.tryParse(declaredCtrl.text.trim()),
        'claimed_amount': double.tryParse(claimedCtrl.text.trim()) ?? 0,
        'damage_type': damageType,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add item: $e')));
      }
    }
  }

  Future<void> _updateClaim(ClaimsRow claim) async {
    if (claim.id == null) return;
    final assessedCtrl =
        TextEditingController(text: claim.assessedAmount?.toString() ?? '');
    final approvedCtrl =
        TextEditingController(text: claim.approvedAmount?.toString() ?? '');
    final settledCtrl =
        TextEditingController(text: claim.settledAmount?.toString() ?? '');
    final surveyorNameCtrl = TextEditingController(text: claim.surveyorName ?? '');
    final surveyorPhoneCtrl = TextEditingController(text: claim.surveyorPhone ?? '');
    final rejectionCtrl = TextEditingController(text: claim.rejectionReason ?? '');
    String status = claim.status;
    String settlementMode = claim.settlementMode ?? 'bank_transfer';
    String borneBy = claim.borneBy ?? 'insurer';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Update Claim'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'intimated', child: Text('Intimated')),
                      DropdownMenuItem(value: 'surveyed', child: Text('Surveyed')),
                      DropdownMenuItem(value: 'approved', child: Text('Approved')),
                      DropdownMenuItem(value: 'settled', child: Text('Settled')),
                      DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v ?? status),
                  ),
                  const Divider(),
                  TextField(
                      controller: surveyorNameCtrl,
                      decoration: const InputDecoration(labelText: 'Surveyor Name')),
                  TextField(
                      controller: surveyorPhoneCtrl,
                      decoration: const InputDecoration(labelText: 'Surveyor Phone')),
                  TextField(
                      controller: assessedCtrl,
                      decoration: const InputDecoration(labelText: 'Assessed Amount'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  TextField(
                      controller: approvedCtrl,
                      decoration: const InputDecoration(labelText: 'Approved Amount'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  if (status == 'settled') ...[
                    const Divider(),
                    TextField(
                        controller: settledCtrl,
                        decoration: const InputDecoration(labelText: 'Settled Amount'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                    DropdownButtonFormField<String>(
                      initialValue: settlementMode,
                      decoration: const InputDecoration(labelText: 'Settlement Mode'),
                      items: const [
                        DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                        DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(
                            value: 'adjusted_in_bill', child: Text('Adjusted in Bill')),
                      ],
                      onChanged: (v) => setDialogState(() => settlementMode = v ?? settlementMode),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: borneBy,
                      decoration: const InputDecoration(labelText: 'Borne By'),
                      items: const [
                        DropdownMenuItem(value: 'insurer', child: Text('Insurer')),
                        DropdownMenuItem(value: 'company', child: Text('Company')),
                        DropdownMenuItem(value: 'vendor', child: Text('Vendor')),
                      ],
                      onChanged: (v) => setDialogState(() => borneBy = v ?? borneBy),
                    ),
                  ],
                  if (status == 'rejected') ...[
                    const Divider(),
                    TextField(
                        controller: rejectionCtrl,
                        decoration: const InputDecoration(labelText: 'Rejection Reason'),
                        maxLines: 2),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ClaimsTable().update(
        data: {
          'status': status,
          'surveyor_name':
              surveyorNameCtrl.text.trim().isEmpty ? null : surveyorNameCtrl.text.trim(),
          'surveyor_phone':
              surveyorPhoneCtrl.text.trim().isEmpty ? null : surveyorPhoneCtrl.text.trim(),
          'assessed_amount': double.tryParse(assessedCtrl.text.trim()),
          'approved_amount': double.tryParse(approvedCtrl.text.trim()),
          if (status == 'settled') ...{
            'settled_amount': double.tryParse(settledCtrl.text.trim()),
            'settled_at': DateTime.now().toUtc().toIso8601String(),
            'settlement_mode': settlementMode,
            'borne_by': borneBy,
          },
          if (status == 'rejected')
            'rejection_reason':
                rejectionCtrl.text.trim().isEmpty ? null : rejectionCtrl.text.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', claim.id!),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update claim: $e')));
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
          'active': Colors.green,
          'expired': Colors.grey,
          'cancelled': Colors.red,
          'intimated': Colors.blueGrey,
          'surveyed': Colors.blue,
          'approved': Colors.teal,
          'settled': Colors.green,
          'rejected': Colors.red,
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
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text('Insurance & Claims',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Policies'), Tab(text: 'Claims')],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tabs.index == 0 ? _newPolicy() : _newClaim(),
        icon: const Icon(Icons.add),
        label: Text(_tabs.index == 0 ? 'New Policy' : 'New Claim'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    children: [
                      if (_policies.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('No policies yet.',
                              style: GoogleFonts.inter(color: theme.secondaryText)),
                        )
                      else
                        for (final p in _policies) _policyRow(theme, p),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    children: [
                      if (_claims.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('No claims yet.',
                              style: GoogleFonts.inter(color: theme.secondaryText)),
                        )
                      else
                        for (final c in _claims) _claimRow(theme, c),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _policyRow(FlutterFlowTheme theme, InsurancePoliciesRow p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.policyNo ?? '(no policy no)',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  [
                    if ((p.orderId ?? '').isNotEmpty) p.orderId,
                    if ((p.insurerName ?? '').isNotEmpty) p.insurerName,
                  ].whereType<String>().join(' · '),
                  style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_rupees(p.totalPremium),
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
              _statusChip(theme, p.status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _claimRow(FlutterFlowTheme theme, ClaimsRow c) {
    return InkWell(
      onTap: () => _openClaim(c),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.claimNo ?? c.id ?? '(claim)',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    [
                      if ((c.orderId ?? '').isNotEmpty) c.orderId,
                      if ((c.claimType ?? '').isNotEmpty) c.claimType,
                    ].whereType<String>().join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_rupees(c.claimedAmount),
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                _statusChip(theme, c.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
