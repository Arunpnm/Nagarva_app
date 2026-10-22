import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/load_error_state.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';

/// Warehouses / godowns.
///
/// Storage rates are set per CITY (brief §38), and a stay's rate is
/// snapshotted onto its own record (§44) — so this screen deliberately
/// holds no pricing. It is the place a vendor describes the SPACE:
/// where it is, who to call, and how much it holds. Pricing lives with
/// the storage booking, where it can be agreed per customer.
///
/// Occupancy is computed from the CFT of stays currently in the
/// warehouse, not stored on the row — a cached number would drift the
/// moment a stay closed.
class WarehousesPageWidget extends StatefulWidget {
  const WarehousesPageWidget({super.key});

  static String routeName = 'WarehousesPage';
  static String routePath = '/warehouses';

  @override
  State<WarehousesPageWidget> createState() => _WarehousesPageWidgetState();
}

class _WarehousesPageWidgetState extends State<WarehousesPageWidget> {
  List<WarehousesRow> _rows = [];

  /// warehouse_id -> CFT currently stored (stays with no out_date).
  final Map<String, double> _usedCft = {};

  /// warehouse_id -> number of live stays.
  final Map<String, int> _liveStays = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await WarehousesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name', ascending: true),
      );

      // Live occupancy: stays that have gone in and not yet come out.
      final stays = await OrgScope.read(SupaFlow.client
              .from('storage_jobs')
              .select('warehouse_id,total_cft,out_date'))
          .isFilter('out_date', null);

      _usedCft.clear();
      _liveStays.clear();
      for (final s in stays) {
        final wid = s['warehouse_id'] as String?;
        if (wid == null) continue;
        _usedCft[wid] =
            (_usedCft[wid] ?? 0) + (num.tryParse('${s['total_cft']}') ?? 0);
        _liveStays[wid] = (_liveStays[wid] ?? 0) + 1;
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _edit([WarehousesRow? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NgPalette.of(context).s1,
      builder: (_) => _WarehouseFormSheet(existing: existing),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final activeCount = _rows.where((w) => w.active).length;
    final totalCapacity = _rows
        .where((w) => w.active)
        .fold<double>(0, (s, w) => s + (w.capacityCft ?? 0));
    Widget tile(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: c.s1, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: NgFonts.mono(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: c.acc)),
                const SizedBox(height: 3),
                Text(label, style: NgFonts.geist(fontSize: 12, color: c.mute)),
              ],
            ),
          ),
        );
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadErrorState(
                  message: 'Could not load warehouses.\n$_error',
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      NgModuleHeader('Warehouses', actions: [
                        NgPrimaryButton(
                          compact: true,
                          height: 40,
                          icon: Icons.add_rounded,
                          label: 'New warehouse',
                          onPressed: () => _edit(),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        tile('$activeCount', 'Active warehouses'),
                        const SizedBox(width: 8),
                        tile(
                            totalCapacity <= 0
                                ? '—'
                                : functions
                                    .inrFull(totalCapacity)
                                    .replaceFirst('₹', ''),
                            'Total CFT capacity'),
                      ]),
                      const SizedBox(height: 14),
                      if (_rows.isEmpty)
                        NgCard(
                          child: Column(children: [
                            Icon(Icons.warehouse_outlined,
                                size: 32, color: c.faint),
                            const SizedBox(height: 8),
                            Text('No warehouses yet.',
                                style: NgFonts.geist(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.text)),
                            const SizedBox(height: 4),
                            Text(
                              'Add the godown you store customer goods in, '
                              'then you can move an order into it.',
                              textAlign: TextAlign.center,
                              style:
                                  NgFonts.geist(fontSize: 12.5, color: c.mute),
                            ),
                          ]),
                        )
                      else
                        NgCardList(children: [
                          for (final w in _rows) _card(w),
                        ]),
                    ],
                  ),
                ),
    );
  }

  Widget _card(WarehousesRow w) {
    final c = NgPalette.of(context);
    final id = w.id ?? '';
    final used = _usedCft[id] ?? 0;
    final cap = w.capacityCft ?? 0;
    final stays = _liveStays[id] ?? 0;
    // Only meaningful when a capacity was actually entered; otherwise the
    // bar would imply a limit the vendor never set.
    final frac = cap > 0 ? (used / cap).clamp(0.0, 1.0) : null;
    final muted = !w.active;
    return InkWell(
      onTap: () => _edit(w),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(w.name,
                    style: NgFonts.geist(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: muted ? c.mute : c.text)),
              ),
              if (muted) const NgPill('Inactive', status: NgStatus.red),
            ]),
            const SizedBox(height: 3),
            Text(
              [
                if ((w.code ?? '').isNotEmpty) w.code!,
                if ((w.branch ?? '').isNotEmpty) w.branch!,
                if ((w.city ?? '').isNotEmpty) w.city!,
              ].join(' · '),
              style: NgFonts.geist(fontSize: 12.5, color: c.mute),
            ),
            if ((w.address ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(w.address!,
                  style: NgFonts.geist(fontSize: 13, color: c.soft)),
            ],
            const SizedBox(height: 8),
            if (frac != null) ...[
              NgProgressBar(
                  value: frac,
                  color: frac >= 0.9 ? c.red : c.accBtn,
                  height: 5),
              const SizedBox(height: 5),
            ],
            Text(
              cap > 0
                  ? '${used.toStringAsFixed(0)} / ${cap.toStringAsFixed(0)} CFT used · ${(frac! * 100).round()}% · $stays in store'
                  : '${used.toStringAsFixed(0)} CFT in store · $stays ${stays == 1 ? 'stay' : 'stays'}',
              style: NgFonts.mono(fontSize: 12, color: c.mute),
            ),
            if ((w.contactPerson ?? '').isNotEmpty ||
                (w.contactPhone ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.person_outline_rounded, size: 15, color: c.mute),
                const SizedBox(width: 4),
                Text(
                  [
                    if ((w.contactPerson ?? '').isNotEmpty) w.contactPerson!,
                    if ((w.contactPhone ?? '').isNotEmpty) w.contactPhone!,
                  ].join(' · '),
                  style: NgFonts.geist(fontSize: 12.5, color: c.mute),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Add / edit a warehouse.
class _WarehouseFormSheet extends StatefulWidget {
  const _WarehouseFormSheet({this.existing});
  final WarehousesRow? existing;

  @override
  State<_WarehouseFormSheet> createState() => _WarehouseFormSheetState();
}

class _WarehouseFormSheetState extends State<_WarehouseFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _pincode;
  late final TextEditingController _branch;
  late final TextEditingController _capacity;
  late final TextEditingController _contactPerson;
  late final TextEditingController _contactPhone;
  late bool _active;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final w = widget.existing;
    _name = TextEditingController(text: w?.name ?? '');
    _code = TextEditingController(text: w?.code ?? '');
    _address = TextEditingController(text: w?.address ?? '');
    _city = TextEditingController(text: w?.city ?? '');
    _pincode = TextEditingController(text: w?.pincode ?? '');
    _branch = TextEditingController(text: w?.branch ?? '');
    _capacity = TextEditingController(
        text: (w?.capacityCft ?? 0) == 0 ? '' : '${w!.capacityCft!.toInt()}');
    _contactPerson = TextEditingController(text: w?.contactPerson ?? '');
    _contactPhone = TextEditingController(text: w?.contactPhone ?? '');
    _active = w?.active ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _code,
      _address,
      _city,
      _pincode,
      _branch,
      _capacity,
      _contactPerson,
      _contactPhone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the warehouse a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Empty optional fields are written as NULL, never ''.
      //
      // `branch` carries a foreign key to `branches`, and '' is not a
      // branch — so leaving the field blank, which is the ordinary case
      // for an org that has never set branches up, failed the insert
      // outright with a raw 23503 shown to the vendor:
      //
      //   insert or update on table "warehouses" violates foreign key
      //   constraint "warehouses_branch_fk" ... Key is not present in
      //   table "branches"
      //
      // Found creating the first Coimbatore godown, 2 Sept 2026. The
      // other fields have no FK so '' merely stored junk, but an empty
      // string is not "unset" and makes every later "is it filled in?"
      // check answer wrongly, so they are nullified too.
      String? nz(String v) => v.trim().isEmpty ? null : v.trim();

      final data = <String, dynamic>{
        'name': name,
        'code': nz(_code.text),
        'address': nz(_address.text),
        // City drives the storage rate card, so it is worth keeping clean.
        'city': nz(_city.text),
        'pincode': nz(_pincode.text),
        'branch': nz(_branch.text),
        'capacity_cft': double.tryParse(_capacity.text.trim()) ?? 0,
        'contact_person': nz(_contactPerson.text),
        'contact_phone': nz(_contactPhone.text),
        'active': _active,
      };
      final existingId = widget.existing?.id;
      if (existingId == null) {
        await WarehousesTable().insert({...OrgScope.stamp(), ...data});
      } else {
        await WarehousesTable().update(
          data: data,
          matchingRows: (q) => OrgScope.write(q).eq('id', existingId),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          // Branch is free text against an FK, so a typo reads as a
          // Postgres constraint dump. Say what the vendor can actually
          // do about it instead. (The field should be a picker fed by
          // `branches`, as the staff and lead forms already are - that
          // is the real fix and is not done here.)
          _error = '$e'.contains('warehouses_branch_fk')
              ? 'That branch does not exist. Leave Branch empty, or type '
                  'the exact name of a branch you have already created.'
              : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    final isNew = widget.existing == null;
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isNew ? 'New Warehouse' : 'Edit Warehouse',
                style: NgFonts.geist(fontSize: 22, 
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _field(_name, 'Name *'),
            Row(children: [
              Expanded(child: _field(_code, 'Code')),
              const SizedBox(width: 10),
              Expanded(child: _field(_branch, 'Branch')),
            ]),
            _field(_address, 'Address', maxLines: 2),
            Row(children: [
              Expanded(child: _field(_city, 'City')),
              const SizedBox(width: 10),
              Expanded(child: _field(_pincode, 'Pincode')),
            ]),
            _field(_capacity, 'Capacity (CFT)',
                keyboard: TextInputType.number),
            Row(children: [
              Expanded(child: _field(_contactPerson, 'Contact person')),
              const SizedBox(width: 10),
              Expanded(
                  child: _field(_contactPhone, 'Contact phone',
                      keyboard: TextInputType.phone)),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: Text(
                'Inactive godowns stay on past storage records but cannot '
                'take new goods.',
                style: NgFonts.geist(fontSize: 12.5, 
                    color: ng.mute),
              ),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: NgFonts.geist(fontSize: 12.5, color: ng.red)),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving
                      ? 'Saving…'
                      : (isNew ? 'Add Warehouse' : 'Save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
          {int maxLines = 1, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );
}
