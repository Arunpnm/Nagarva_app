import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/backend/edge_function_errors.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';

/// Super Admin › Marketplace › New Nagarva job (14 Nov 2026, Arun: "we
/// don't have enough option to save all details. Full address floor item
/// list same like customer app ... then create a order and assign a
/// vendor for that order or broadcast").
///
/// The same details the customer app collects, priced by the same
/// function (`mkt_quote`), so a job typed in here and a customer's own
/// booking come out at the same price. The admin may change the price,
/// but only with a reason, and the reason is kept on the job's history.
///
/// [tryOnly]: the "Try a price" tool on the Prices tab - the same form
/// with no customer and no save, to check what customers will be shown.
class NagarvaJobForm extends StatefulWidget {
  const NagarvaJobForm({
    super.key,
    required this.rules,
    required this.vendors,
    required this.orgNames,
    this.tryOnly = false,
    this.debugCities,
    this.debugCatalogue,
  });

  /// Tests only: skip the database and use these.
  final List<Map<String, dynamic>>? debugCities;
  final List<Map<String, dynamic>>? debugCatalogue;

  /// mkt_city_rules rows (the '*' row is the default for every city).
  final List<Map<String, dynamic>> rules;
  final List<Map<String, dynamic>> vendors;
  final Map<String, String> orgNames;
  final bool tryOnly;

  @override
  State<NagarvaJobForm> createState() => _NagarvaJobFormState();
}

class _Line {
  _Line(this.item);
  final Map<String, dynamic> item;
  int variant = 0;
  int qty = 0;
  final Set<String> services = {};

  List<dynamic> get variants => (item['variants'] as List?) ?? const [];
  List<dynamic> get serviceList => (item['services'] as List?) ?? const [];
  double get cft {
    if (variants.isEmpty) return 0;
    final v = variants[variant.clamp(0, variants.length - 1)];
    return ((v['cft'] as num?) ?? 0).toDouble();
  }
}

class _NagarvaJobFormState extends State<NagarvaJobForm> {
  static const _catNames = {
    'bed': 'Bedroom', 'liv': 'Living', 'din': 'Dining & kitchen',
    'app': 'Appliances', 'ele': 'Electronics', 'off': 'Office',
    'veh': 'Vehicles', 'oth': 'Others',
  };
  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  SupabaseClient get _db => SupaFlow.client;

  bool _loading = true;
  List<Map<String, dynamic>> _cities = const [];
  final List<_Line> _lines = [];
  String? _openCat;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pickupAddr = TextEditingController();
  final _dropAddr = TextEditingController();
  final _km = TextEditingController();
  final _slot = TextEditingController();
  final _price = TextEditingController();
  final _reason = TextEditingController();
  final _commission = TextEditingController();

  bool _intercity = false;
  String? _from;
  String? _to;
  int _pickupFloor = 0;
  bool _pickupLift = false;
  int _dropFloor = 0;
  bool _dropLift = false;
  String _package = 'standard';
  bool _cover = false;
  bool _unpack = false;
  int _storage = 0;
  DateTime _date = DateTime.now().add(const Duration(days: 2));

