import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/order_picker_dialog.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

class TripDetailPageWidget extends StatefulWidget {
  const TripDetailPageWidget({super.key, this.tripId});
  final String? tripId;

  static String routeName = 'TripDetailPage';
  static String routePath = '/trip-detail';

  @override
  State<TripDetailPageWidget> createState() => _TripDetailPageWidgetState();
}

class _TripDetailPageWidgetState extends State<TripDetailPageWidget> {
  bool _loading = true;
  TripsRow? _trip;
  TripPnlViewRow? _pnl;
  List<TripOrdersRow> _tripOrders = [];
  List<TripExpensesRow> _expenses = [];
  List<VendorsRow> _vendors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.tripId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final trips = await TripsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.tripId!),
      );
      _trip = trips.isNotEmpty ? trips.first : null;
      final pnls = await TripPnlViewTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('trip_id', widget.tripId!),
      );
      _pnl = pnls.isNotEmpty ? pnls.first : null;
      _tripOrders = await TripOrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('trip_id', widget.tripId!).order('pickup_seq'),
      );
      _expenses = await TripExpensesTable().queryRows(
        queryFn: (q) =>
            OrgScope.read(q).eq('trip_id', widget.tripId!).order('expense_date', ascending: false),
      );
      _vendors = await VendorsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('active', true).order('name'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load trip: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _rupees(num v) => '₹${v.toStringAsFixed(0)}';

  Future<void> _editTrip() async {
    final t = _trip;
    if (t == null) return;
    final tripNoCtrl = TextEditingController(text: t.tripNo ?? '');
    final vehicleNoCtrl = TextEditingController(text: t.vehicleNo ?? '');
    final driverNameCtrl = TextEditingController(text: t.driverName ?? '');
    final driverPhoneCtrl = TextEditingController(text: t.driverPhone ?? '');
    final fromCtrl = TextEditingController(text: t.fromLoc ?? '');
    final toCtrl = TextEditingController(text: t.toLoc ?? '');
    final kmStartCtrl = TextEditingController(text: t.kmStart?.toString() ?? '');
    final kmEndCtrl = TextEditingController(text: t.kmEnd?.toString() ?? '');
    final fuelCtrl = TextEditingController(text: t.fuelLitres?.toString() ?? '');
    final hireAmountCtrl = TextEditingController(text: t.hireAmount?.toString() ?? '');
    String tripType = t.tripType ?? 'own';
    String status = t.status;
    String? vendorId = t.vendorId;
    DateTime startDate = t.startDate ?? DateTime.now();
    DateTime? endDate = t.endDate;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Edit Trip'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: tripNoCtrl,
                      decoration: const InputDecoration(labelText: 'Trip No')),
                  DropdownButtonFormField<String>(
                    initialValue: tripType,
                    decoration: const InputDecoration(labelText: 'Trip Type'),
                    items: const [
                      DropdownMenuItem(value: 'own', child: Text('Own Vehicle')),
                      DropdownMenuItem(value: 'hired', child: Text('Hired Vehicle')),
                    ],
                    onChanged: (v) => setDialogState(() => tripType = v ?? 'own'),
                  ),
                  if (tripType == 'hired') ...[
                    DropdownButtonFormField<String>(
                      initialValue: vendorId,
                      decoration: const InputDecoration(labelText: 'Vendor'),
                      items: [
                        for (final v in _vendors)
                          DropdownMenuItem(value: v.id, child: Text(v.name)),
                      ],
                      onChanged: (v) => setDialogState(() => vendorId = v),
                    ),
                    TextField(
                        controller: hireAmountCtrl,
                        decoration: const InputDecoration(labelText: 'Hire Amount'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  ],
                  TextField(
                      controller: vehicleNoCtrl,
                      decoration: const InputDecoration(labelText: 'Vehicle No')),
                  TextField(
                      controller: driverNameCtrl,
                      decoration: const InputDecoration(labelText: 'Driver Name')),
                  TextField(
                      controller: driverPhoneCtrl,
                      decoration: const InputDecoration(labelText: 'Driver Phone'),
                      keyboardType: TextInputType.phone),
                  TextField(
                      controller: fromCtrl,
                      decoration: const InputDecoration(labelText: 'From')),
                  TextField(
                      controller: toCtrl,
                      decoration: const InputDecoration(labelText: 'To')),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start Date'),
                    subtitle: Text(DateFormat('d MMM yyyy').format(startDate)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: dialogCtx,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => startDate = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End Date'),
                    subtitle:
                        Text(endDate == null ? '—' : DateFormat('d MMM yyyy').format(endDate!)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: dialogCtx,
                          initialDate: endDate ?? startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => endDate = picked);
                    },
                  ),
                  TextField(
                      controller: kmStartCtrl,
                      decoration: const InputDecoration(labelText: 'Km Start'),
                      keyboardType: TextInputType.number),
                  TextField(
                      controller: kmEndCtrl,
                      decoration: const InputDecoration(labelText: 'Km End'),
                      keyboardType: TextInputType.number),
                  TextField(
                      controller: fuelCtrl,
                      decoration: const InputDecoration(labelText: 'Fuel (litres)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'planned', child: Text('Planned')),
                      DropdownMenuItem(value: 'ongoing', child: Text('Ongoing')),
                      DropdownMenuItem(value: 'completed', child: Text('Completed')),
                      DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v ?? status),
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
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final kmStart = int.tryParse(kmStartCtrl.text.trim());
    final kmEnd = int.tryParse(kmEndCtrl.text.trim());
    try {
      await TripsTable().update(
        data: {
          'trip_no': tripNoCtrl.text.trim().isEmpty ? null : tripNoCtrl.text.trim(),
          'trip_type': tripType,
          'is_hired': tripType == 'hired',
          'vendor_id': tripType == 'hired' ? vendorId : null,
          'hire_amount': tripType == 'hired' ? double.tryParse(hireAmountCtrl.text.trim()) : null,
          'vehicle_no': vehicleNoCtrl.text.trim().isEmpty ? null : vehicleNoCtrl.text.trim(),
          'driver_name': driverNameCtrl.text.trim().isEmpty ? null : driverNameCtrl.text.trim(),
          'driver_phone':
              driverPhoneCtrl.text.trim().isEmpty ? null : driverPhoneCtrl.text.trim(),
          'from_loc': fromCtrl.text.trim().isEmpty ? null : fromCtrl.text.trim(),
          'to_loc': toCtrl.text.trim().isEmpty ? null : toCtrl.text.trim(),
          'start_date': startDate.toIso8601String().split('T').first,
          'end_date': endDate?.toIso8601String().split('T').first,
          'km_start': kmStart,
          'km_end': kmEnd,
          'total_km': (kmStart != null && kmEnd != null && kmEnd >= kmStart)
              ? kmEnd - kmStart
              : null,
          'fuel_litres': double.tryParse(fuelCtrl.text.trim()),
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.tripId!),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _addOrderToTrip() async {
    final order = await OrderPickerDialog.show(context);
    if (order == null || !mounted) return;
    final cftCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final pctCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Add Order — ${order.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: cftCtrl,
                decoration: const InputDecoration(labelText: 'CFT Share'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            TextField(
                controller: weightCtrl,
                decoration: const InputDecoration(labelText: 'Weight Share (kg)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            TextField(
                controller: pctCtrl,
                decoration: const InputDecoration(labelText: 'Allocation %'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            TextField(
                controller: costCtrl,
                decoration: const InputDecoration(labelText: 'Allocated Cost'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await TripOrdersTable().insert({
        ...OrgScope.stamp(),
        'trip_id': widget.tripId,
        'order_id': order.id,
        'pickup_seq': _tripOrders.length + 1,
        'cft_share': double.tryParse(cftCtrl.text.trim()),
        'weight_share_kg': double.tryParse(weightCtrl.text.trim()),
        'allocation_pct': double.tryParse(pctCtrl.text.trim()),
        'allocated_cost': double.tryParse(costCtrl.text.trim()),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add order: $e')));
      }
    }
  }

  Future<void> _removeTripOrder(TripOrdersRow to) async {
    if (to.id == null) return;
    try {
      await SupaFlow.client.from('trip_orders').delete().eq('id', to.id!);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not remove: $e')));
      }
    }
  }

  Future<void> _addExpense() async {
    final amountCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String expenseType = 'fuel';
    String paidBy = 'driver';
    DateTime expenseDate = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Add Trip Expense'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: expenseType,
                    decoration: const InputDecoration(labelText: 'Expense Type'),
                    items: const [
                      DropdownMenuItem(value: 'fuel', child: Text('Fuel')),
                      DropdownMenuItem(value: 'toll', child: Text('Toll')),
                      DropdownMenuItem(value: 'driver_batta', child: Text('Driver Batta')),
                      DropdownMenuItem(value: 'loading', child: Text('Loading')),
                      DropdownMenuItem(value: 'unloading', child: Text('Unloading')),
                      DropdownMenuItem(value: 'parking', child: Text('Parking')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setDialogState(() => expenseType = v ?? 'fuel'),
                  ),
                  TextField(
                      controller: amountCtrl,
                      decoration: const InputDecoration(labelText: 'Amount'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(labelText: 'Location')),
                  DropdownButtonFormField<String>(
                    initialValue: paidBy,
                    decoration: const InputDecoration(labelText: 'Paid By'),
                    items: const [
                      DropdownMenuItem(value: 'driver', child: Text('Driver')),
                      DropdownMenuItem(value: 'office', child: Text('Office')),
                    ],
                    onChanged: (v) => setDialogState(() => paidBy = v ?? paidBy),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date'),
                    subtitle: Text(DateFormat('d MMM yyyy').format(expenseDate)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: dialogCtx,
                          initialDate: expenseDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => expenseDate = picked);
                    },
                  ),
                  TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(labelText: 'Note')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: amountCtrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await TripExpensesTable().insert({
        ...OrgScope.stamp(),
        'trip_id': widget.tripId,
        'expense_type': expenseType,
        'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
        if (locationCtrl.text.trim().isNotEmpty) 'location': locationCtrl.text.trim(),
        'paid_by': paidBy,
        'expense_date': expenseDate.toIso8601String().split('T').first,
        if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add expense: $e')));
      }
    }
  }

  Future<void> _removeExpense(TripExpensesRow e) async {
    if (e.id == null) return;
    try {
      await SupaFlow.client.from('trip_expenses').delete().eq('id', e.id!);
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not remove: $err')));
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

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final t = _trip;
    final pnl = _pnl;
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text(t?.tripNo ?? 'Trip',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (t != null)
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _editTrip),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : t == null
              ? const Center(child: Text('Trip not found.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (pnl != null) ...[
                      Row(
                        children: [
                          Expanded(child: _kpiCard(theme, 'Revenue', _rupees(pnl.grossRevenue))),
                          const SizedBox(width: 8),
                          Expanded(child: _kpiCard(theme, 'Net Profit', _rupees(pnl.netProfit))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                              child: _kpiCard(theme, 'Expenses',
                                  _rupees(pnl.tripExpenses + pnl.hireAmount))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _kpiCard(theme, 'Cost / Km', _rupees(pnl.costPerKm))),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: theme.secondaryBackground, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv('Type', t.isHired ? 'Hired' : 'Own'),
                          if ((t.vehicleNo ?? '').isNotEmpty) _kv('Vehicle', t.vehicleNo!),
                          if ((t.driverName ?? '').isNotEmpty) _kv('Driver', t.driverName!),
                          _kv('Route', '${t.fromLoc ?? '—'} → ${t.toLoc ?? '—'}'),
                          if (t.totalKm != null) _kv('Total Km', '${t.totalKm}'),
                          if (t.isHired && t.hireAmount != null)
                            _kv('Hire Amount', _rupees(t.hireAmount!)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Orders on this Trip',
                            style: GoogleFonts.interTight(fontSize: 14, fontWeight: FontWeight.w700)),
                        TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add'),
                            onPressed: _addOrderToTrip),
                      ],
                    ),
                    if (_tripOrders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('No orders added yet.',
                            style: GoogleFonts.inter(fontSize: 12, color: theme.secondaryText)),
                      )
                    else
                      for (final to in _tripOrders) _tripOrderRow(theme, to),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Trip Expenses',
                            style: GoogleFonts.interTight(fontSize: 14, fontWeight: FontWeight.w700)),
                        TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add'),
                            onPressed: _addExpense),
                      ],
                    ),
                    if (_expenses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('No expenses logged yet.',
                            style: GoogleFonts.inter(fontSize: 12, color: theme.secondaryText)),
                      )
                    else
                      for (final e in _expenses) _expenseRow(theme, e),
                  ],
                ),
    );
  }

  Widget _kpiCard(FlutterFlowTheme theme, String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: theme.secondaryText)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.interTight(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _tripOrderRow(FlutterFlowTheme theme, TripOrdersRow to) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(to.orderId ?? '—',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  Text(
                    [
                      if (to.cftShare != null) '${to.cftShare} CFT',
                      if (to.allocationPct != null) '${to.allocationPct}%',
                      if (to.allocatedCost != null) _rupees(to.allocatedCost!),
                    ].join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _removeTripOrder(to)),
          ],
        ),
      );

  Widget _expenseRow(FlutterFlowTheme theme, TripExpensesRow e) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.expenseType ?? '—',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  Text(
                    [
                      if (e.expenseDate != null) DateFormat('d MMM').format(e.expenseDate!),
                      if ((e.location ?? '').isNotEmpty) e.location,
                    ].whereType<String>().join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            Text(_rupees(e.amount), style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
            IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _removeExpense(e)),
          ],
        ),
      );
}
