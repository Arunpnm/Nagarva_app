import '/flutter_flow/ng_tokens.dart';
import '/components/ng_widgets.dart';
import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

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
    final ng = NgPalette.of(context);
    return Scaffold(
      backgroundColor: NgPalette.of(context).bg,
      appBar: NgSimpleBar(title: _card?.name ?? 'Rate card'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: NgTabBar(
                  controller: _tabs,
                  scrollable: true,
                  labels: const [
                    'Charges',
                    'Distance / CFT rules',
                    'Floor charges',
                    'Multipliers',
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(controller: _tabs, children: [
                  _chargesTab(ng),
                  _rulesTab(ng),
                  _floorsTab(ng),
                  _multipliersTab(ng),
                ]),
              ),
            ]),
    );
  }

  /// One tab: the rows in a hairline card, then an "Add …" button.
  Widget _tab(NgPalette ng,
          {required List<Widget> rows,
          required String empty,
          required String addLabel,
          required VoidCallback onAdd}) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          NgRowsCard(rows: rows, empty: empty),
          const SizedBox(height: 12),
          NgSecondaryButton(
            icon: Icons.add_rounded,
            iconColor: ng.acc,
            label: addLabel,
            height: 46,
            onPressed: onAdd,
          ),
        ],
      );

  Widget _row(NgPalette ng,
          {required String title,
          required String subtitle,
          String? value,
          VoidCallback? onTap,
          required VoidCallback onDelete}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: NgFonts.geist(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: ng.text)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: NgFonts.geist(fontSize: 12.5, color: ng.mute)),
                  ],
                ),
              ),
              if (value != null)
                Text(value,
                    style: NgFonts.mono(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ng.text)),
              IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 19, color: ng.mute),
                  onPressed: onDelete),
            ],
          ),
        ),
      );

  Widget _chargesTab(NgPalette ng) => _tab(ng,
      rows: [
        for (final c in _charges)
          _row(ng,
              title: c.label?.isNotEmpty == true ? c.label! : c.chargeKey,
              subtitle: '${c.unit} · ${c.isOptional ? "optional" : "required"}',
              value: _rupees(c.rate),
              onDelete: () => _deleteCharge(c)),
      ],
      empty: 'No charges on this card yet.',
      addLabel: 'Add charge',
      onAdd: _addCharge);

  Widget _rulesTab(NgPalette ng) => _tab(ng,
      rows: [
        for (final r in _rules)
          _row(ng,
              onTap: () => _editRule(r),
              title:
                  '${r.minKm}–${r.maxKm?.toStringAsFixed(0) ?? '∞'} km · ${r.minCft}–${r.maxCft?.toStringAsFixed(0) ?? '∞'} CFT',
              subtitle:
                  'Base ${_rupees(r.baseAmount)} + ${_rupees(r.perKmRate)}/km + ${_rupees(r.perCftRate)}/CFT',
              onDelete: () => _deleteRule(r)),
      ],
      empty: 'No distance or CFT rules yet.',
      addLabel: 'Add rule',
      onAdd: _addRule);

  Widget _floorsTab(NgPalette ng) => _tab(ng,
      rows: [
        for (final f in _floors)
          _row(ng,
              onTap: () => _editFloorCharge(f),
              title: 'Floor ${f.floorFrom}–${f.floorTo}',
              subtitle: f.hasLift ? 'With lift' : 'No lift',
              value: _rupees(f.amount),
              onDelete: () => _deleteFloorCharge(f)),
      ],
      empty: 'No floor charges yet.',
      addLabel: 'Add floor charge',
      onAdd: _addFloorCharge);

  Widget _multipliersTab(NgPalette ng) => _tab(ng,
      rows: [
        for (final m in _multipliers)
          _row(ng,
              title: m.name?.isNotEmpty == true ? m.name! : 'Multiplier',
              subtitle: 'Applies to ${m.appliesTo}',
              value: '${m.multiplierPct}%',
              onDelete: () => _deleteMultiplier(m)),
      ],
      empty: 'No multipliers yet.',
      addLabel: 'Add multiplier',
      onAdd: _addMultiplier);
}