  Map<String, dynamic>? _quote;
  bool _pricing = false;
  bool _override = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (widget.debugCities != null) {
      setState(() {
        _cities = widget.debugCities!;
        for (final it in widget.debugCatalogue ?? const []) {
          _lines.add(_Line(Map<String, dynamic>.from(it)));
        }
        _from = _cities.firstOrNull?['city'] as String?;
        _loading = false;
      });
      _syncCommission();
      return;
    }
    try {
      final r = await Future.wait([
        _db.from('mkt_cities').select().eq('active', true).order('city'),
        _db.from('mkt_catalogue').select().eq('active', true).order('sort'),
      ]);
      if (!mounted) return;
      setState(() {
        _cities = List<Map<String, dynamic>>.from(r[0]);
        for (final it in r[1]) {
          _lines.add(_Line(Map<String, dynamic>.from(it)));
        }
        _from = _cities.firstOrNull?['city'] as String?;
        _loading = false;
      });
      _syncCommission();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _toast('Could not load: ${friendlyError(e)}');
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  Map<String, dynamic> _rulesFor(String? city) =>
      widget.rules.where((r) => r['city'] == city).firstOrNull ??
      widget.rules.where((r) => r['city'] == '*').firstOrNull ??
      const {};

  void _syncCommission() {
    final pct = _rulesFor(_from)['commission_pct'];
    _commission.text = pct == null ? '' : '$pct';
  }

  /// Within a city, mkt_quote measures the distance between two points.
  /// The admin types the road distance instead of dropping pins, so the
  /// points are made from the city centre and that distance (the server
  /// multiplies straight-line km by 1.25 for roads; this divides it back).
  ({Map<String, dynamic> pickup, Map<String, dynamic> drop})? _points() {
    final km = double.tryParse(_km.text.trim());
    final c = _cities.where((x) => x['city'] == _from).firstOrNull;
    if (km == null || km <= 0 || c == null) return null;
    final lat = (c['lat'] as num).toDouble();
    final lng = (c['lng'] as num).toDouble();
    final dLat = (km / 1.25) / 111.0;
    return (
      pickup: {'lat': lat, 'lng': lng},
      drop: {'lat': lat + dLat, 'lng': lng},
    );
  }

  Map<String, dynamic> _input() {
    final pts = _intercity ? null : _points();
    return {
      'from_city': _from,
      'to_city': _intercity ? _to : _from,
      'package': _package,
      'lines': [
        for (final l in _lines.where((l) => l.qty > 0))
          {
            'key': l.item['key'],
            'variant': l.variant,
            'qty': l.qty,
            'services': l.services.toList(),
          }
      ],
      'pickup_floor': _pickupFloor,
      'pickup_lift': _pickupLift,
      'drop_floor': _dropFloor,
      'drop_lift': _dropLift,
      if (pts != null) 'pickup': pts.pickup,
      if (pts != null) 'drop': pts.drop,
      'addons': {'cover': _cover, 'unpack': _unpack, 'storage_months': _storage},
    };
  }

  String _problem(Map<String, dynamic> q) => switch (q['reason']) {
        'no_price' => 'No price set yet for ${q['detail']}. Set it in Prices.',
        'city_not_served' => 'That city is not switched on.',
        'no_items' => 'Add at least one item.',
        'no_address' => 'Type the road distance between the two addresses.',
        'outside_city' => 'That distance is outside the city.',
        'too_far' => 'Too far for a within-city move (${q['detail']}).',
        'bad_package' => 'Pick a package.',
        _ => 'Could not price this move (${q['reason']}).',
      };

  Future<void> _getPrice() async {
    if (_from == null || (_intercity && _to == null)) {
      return _toast('Pick the cities first.');
    }
    setState(() => _pricing = true);
    try {
      final r = await _db.rpc('mkt_quote', params: {'p': _input()});
      if (!mounted) return;
      setState(() => _quote = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      _toast('Could not get a price: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _pricing = false);
    }
  }

  void _changed() {
    if (_quote != null) setState(() => _quote = null);
  }

  double get _cft =>
      _lines.where((l) => l.qty > 0 && l.item['cat'] != 'veh').fold(
          0.0, (s, l) => s + l.qty * l.cft);

  String _addrWithFloor(String addr, int floor, bool lift) {
    final f = floor == 0
        ? 'Ground floor'
        : 'Floor $floor${lift ? ', lift' : ', no lift'}';
    return [addr.trim(), f].where((x) => x.isNotEmpty).join(' · ');
  }

  Future<void> _save({required bool assign}) async {
    final q = _quote;
    if (q == null || q['ok'] != true) return _toast('Get the price first.');
    if (_name.text.trim().isEmpty || _phone.text.trim().length < 10) {
      return _toast('Customer name and phone are needed.');
    }
    if (_pickupAddr.text.trim().isEmpty || _dropAddr.text.trim().isEmpty) {
      return _toast('Both addresses are needed.');
    }
    final listTotal = (q['total'] as num).toDouble();
    double total = listTotal;
    if (_override) {
      final v = double.tryParse(_price.text.trim());
      if (v == null || v <= 0) return _toast('Type the new price.');
      if (_reason.text.trim().length < 4) {
        return _toast('Say why the price is changed.');
      }
      total = v;
    }
    final commission = double.tryParse(_commission.text.trim());
    if (commission == null || commission < 0 || commission > 50) {
      return _toast('Commission must be between 0 and 50%.');
    }

    String? vendor;
    if (assign) {
      vendor = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Assign to'),
          children: [
            for (final v in widget.vendors.where((v) => v['suspended'] != true))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, '${v['org_id']}'),
                child: Text(
                    '${widget.orgNames['${v['org_id']}'] ?? v['org_id']} · ${v['home_city'] ?? '—'}'),
              ),
          ],
        ),
      );
      if (vendor == null) return;
    }

