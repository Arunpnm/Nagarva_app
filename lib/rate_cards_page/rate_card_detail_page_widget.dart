import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';

class RateCardDetailPageWidget extends StatefulWidget {
  const RateCardDetailPageWidget({super.key, this.cardId});
  final String? cardId;

  static String routeName = 'RateCardDetailPage';
  static String routePath = '/rate-card-detail';

  @override
  State<RateCardDetailPageWidget> createState() =>
      _RateCardDetailPageWidgetState();
}

class _RateCardDetailPageWidgetState extends State<RateCardDetailPageWidget>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool _loading = true;
  RateCardsRow? _card;
  List<RateCardChargesRow> _charges = [];
  List<RateCardRulesRow> _rules = [];
  List<RateCardFloorChargesRow> _floors = [];
  List<RateCardMultipliersRow> _multipliers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.cardId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final cards = await RateCardsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.cardId!),
      );
      _card = cards.isNotEmpty ? cards.first : null;
      _charges = await RateCardChargesTable().queryRows(
        queryFn: (q) =>
            OrgScope.read(q).eq('card_id', widget.cardId!).order('sort_order'),
      );
      _rules = await RateCardRulesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('card_id', widget.cardId!),
      );
      _floors = await RateCardFloorChargesTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eq('card_id', widget.cardId!)
            .order('floor_from'),
      );
      _multipliers = await RateCardMultipliersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('card_id', widget.cardId!),
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

  Future<void> _addCharge() async {
    final keyCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Charge'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(labelText: 'Charge Key'),
              autofocus: true),
          TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Label')),
          TextField(
              controller: rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Rate (₹)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (result != true || keyCtrl.text.trim().isEmpty) return;
    try {
      await RateCardChargesTable().insert({
        ...OrgScope.stamp(),
        'card_id': widget.cardId,
        'charge_key': keyCtrl.text.trim(),
        'label': labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim(),
        'rate': double.tryParse(rateCtrl.text.trim()) ?? 0,
        'sort_order': _charges.length,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }

  Future<void> _deleteCharge(RateCardChargesRow c) async {
    if (c.id == null) return;
    await RateCardChargesTable()
        .delete(matchingRows: (q) => OrgScope.write(q).eq('id', c.id!));
    _load();
  }

  Future<void> _addRule() async {
    try {
      await RateCardRulesTable().insert({
        ...OrgScope.stamp(),
        'card_id': widget.cardId,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }

  Future<void> _editRule(RateCardRulesRow r) async {
    final minKmCtrl = TextEditingController(text: r.minKm.toStringAsFixed(0));
    final maxKmCtrl = TextEditingController(text: r.maxKm?.toStringAsFixed(0) ?? '');
    final baseCtrl = TextEditingController(text: r.baseAmount.toStringAsFixed(0));
    final perKmCtrl = TextEditingController(text: r.perKmRate.toStringAsFixed(0));
    final perCftCtrl = TextEditingController(text: r.perCftRate.toStringAsFixed(0));
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Rule'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: minKmCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Min KM')),
          TextField(
              controller: maxKmCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Max KM (blank = no limit)')),
          TextField(
              controller: baseCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Base Amount (₹)')),
          TextField(
              controller: perKmCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Per KM Rate (₹)')),
          TextField(
              controller: perCftCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Per CFT Rate (₹)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != true || r.id == null) return;
    try {
      await RateCardRulesTable().update(
        data: {
          'min_km': double.tryParse(minKmCtrl.text.trim()) ?? 0,
          'max_km': double.tryParse(maxKmCtrl.text.trim()),
          'base_amount': double.tryParse(baseCtrl.text.trim()) ?? 0,
          'per_km_rate': double.tryParse(perKmCtrl.text.trim()) ?? 0,
          'per_cft_rate': double.tryParse(perCftCtrl.text.trim()) ?? 0,
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', r.id!),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _deleteRule(RateCardRulesRow r) async {
    if (r.id == null) return;
    await RateCardRulesTable()
        .delete(matchingRows: (q) => OrgScope.write(q).eq('id', r.id!));
    _load();
  }

  Future<void> _addFloorCharge() async {
    try {
      await RateCardFloorChargesTable().insert({
        ...OrgScope.stamp(),
        'card_id': widget.cardId,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }

  Future<void> _editFloorCharge(RateCardFloorChargesRow f) async {
    final fromCtrl = TextEditingController(text: '${f.floorFrom}');
    final toCtrl = TextEditingController(text: '${f.floorTo}');
    final amountCtrl = TextEditingController(text: f.amount.toStringAsFixed(0));
    var hasLift = f.hasLift;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Floor Charge'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: fromCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Floor From')),
            TextField(
                controller: toCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Floor To')),
            TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (₹)')),
            CheckboxListTile(
              value: hasLift,
              onChanged: (v) => setDialogState(() => hasLift = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Lift Available'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result != true || f.id == null) return;
    try {
      await RateCardFloorChargesTable().update(
        data: {
          'floor_from': int.tryParse(fromCtrl.text.trim()) ?? 0,
          'floor_to': int.tryParse(toCtrl.text.trim()) ?? 0,
          'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
          'has_lift': hasLift,
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', f.id!),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _deleteFloorCharge(RateCardFloorChargesRow f) async {
    if (f.id == null) return;
    await RateCardFloorChargesTable()
        .delete(matchingRows: (q) => OrgScope.write(q).eq('id', f.id!));
    _load();
  }

  Future<void> _addMultiplier() async {
    final nameCtrl = TextEditingController();
    final pctCtrl = TextEditingController(text: '100');
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Multiplier'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true),
          TextField(
              controller: pctCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Multiplier %')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (result != true) return;
    try {
      await RateCardMultipliersTable().insert({
        ...OrgScope.stamp(),
        'card_id': widget.cardId,
        'name': nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        'multiplier_pct': double.tryParse(pctCtrl.text.trim()) ?? 100,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }

  Future<void> _deleteMultiplier(RateCardMultipliersRow m) async {
    if (m.id == null) return;
    await RateCardMultipliersTable()
        .delete(matchingRows: (q) => OrgScope.write(q).eq('id', m.id!));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text(_card?.name ?? 'Rate Card'),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(controller: _tabs, isScrollable: true, tabs: const [
          Tab(text: 'Charges'),
          Tab(text: 'Distance/CFT Rules'),
          Tab(text: 'Floor Charges'),
          Tab(text: 'Multipliers'),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabs, children: [
              _chargesTab(theme),
              _rulesTab(theme),
              _floorsTab(theme),
              _multipliersTab(theme),
            ]),
    );
  }

  Widget _chargesTab(FlutterFlowTheme theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final c in _charges)
          ListTile(
            title: Text(c.label?.isNotEmpty == true ? c.label! : c.chargeKey),
            subtitle: Text('${c.unit} · ${c.isOptional ? "optional" : "required"}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_rupees(c.rate)),
                IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteCharge(c)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _addCharge,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Charge')),
      ],
    );
  }

  Widget _rulesTab(FlutterFlowTheme theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final r in _rules)
          ListTile(
            onTap: () => _editRule(r),
            title: Text(
                '${r.minKm}-${r.maxKm?.toStringAsFixed(0) ?? '∞'} km · ${r.minCft}-${r.maxCft?.toStringAsFixed(0) ?? '∞'} cft'),
            subtitle: Text(
                'Base ${_rupees(r.baseAmount)} + ${_rupees(r.perKmRate)}/km + ${_rupees(r.perCftRate)}/cft'),
            trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _deleteRule(r)),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _addRule,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Rule')),
      ],
    );
  }

  Widget _floorsTab(FlutterFlowTheme theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final f in _floors)
          ListTile(
            onTap: () => _editFloorCharge(f),
            title: Text('Floor ${f.floorFrom}-${f.floorTo}'),
            subtitle: Text(f.hasLift ? 'With lift' : 'No lift'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_rupees(f.amount)),
                IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteFloorCharge(f)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _addFloorCharge,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Floor Charge')),
      ],
    );
  }

  Widget _multipliersTab(FlutterFlowTheme theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final m in _multipliers)
          ListTile(
            title: Text(m.name?.isNotEmpty == true ? m.name! : 'Multiplier'),
            subtitle: Text('Applies to ${m.appliesTo}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${m.multiplierPct}%'),
                IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteMultiplier(m)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _addMultiplier,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Multiplier')),
      ],
    );
  }
}