    final r = _rulesFor(_from);
    final gst = _override
        ? double.parse((total * 18 / 118).toStringAsFixed(2))
        : ((q['gst'] as num?) ?? total * 18 / 118).toDouble();
    final advPct = ((r['advance_pct'] as num?) ?? 0).toDouble();
    final advMin = ((r['advance_min'] as num?) ?? 0).toDouble();
    final advance = _override
        ? min(total, max(advMin, (total * advPct / 100).roundToDouble()))
        : ((q['advance'] as num?) ?? 0).toDouble();
    final rnd = Random.secure();
    final otp = List.generate(4, (_) => rnd.nextInt(10)).join();
    final jobNo =
        'NG-${DateFormat('yyMMdd').format(DateTime.now())}-${rnd.nextInt(9000) + 1000}';
    final now = DateTime.now().toUtc().toIso8601String();

    setState(() => _saving = true);
    try {
      final row = await _db.from('mkt_jobs').insert({
        'job_no': jobNo,
        'pickup_city': _from,
        'drop_city': _intercity ? _to : _from,
        'package': _package,
        'move_date': _date.toIso8601String().split('T').first,
        if (_slot.text.trim().isNotEmpty) 'slot': _slot.text.trim(),
        'cft': (q['cft'] as num?) ?? _cft,
        'items': [
          for (final l in _lines.where((l) => l.qty > 0))
            {
              'key': l.item['key'],
              'name': l.item['name'],
              'cat': l.item['cat'],
              'variant': l.variants.isEmpty
                  ? null
                  : l.variants[l.variant]['name'],
              'cft': l.cft,
              'qty': l.qty,
              'services': [
                for (final s in l.serviceList)
                  if (l.services.contains(s['code'])) s['label'] ?? s['code']
              ],
            }
        ],
        'total_inr': total,
        'gst_inr': gst,
        'advance_inr': advance,
        'commission_pct': commission,
        'customer_name': _name.text.trim(),
        'customer_phone': _phone.text.trim(),
        'pickup_address':
            _addrWithFloor(_pickupAddr.text, _pickupFloor, _pickupLift),
        'drop_address': _addrWithFloor(_dropAddr.text, _dropFloor, _dropLift),
        'delivery_otp': otp,
        if (vendor != null) ...{
          'status': 'accepted',
          'accepted_org_id': vendor,
          'accepted_at': now,
        },
      }).select('id').single();
      final addons = [
        if (_cover) 'damage cover',
        if (_unpack) 'unpacking',
        if (_storage > 0) 'storage $_storage month(s)',
      ];
      await _db.from('mkt_job_events').insert({
        'job_id': row['id'],
        'kind': 'created_by_admin',
        'actor': _db.auth.currentUser?.id,
        'note': [
          'Price from rates ${_money.format(listTotal)}',
          if (_override)
            'changed to ${_money.format(total)}: ${_reason.text.trim()}',
          if (addons.isNotEmpty) 'Add-ons: ${addons.join(', ')}',
          if (!_intercity && _km.text.trim().isNotEmpty) '${_km.text.trim()} km',
        ].join(' · '),
      });
      await _db.from('mkt_job_events').insert({
        'job_id': row['id'],
        'kind': vendor != null ? 'assigned_by_admin' : 'broadcast',
        if (vendor != null) 'org_id': vendor,
        'actor': _db.auth.currentUser?.id,
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(vendor != null ? 'Job assigned' : 'Job broadcast'),
          content: Text(
              '$jobNo${vendor != null ? ' is with ${widget.orgNames[vendor] ?? 'the vendor'}' : ' is out to vendors'}.\n\n'
              'Delivery code: $otp\nGive it to the customer; the vendor needs it at delivery.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('Could not save: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- UI ----------------------------------------------------------------

  Widget _floorRow(String label, int floor, bool lift,
      ValueChanged<int> onFloor, ValueChanged<bool> onLift) {
    final c = NgPalette.of(context);
    return Row(children: [
      Expanded(
          child: Text(label, style: NgFonts.geist(fontSize: 13.5, color: c.text))),
      IconButton(
          onPressed: floor > 0 ? () => onFloor(floor - 1) : null,
          icon: const Icon(Icons.remove_rounded)),
      Text(floor == 0 ? 'Ground' : 'Floor $floor',
          style: NgFonts.mono(fontSize: 13, color: c.text)),
      IconButton(
          onPressed: floor < 40 ? () => onFloor(floor + 1) : null,
          icon: const Icon(Icons.add_rounded)),
      const SizedBox(width: 4),
      Text('Lift', style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
      Switch.adaptive(value: lift, onChanged: onLift),
    ]);
  }

  Widget _section(String title, List<Widget> children) {
    final c = NgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NgCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: NgFonts.geist(
                    fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _cityPicker(String label, String? value, ValueChanged<String?> on) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final c in _cities)
            DropdownMenuItem(value: '${c['city']}', child: Text('${c['city']}')),
        ],
        onChanged: on,
      );

  Widget _itemsSection() {
    final c = NgPalette.of(context);
    final cats = <String>[];
    for (final l in _lines) {
      final cat = '${l.item['cat']}';
      if (!cats.contains(cat)) cats.add(cat);
    }
    final picked = _lines.where((l) => l.qty > 0).toList();
    return _section('Items · ${_cft.round()} CFT', [
      if (picked.isNotEmpty) ...[
        Text(
            picked
                .map((l) => '${l.item['name']}${l.variants.length > 1 ? ' (${l.variants[l.variant]['name']})' : ''} × ${l.qty}')
                .join(', '),
            style: NgFonts.geist(fontSize: 12.5, color: c.acc)),
        const SizedBox(height: 8),
      ],
      for (final cat in cats) ...[
        InkWell(
          onTap: () => setState(() => _openCat = _openCat == cat ? null : cat),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(
                  child: Text(_catNames[cat] ?? cat,
                      style: NgFonts.geist(
                          fontSize: 14, fontWeight: FontWeight.w600, color: c.text))),
              Text(
                  '${_lines.where((l) => l.item['cat'] == cat && l.qty > 0).fold<int>(0, (s, l) => s + l.qty)}',
                  style: NgFonts.mono(fontSize: 12.5, color: c.mute)),
              Icon(_openCat == cat
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded),
            ]),
          ),
        ),
        if (_openCat == cat)
          for (final l in _lines.where((l) => l.item['cat'] == cat))
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text('${l.item['name']}',
                          style: NgFonts.geist(fontSize: 13.5, color: c.text)),
                    ),
                    if (l.variants.length > 1)
                      DropdownButton<int>(
                        value: l.variant,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (var i = 0; i < l.variants.length; i++)
                            DropdownMenuItem(
                                value: i,
                                child: Text(
                                    cat == 'veh'
                                        ? '${l.variants[i]['name']}'
                                        : '${l.variants[i]['name']} · ${((l.variants[i]['cft'] as num?) ?? 0).round()}',
                                    style: const TextStyle(fontSize: 12.5))),
                        ],
                        onChanged: (v) => setState(() {
                          l.variant = v ?? 0;
                          _changed();
                        }),
                      ),
                    IconButton(
                        onPressed: l.qty > 0
                            ? () => setState(() {
                                  l.qty--;
                                  _changed();
                                })
                            : null,
                        icon: const Icon(Icons.remove_rounded)),
                    SizedBox(
                        width: 22,
                        child: Text('${l.qty}',
                            textAlign: TextAlign.center,
                            style: NgFonts.mono(fontSize: 14, color: c.text))),
                    IconButton(
                        onPressed: () => setState(() {
                              l.qty++;
                              _changed();
                            }),
                        icon: const Icon(Icons.add_rounded)),
                  ]),
                  if (l.qty > 0 && l.serviceList.isNotEmpty)
                    Wrap(spacing: 6, children: [
                      for (final s in l.serviceList)
                        FilterChip(
                          label: Text('${s['label'] ?? s['code']}',
                              style: const TextStyle(fontSize: 12)),
                          selected: l.services.contains(s['code']),
                          onSelected: (on) => setState(() {
                            on
                                ? l.services.add('${s['code']}')
                                : l.services.remove('${s['code']}');
                            _changed();
                          }),
                        ),
                    ]),
                ],
              ),
            ),
      ],
    ]);
  }

  Widget _priceSection() {
    final c = NgPalette.of(context);
    final q = _quote;
    Widget line(String k, num? v, {bool bold = false}) =>
        (v == null || v == 0) && !bold
            ? const SizedBox.shrink()
            : NgKeyValue(k, _money.format(v ?? 0), strong: bold);
    return _section('Price', [
      NgSecondaryButton(
        label: _pricing ? 'Working it out…' : (q == null ? 'Get price' : 'Price again'),
        icon: Icons.calculate_outlined,
        onPressed: _pricing ? null : _getPrice,
      ),
      if (q != null && q['ok'] != true) ...[
        const SizedBox(height: 8),
        Text(_problem(q), style: NgFonts.geist(fontSize: 13, color: c.red)),
      ],
      if (q != null && q['ok'] == true) ...[
        const SizedBox(height: 10),
        Text(
            q['km'] == null
                ? '${(q['cft'] as num).round()} CFT'
                : '${(q['cft'] as num).round()} CFT · ${q['km']} km',
            style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
        line('Moving', q['move'] as num?),
        line('Floors without lift', q['floors'] as num?),
        line('Vehicles', q['vehicles'] as num?),
        line('Item services', q['services'] as num?),
        line('Add-ons', q['addons'] as num?),
        line('GST 18%', q['gst'] as num?),
        line('Total', q['total'] as num?, bold: true),
        line('Advance to Nagarva', q['advance'] as num?),
        if (!widget.tryOnly) ...[
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _override,
            onChanged: (v) => setState(() => _override = v),
            title: const Text('Change the price'),
            subtitle: const Text('Only with a reason; it is kept on the job.'),
          ),
          if (_override) ...[
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'New total incl. GST', prefixText: '₹ '),
            ),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                  labelText: 'Reason (e.g. repeat customer, matched competitor)'),
            ),
          ],
          const SizedBox(height: 6),
          TextField(
            controller: _commission,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Commission on this job (%)',
              helperText:
                  '${_rulesFor(_from)['city'] == '*' ? 'Default' : '$_from'} rule: ${_rulesFor(_from)['commission_pct'] ?? '—'}%',
            ),
          ),
        ],
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(widget.tryOnly ? 'Try a price' : 'New Nagarva job'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                if (!widget.tryOnly)
                  _section('Customer', [
                    TextField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Name')),
                    TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(labelText: 'Mobile number')),
                  ]),
                _section('Move', [
                  NgSegmented(
                    labels: const ['Within city', 'Intercity'],
                    selected: _intercity ? 1 : 0,
                    onSelect: (i) => setState(() {
                      _intercity = i == 1;
                      _changed();
                    }),
                  ),
                  const SizedBox(height: 8),
                  _cityPicker(_intercity ? 'From city' : 'City', _from, (v) {
                    setState(() {
                      _from = v;
                      _changed();
                    });
                    _syncCommission();
                  }),
                  if (_intercity)
                    _cityPicker('To city', _to, (v) => setState(() {
                          _to = v;
                          _changed();
                        })),
                  if (!_intercity)
                    TextField(
                      controller: _km,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _changed(),
                      decoration: const InputDecoration(
                          labelText: 'Road distance between the addresses (km)'),
                    ),
                  if (!widget.tryOnly) ...[
                    TextField(
                        controller: _pickupAddr,
                        minLines: 1,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(labelText: 'Pickup address')),
                  ],
                  _floorRow('Pickup', _pickupFloor, _pickupLift, (v) {
                    setState(() {
                      _pickupFloor = v;
                      _changed();
                    });
                  }, (v) {
                    setState(() {
                      _pickupLift = v;
                      _changed();
                    });
                  }),
                  if (!widget.tryOnly)
                    TextField(
                        controller: _dropAddr,
                        minLines: 1,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(labelText: 'Drop address')),
                  _floorRow('Drop', _dropFloor, _dropLift, (v) {
                    setState(() {
                      _dropFloor = v;
                      _changed();
                    });
                  }, (v) {
                    setState(() {
                      _dropLift = v;
                      _changed();
                    });
                  }),
                  if (!widget.tryOnly) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Move date'),
                      subtitle: Text(DateFormat('EEE d MMM yyyy').format(_date)),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final p = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 180)),
                        );
                        if (p != null) setState(() => _date = p);
                      },
                    ),
                    TextField(
                        controller: _slot,
                        decoration: const InputDecoration(
                            labelText: 'Time slot (e.g. 8–10 AM)')),
                  ],
                ]),
                _itemsSection(),
                _section('Package and add-ons', [
                  NgSegmented(
                    labels: const ['Economy', 'Standard', 'Premium'],
                    selected: const ['economy', 'standard', 'premium'].indexOf(_package),
                    onSelect: (i) => setState(() {
                      _package = const ['economy', 'standard', 'premium'][i];
                      _changed();
                    }),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _cover,
                    onChanged: (v) => setState(() {
                      _cover = v;
                      _changed();
                    }),
                    title: const Text('Damage cover'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _unpack,
                    onChanged: (v) => setState(() {
                      _unpack = v;
                      _changed();
                    }),
                    title: const Text('Unpacking'),
                  ),
                  Row(children: [
                    const Expanded(child: Text('Storage (months)')),
                    IconButton(
                        onPressed: _storage > 0
                            ? () => setState(() {
                                  _storage--;
                                  _changed();
                                })
                            : null,
                        icon: const Icon(Icons.remove_rounded)),
                    Text('$_storage'),
                    IconButton(
                        onPressed: () => setState(() {
                              _storage++;
                              _changed();
                            }),
                        icon: const Icon(Icons.add_rounded)),
                  ]),
                ]),
                _priceSection(),
              ],
            ),
      bottomNavigationBar: widget.tryOnly || _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: NgSecondaryButton(
                      label: 'Assign to vendor',
                      icon: Icons.person_add_alt_outlined,
                      onPressed: _saving || _quote?['ok'] != true
                          ? null
                          : () => _save(assign: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NgPrimaryButton(
                      label: 'Broadcast',
                      icon: Icons.campaign_outlined,
                      onPressed: _saving || _quote?['ok'] != true
                          ? null
                          : () => _save(assign: false),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}
