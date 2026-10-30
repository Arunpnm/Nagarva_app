import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';

/// Super Admin › Marketplace (Claude Design handoff, Nagarva Admin.dc.html
/// "Marketplace"): live dispatch, money, vendors and city rules for the
/// Nagarva marketplace (`supabase/20261030_marketplace_vendor.sql`).
///
/// Like the rest of lib/super_admin_page/, every query here is unscoped by
/// org_id on purpose; the mkt_* tables let a platform admin read and write
/// everything (`is_platform_admin()` RLS), and nobody else reaches this tab.
///
/// Jobs are created here until the customer app exists: the admin enters
/// the booking, and the price split follows the city's rules (advance %
/// with its minimum, commission %), GST at 18% inside the total.
///
/// Money does not move here either: Mark paid records that a top-up was
/// received or a withdrawal was sent, after it actually happened.
///
/// Not built from the design: Disputes and Return trips (nothing stores a
/// dispute yet; return trips show on the vendor's own profile). Alerts are
/// derived on each card from the city rules: no vendor after both tier
/// windows, or in transit longer than the stuck-hours limit.
class MarketplaceTab extends StatefulWidget {
  const MarketplaceTab({super.key});

  @override
  State<MarketplaceTab> createState() => _MarketplaceTabState();
}

class _MarketplaceTabState extends State<MarketplaceTab> {
  int _view = 0; // live, money, vendors, rules, prices
  // Customer prices (20261030_marketplace_pricing.sql). Loaded on their
  // own so the rest of the tab works before that migration has run.
  bool _pricingReady = false;
  List<Map<String, dynamic>> _cities = const [];
  List<Map<String, dynamic>> _ratesRows = const [];
  List<Map<String, dynamic>> _cityPrices = const [];
  List<Map<String, dynamic>> _catalogue = const [];
  String? _priceCity;
  bool _loading = true;
  List<Map<String, dynamic>> _jobs = const [];
  List<Map<String, dynamic>> _rules = const [];
  List<Map<String, dynamic>> _vendors = const [];
  List<Map<String, dynamic>> _wallet = const [];
  List<Map<String, dynamic>> _weights = const [];
  Map<String, String> _orgNames = const {};

  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  SupabaseClient get _db => SupaFlow.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        _db.from('mkt_jobs').select().order('broadcast_at', ascending: false).limit(300),
        _db.from('mkt_city_rules').select().order('city'),
        _db.from('mkt_vendors').select(),
        _db.from('mkt_wallet_entries').select().order('created_at', ascending: false).limit(500),
        _db.from('mkt_tier_weights').select().order('weight', ascending: false),
        _db.from('organizations').select('id,name'),
      ]);
      if (!mounted) return;
      setState(() {
        _jobs = List<Map<String, dynamic>>.from(r[0]);
        _rules = List<Map<String, dynamic>>.from(r[1]);
        _vendors = List<Map<String, dynamic>>.from(r[2]);
        _wallet = List<Map<String, dynamic>>.from(r[3]);
        _weights = List<Map<String, dynamic>>.from(r[4]);
        _orgNames = {for (final o in r[5]) '${o['id']}': '${o['name']}'};
        _loading = false;
      });
      await _loadPricing();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _toast('Could not load the marketplace: $e');
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      _toast(done);
    } catch (e) {
      _toast('Could not save: $e');
    }
    await _load();
  }

  Map<String, dynamic> _rulesFor(String? city) =>
      _rules.where((r) => r['city'] == city).firstOrNull ??
      _rules.where((r) => r['city'] == '*').firstOrNull ??
      const {};

  double _balance(String org) => _wallet
      .where((w) => w['org_id'] == org && w['status'] == 'done')
      .fold(0.0, (s, w) => s + (w['amount'] as num).toDouble());

  String _tier(num score) =>
      score >= 80 ? 'Gold' : (score >= 60 ? 'Silver' : 'Bronze');

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    final pending = _wallet.where((w) => w['status'] == 'pending').length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (i, label) in [
              (0, 'Live dispatch'),
              (1, pending > 0 ? 'Money · $pending' : 'Money'),
              (2, 'Vendors'),
              (3, 'City rules'),
              (4, 'Prices'),
            ])
              NgChip(
                  label: label,
                  selected: _view == i,
                  onTap: () => setState(() => _view = i)),
          ]),
          const SizedBox(height: 14),
          ...switch (_view) {
            0 => _live(c),
            1 => _moneyView(c),
            2 => _vendorsView(c),
            3 => _rulesView(c),
            _ => _pricesView(c),
          },
        ],
      ),
    );
  }

  // ---- Live dispatch -----------------------------------------------------

  List<Widget> _live(NgPalette c) {
    final groups = <(String, List<String>)>[
      ('Broadcasting', ['broadcast']),
      ('Accepted · on the way', ['accepted', 'on_the_way', 'arrived']),
      ('Loading', ['loading']),
      ('In transit', ['in_transit']),
      ('Delivered', ['delivered']),
      ('Cancelled', ['cancelled']),
    ];
    return [
      NgPrimaryButton(
          label: 'New Nagarva job', icon: Icons.add_rounded, onPressed: _newJob),
      const SizedBox(height: 14),
      for (final (title, statuses) in groups) ...[
        if (_jobs.any((j) => statuses.contains(j['status']))) ...[
          NgSectionHeader(
              '$title · ${_jobs.where((j) => statuses.contains(j['status'])).length}'),
          const SizedBox(height: 8),
          for (final j in _jobs.where((j) => statuses.contains(j['status'])))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _jobCard(c, j),
            ),
          const SizedBox(height: 6),
        ],
      ],
      if (_jobs.isEmpty)
        const NgEmptyState(
            icon: Icons.storefront_outlined, title: 'No Nagarva jobs yet'),
    ];
  }

  String? _alert(Map<String, dynamic> j) {
    final r = _rulesFor('${j['pickup_city']}');
    final now = DateTime.now();
    final broadcast = DateTime.tryParse('${j['broadcast_at']}')?.toLocal();
    if (j['status'] == 'broadcast' && broadcast != null) {
      final windows = ((r['gold_window_min'] as num?) ?? 0) +
          ((r['silver_window_min'] as num?) ?? 0);
      final mins = now.difference(broadcast).inMinutes;
      if (mins > windows) return 'No vendor after $mins min';
    }
    if (j['status'] == 'in_transit') {
      final events = DateTime.tryParse('${j['updated_at']}')?.toLocal();
      final hours = events == null ? 0 : now.difference(events).inHours;
      if (hours >= ((r['stuck_hours'] as num?) ?? 9999)) {
        return 'In transit ${hours}h · over ${r['stuck_hours']}h';
      }
    }
    return null;
  }

  Widget _jobCard(NgPalette c, Map<String, dynamic> j) {
    final alert = _alert(j);
    final pkg = '${j['package']}';
    final vendor = _orgNames['${j['accepted_org_id']}'];
    final move = DateTime.tryParse('${j['move_date']}');
    return Material(
      color: c.s1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: alert != null ? c.red : c.w06),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _jobSheet(j),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('${j['job_no']}',
                    style: NgFonts.mono(fontSize: 12.5, color: c.mute)),
                const SizedBox(width: 8),
                NgPill('${pkg[0].toUpperCase()}${pkg.substring(1)}',
                    status: pkg == 'premium'
                        ? NgStatus.accent
                        : (pkg == 'standard' ? NgStatus.green : NgStatus.blue)),
              ]),
              const SizedBox(height: 6),
              Text('${j['pickup_city']} → ${j['drop_city']}',
                  style: NgFonts.geist(
                      fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              Text(
                [
                  if (j['cft'] != null) '${(j['cft'] as num).round()} CFT',
                  _money.format(j['total_inr']),
                  if (move != null) DateFormat('d MMM').format(move),
                  if ((j['slot'] ?? '').toString().isNotEmpty) '${j['slot']}',
                ].join(' · '),
                style: NgFonts.geist(fontSize: 12.5, color: c.mute),
              ),
              if (vendor != null) ...[
                const SizedBox(height: 4),
                Text(vendor,
                    style: NgFonts.geist(fontSize: 12.5, color: c.soft)),
              ],
              if (alert != null) ...[
                const SizedBox(height: 6),
                Text(alert, style: NgFonts.geist(fontSize: 12.5, color: c.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _jobSheet(Map<String, dynamic> j) async {
    final c = NgPalette.of(context);
    final status = '${j['status']}';
    final r = _rulesFor('${j['pickup_city']}');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.sheet,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(NgRadius.sheet))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${j['job_no']} · ${j['pickup_city']} → ${j['drop_city']}',
                  style: NgFonts.geist(
                      fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 8),
              NgKeyValue('Customer',
                  '${j['customer_name'] ?? '—'} · ${j['customer_phone'] ?? '—'}'),
              NgKeyValue('Total (incl. GST)', _money.format(j['total_inr'])),
              NgKeyValue('Advance to Nagarva', _money.format(j['advance_inr'])),
              NgKeyValue('Commission', '${j['commission_pct']}%'),
              NgKeyValue('Delivery code', '${j['delivery_otp'] ?? '—'}',
                  mono: true),
              NgKeyValue('Status', status),
              const SizedBox(height: 12),
              if (status == 'broadcast') ...[
                NgSecondaryButton(
                  label: 'Open to all tiers now',
                  icon: Icons.campaign_outlined,
                  onPressed: () {
                    Navigator.pop(ctx);
                    final back = ((r['gold_window_min'] as num?) ?? 0) +
                        ((r['silver_window_min'] as num?) ?? 0);
                    _run(
                        () => _db.from('mkt_jobs').update({
                              'broadcast_at': DateTime.now()
                                  .toUtc()
                                  .subtract(Duration(minutes: back.toInt()))
                                  .toIso8601String(),
                            }).eq('id', j['id']),
                        'Open to every tier now');
                  },
                ),
                const SizedBox(height: 8),
              ],
              if (status != 'delivered' && status != 'cancelled') ...[
                NgSecondaryButton(
                  label: status == 'broadcast' ? 'Assign to a vendor' : 'Re-assign',
                  icon: Icons.person_add_alt_outlined,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _assign(j);
                  },
                ),
                const SizedBox(height: 8),
                NgSecondaryButton(
                  label: 'Cancel job',
                  icon: Icons.cancel_outlined,
                  iconColor: c.red,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _run(() async {
                      await _db
                          .from('mkt_jobs')
                          .update({'status': 'cancelled'}).eq('id', j['id']);
                      await _event(j['id'], 'cancelled_by_admin');
                    }, 'Job cancelled');
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _event(dynamic jobId, String kind, {String? org}) =>
      _db.from('mkt_job_events').insert({
        'job_id': jobId,
        'kind': kind,
        if (org != null) 'org_id': org,
        'actor': _db.auth.currentUser?.id,
      });

  Future<void> _assign(Map<String, dynamic> j) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Assign to'),
        children: [
          for (final v in _vendors.where((v) => v['suspended'] != true))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, '${v['org_id']}'),
              child: Text(
                  '${_orgNames['${v['org_id']}'] ?? v['org_id']} · ${v['home_city'] ?? '—'} · ${_tier(v['score'] as num)}'),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _run(() async {
      await _db.from('mkt_jobs').update({
        'status': 'accepted',
        'accepted_org_id': picked,
        'accepted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', j['id']);
      await _event(j['id'], 'assigned_by_admin', org: picked);
    }, 'Assigned to ${_orgNames[picked] ?? 'vendor'}');
  }

  Future<void> _newJob() async {
    final f = {
      for (final k in [
        'pickup_city', 'drop_city', 'slot', 'cft', 'total', 'name', 'phone',
        'pickup_address', 'drop_address'
      ])
        k: TextEditingController(),
    };
    String pkg = 'standard';
    DateTime date = DateTime.now().add(const Duration(days: 2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Widget tf(String k, String label,
                  {TextInputType? kb, bool digits = false}) =>
              TextField(
                controller: f[k],
                keyboardType: kb,
                inputFormatters:
                    digits ? [FilteringTextInputFormatter.digitsOnly] : null,
                decoration: InputDecoration(labelText: label),
              );
          return AlertDialog(
            title: const Text('New Nagarva job'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  tf('pickup_city', 'Pickup city'),
                  tf('drop_city', 'Drop city'),
                  DropdownButtonFormField<String>(
                    initialValue: pkg,
                    decoration: const InputDecoration(labelText: 'Package'),
                    items: const [
                      DropdownMenuItem(value: 'economy', child: Text('Economy')),
                      DropdownMenuItem(value: 'standard', child: Text('Standard')),
                      DropdownMenuItem(value: 'premium', child: Text('Premium')),
                    ],
                    onChanged: (v) => setD(() => pkg = v ?? pkg),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Move date'),
                    subtitle: Text(DateFormat('EEE d MMM yyyy').format(date)),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 180)),
                      );
                      if (p != null) setD(() => date = p);
                    },
                  ),
                  tf('slot', 'Time slot (e.g. 8–10 AM)'),
                  tf('cft', 'CFT', kb: TextInputType.number, digits: true),
                  tf('total', 'Total incl. 18% GST (₹)',
                      kb: TextInputType.number, digits: true),
                  tf('name', 'Customer name'),
                  tf('phone', 'Customer phone', kb: TextInputType.phone),
                  tf('pickup_address', 'Pickup address'),
                  tf('drop_address', 'Drop address'),
                ]),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Broadcast')),
            ],
          );
        },
      ),
    );
    String t(String k) => f[k]!.text.trim();
    final total = double.tryParse(t('total'));
    if (ok != true) return;
    if (t('pickup_city').isEmpty || t('drop_city').isEmpty || total == null || total <= 0) {
      return _toast('Pickup city, drop city and the total are needed.');
    }
    final r = _rulesFor(t('pickup_city'));
    final gst = double.parse((total * 18 / 118).toStringAsFixed(2));
    final advPct = ((r['advance_pct'] as num?) ?? 0).toDouble();
    final advMin = ((r['advance_min'] as num?) ?? 0).toDouble();
    final advance = min(total, max(advMin, (total * advPct / 100).roundToDouble()));
    final rnd = Random.secure();
    final otp = List.generate(4, (_) => rnd.nextInt(10)).join();
    final jobNo =
        'NG-${DateFormat('yyMMdd').format(DateTime.now())}-${rnd.nextInt(9000) + 1000}';
    await _run(() async {
      final row = await _db.from('mkt_jobs').insert({
        'job_no': jobNo,
        'pickup_city': t('pickup_city'),
        'drop_city': t('drop_city'),
        'package': pkg,
        'move_date': date.toIso8601String().split('T').first,
        if (t('slot').isNotEmpty) 'slot': t('slot'),
        if (t('cft').isNotEmpty) 'cft': double.parse(t('cft')),
        'total_inr': total,
        'gst_inr': gst,
        'advance_inr': advance,
        'commission_pct': (r['commission_pct'] as num?) ?? 0,
        if (t('name').isNotEmpty) 'customer_name': t('name'),
        if (t('phone').isNotEmpty) 'customer_phone': t('phone'),
        if (t('pickup_address').isNotEmpty) 'pickup_address': t('pickup_address'),
        if (t('drop_address').isNotEmpty) 'drop_address': t('drop_address'),
        'delivery_otp': otp,
      }).select('id').single();
      await _event(row['id'], 'broadcast');
    }, '$jobNo broadcast. Delivery code $otp: give it to the customer.');
  }

  // ---- Money -------------------------------------------------------------

  List<Widget> _moneyView(NgPalette c) {
    final pending = _wallet.where((w) => w['status'] == 'pending').toList();
    final done = _wallet.where((w) => w['status'] == 'done');
    double sum(String kind) => done
        .where((w) => w['kind'] == kind)
        .fold(0.0, (s, w) => s + (w['amount'] as num).toDouble());
    return [
      Row(children: [
        Expanded(
            child: NgStatTile(
                icon: Icons.payments_outlined,
                label: 'Advances credited',
                value: _money.format(sum('advance_credit')))),
        const SizedBox(width: 10),
        Expanded(
            child: NgStatTile(
                icon: Icons.percent_rounded,
                label: 'Commission',
                value: _money.format(-sum('commission')))),
      ]),
      const SizedBox(height: 14),
      NgSectionHeader('Requests waiting · ${pending.length}'),
      const SizedBox(height: 8),
      if (pending.isEmpty)
        const NgEmptyState(
            icon: Icons.check_circle_outline, title: 'Nothing waiting')
      else
        NgCardList(children: [
          for (final w in pending)
            NgListRow(
              icon: w['kind'] == 'topup'
                  ? Icons.add_card_outlined
                  : Icons.account_balance_outlined,
              title:
                  '${_orgNames['${w['org_id']}'] ?? w['org_id']} · ${w['kind'] == 'topup' ? 'Top-up' : 'Withdrawal'}',
              subtitle: [
                _money.format((w['amount'] as num).abs()),
                if ((w['reference'] ?? '').toString().isNotEmpty)
                  'ref ${w['reference']}',
                'balance ${_money.format(_balance('${w['org_id']}'))}',
              ].join(' · '),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                  onPressed: () => _run(
                      () => _db
                          .from('mkt_wallet_entries')
                          .update({'status': 'rejected'}).eq('id', w['id']),
                      'Rejected'),
                  child: Text('Reject', style: TextStyle(color: c.red)),
                ),
                TextButton(
                  onPressed: () => _confirmPaid(w),
                  child: Text(w['kind'] == 'topup' ? 'Received' : 'Paid'),
                ),
              ]),
            ),
        ]),
    ];
  }

  Future<void> _confirmPaid(Map<String, dynamic> w) async {
    final topup = w['kind'] == 'topup';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(topup ? 'Money received?' : 'Money sent?'),
        content: Text(topup
            ? 'Confirm only after ${_money.format(w['amount'])} has reached Nagarva\'s account. It then counts toward the vendor\'s balance.'
            : 'Confirm only after ${_money.format((w['amount'] as num).abs())} has been paid to the vendor\'s bank account.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
        () => _db
            .from('mkt_wallet_entries')
            .update({'status': 'done'}).eq('id', w['id']),
        'Confirmed');
  }

  // ---- Vendors -----------------------------------------------------------

  List<Widget> _vendorsView(NgPalette c) {
    if (_vendors.isEmpty) {
      return const [
        NgEmptyState(
            icon: Icons.storefront_outlined,
            title: 'No vendor has joined yet',
            subtitle: 'A vendor joins by setting a home city in Nagarva jobs.'),
      ];
    }
    return [
      NgCardList(children: [
        for (final v in _vendors)
          NgListRow(
            icon: Icons.local_shipping_outlined,
            title: _orgNames['${v['org_id']}'] ?? '${v['org_id']}',
            subtitle: [
              '${v['home_city'] ?? '—'}',
              '${_tier(v['score'] as num)} · ${(v['score'] as num).round()}',
              _money.format(_balance('${v['org_id']}')),
              if (v['available'] == true) 'available' else 'off',
              if (v['suspended'] == true) 'SUSPENDED',
            ].join(' · '),
            trailing: PopupMenuButton<String>(
              onSelected: (a) => a == 'score' ? _editScore(v) : _toggleSuspend(v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'score', child: Text('Set score')),
                PopupMenuItem(
                    value: 'suspend',
                    child: Text(v['suspended'] == true ? 'Lift suspension' : 'Suspend')),
              ],
            ),
          ),
      ]),
    ];
  }

  Future<void> _toggleSuspend(Map<String, dynamic> v) => _run(
      () => _db.from('mkt_vendors').update({
            'suspended': v['suspended'] != true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('org_id', v['org_id']),
      v['suspended'] == true ? 'Suspension lifted' : 'Vendor suspended');

  Future<void> _editScore(Map<String, dynamic> v) async {
    final ctrl = TextEditingController(text: '${(v['score'] as num).round()}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Score (0–100)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
              helperText: 'Gold 80+ · Silver 60–79 · Bronze <60'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    final s = int.tryParse(ctrl.text);
    if (ok != true || s == null || s < 0 || s > 100) return;
    await _run(
        () => _db.from('mkt_vendors').update({
              'score': s,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('org_id', v['org_id']),
        'Score saved');
  }

  // ---- Customer prices ---------------------------------------------------

  Future<void> _loadPricing() async {
    try {
      final r = await Future.wait([
        _db.from('mkt_cities').select().order('city'),
        _db.from('mkt_rates').select(),
        _db.from('mkt_city_prices').select(),
        _db.from('mkt_catalogue').select().order('sort'),
      ]);
      if (!mounted) return;
      setState(() {
        _cities = List<Map<String, dynamic>>.from(r[0]);
        _ratesRows = List<Map<String, dynamic>>.from(r[1]);
        _cityPrices = List<Map<String, dynamic>>.from(r[2]);
        _catalogue = List<Map<String, dynamic>>.from(r[3]);
        _priceCity ??= _cities.firstOrNull?['city'] as String?;
        _pricingReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _pricingReady = false);
    }
  }

  static const _pkgs = ['economy', 'standard', 'premium'];
  static const _cityPriceFields = <(String, String)>[
    ('per_floor', 'Per floor without lift (₹)'),
    ('car_local', 'Car, within city (₹)'),
    ('car_base', 'Car, intercity base (₹)'),
    ('car_per_km', 'Car, intercity per km (₹)'),
    ('bike_local', 'Two-wheeler, within city (₹)'),
    ('bike_base', 'Two-wheeler, intercity base (₹)'),
    ('bike_per_km', 'Two-wheeler, intercity per km (₹)'),
    ('damage_cover', 'Damage cover (₹)'),
    ('unpacking', 'Unpacking & arranging (₹)'),
    ('storage_month', 'Storage per month (₹)'),
  ];

  List<Widget> _pricesView(NgPalette c) {
    if (!_pricingReady) {
      return const [
        NgEmptyState(
          icon: Icons.price_change_outlined,
          title: 'Prices are not set up yet',
          subtitle:
              'Run supabase/20261030_marketplace_pricing.sql, then come back.',
        ),
      ];
    }
    final city = _priceCity;
    final cp = _cityPrices.where((p) => p['city'] == city).firstOrNull;
    String v(dynamic x) => x == null ? 'Not set' : _money.format(x);
    return [
      Text(
          'What customers pay Nagarva. A city shows prices in the customer app only once its rates are here; anything left unset makes the quote say so instead of guessing.',
          style: NgFonts.geist(fontSize: 12.5, height: 1.4, color: c.mute)),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in _cities)
          NgChip(
              label: '${x['city']}',
              selected: x['city'] == city,
              onTap: () => setState(() => _priceCity = '${x['city']}')),
      ]),
      const SizedBox(height: 14),
      if (city != null) ...[
        NgSectionHeader('Package rates · $city'),
        const SizedBox(height: 8),
        NgCardList(children: [
          for (final pkg in _pkgs)
            () {
              final r = _ratesRows
                  .where((x) => x['city'] == city && x['package'] == pkg)
                  .firstOrNull;
              return NgListRow(
                title: '${pkg[0].toUpperCase()}${pkg.substring(1)}',
                subtitle: r == null
                    ? 'Not set'
                    : '₹${r['per_cft']} per CFT · +₹${r['per_cft_per_km']} per CFT per km intercity · min ${_money.format(r['min_move'])}',
                trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
                onTap: () => _editRate(city, pkg, r),
              );
            }(),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: NgSectionHeader('Other prices · $city')),
          TextButton(
              onPressed: () => _editCityPrices(city, cp),
              child: const Text('Edit')),
        ]),
        const SizedBox(height: 8),
        NgCardList(children: [
          for (final (k, label) in _cityPriceFields)
            NgListRow(
              title: label,
              trailing: Text(v(cp?[k]),
                  style: NgFonts.mono(
                      fontSize: 13.5,
                      color: cp?[k] == null ? c.faint : c.text)),
            ),
        ]),
      ],
      const SizedBox(height: 16),
      const NgSectionHeader('Item services (all cities)'),
      const SizedBox(height: 8),
      NgCardList(children: [
        for (final it in _catalogue.where((x) => (x['services'] as List).isNotEmpty))
          NgListRow(
            title: '${it['name']}',
            subtitle: [
              for (final sv in it['services'] as List)
                '${sv['label']}: ${sv['price'] == null ? 'not set' : _money.format(sv['price'])}',
            ].join(' · '),
            trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
            onTap: () => _editServices(it),
          ),
      ]),
    ];
  }

  Future<Map<String, num?>?> _numbersDialog(
      String title, List<(String, String)> fields, Map<String, dynamic>? cur,
      {bool required = true}) async {
    final ctrls = {
      for (final (k, _) in fields)
        k: TextEditingController(text: cur?[k] == null ? '' : '${cur![k]}'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (k, label) in fields)
                TextField(
                  controller: ctrls[k],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: label,
                      hintText: required ? null : 'Leave empty if not offered'),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return null;
    final out = <String, num?>{};
    for (final (k, _) in fields) {
      final t = ctrls[k]!.text.trim();
      final n = num.tryParse(t);
      if (t.isNotEmpty && (n == null || n < 0)) {
        _toast('Enter a number of zero or more.');
        return null;
      }
      if (required && n == null) {
        _toast('Every field is needed.');
        return null;
      }
      out[k] = n;
    }
    return out;
  }

  Future<void> _editRate(String city, String pkg, Map<String, dynamic>? r) async {
    final vals = await _numbersDialog('$city · $pkg', const [
      ('per_cft', 'Rate per CFT (₹)'),
      ('per_cft_per_km', 'Extra per CFT per km, intercity (₹)'),
      ('min_move', 'Minimum move charge (₹)'),
    ], r);
    if (vals == null) return;
    await _run(
        () => _db.from('mkt_rates').upsert({
              'city': city,
              'package': pkg,
              ...vals,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }, onConflict: 'city,package'),
        'Rates saved');
  }

  Future<void> _editCityPrices(String city, Map<String, dynamic>? cp) async {
    final vals = await _numbersDialog('$city · other prices', _cityPriceFields, cp,
        required: false);
    if (vals == null) return;
    await _run(
        () => _db.from('mkt_city_prices').upsert({
              'city': city,
              ...vals,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }, onConflict: 'city'),
        'Prices saved');
  }

  Future<void> _editServices(Map<String, dynamic> it) async {
    final services = [
      for (final s in it['services'] as List) Map<String, dynamic>.from(s)
    ];
    final vals = await _numbersDialog(
        '${it['name']}',
        [for (final s in services) ('${s['code']}', '${s['label']} (₹)')],
        {for (final s in services) '${s['code']}': s['price']},
        required: false);
    if (vals == null) return;
    for (final s in services) {
      s['price'] = vals['${s['code']}'];
    }
    await _run(
        () => _db
            .from('mkt_catalogue')
            .update({'services': services}).eq('key', it['key']),
        'Service prices saved');
  }

  // ---- City rules and weights --------------------------------------------

  static const _ruleFields = <(String, String)>[
    ('gold_window_min', 'Gold-only window (min)'),
    ('silver_window_min', 'Silver window (min)'),
    ('wallet_min', 'Minimum wallet (₹)'),
    ('commission_pct', 'Commission (%)'),
    ('advance_pct', 'Customer advance (%)'),
    ('advance_min', 'Minimum advance (₹)'),
    ('late_min', 'Late arrival alert (min)'),
    ('stuck_hours', 'Stuck in transit alert (h)'),
    ('return_delay_min', 'Return-load vendors see jobs after (min)'),
  ];

  List<Widget> _rulesView(NgPalette c) {
    final total = _weights.fold<int>(0, (s, w) => s + (w['weight'] as int));
    return [
      Row(children: [
        const Expanded(child: NgSectionHeader('City rules')),
        TextButton.icon(
          onPressed: _addCity,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add city'),
        ),
      ]),
      const SizedBox(height: 8),
      NgCardList(children: [
        for (final r in _rules)
          NgListRow(
            icon: Icons.location_city_outlined,
            title: r['city'] == '*' ? 'Default (every other city)' : '${r['city']}',
            subtitle:
                'Gold ${r['gold_window_min']}m · Silver ${r['silver_window_min']}m · min ${_money.format(r['wallet_min'])} · ${r['commission_pct']}% commission · ${r['advance_pct']}% advance (min ${_money.format(r['advance_min'])})',
            trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
            onTap: () => _editRules(r),
          ),
      ]),
      const SizedBox(height: 18),
      NgSectionHeader('Tier weights · total $total'),
      const SizedBox(height: 8),
      NgCardList(children: [
        for (final w in _weights)
          NgListRow(
            title: '${w['factor']}'.replaceAll('_', ' '),
            trailing: Text('${w['weight']}%',
                style: NgFonts.mono(fontSize: 14, color: c.text)),
            onTap: () => _editWeight(w, total),
          ),
      ]),
    ];
  }

  Future<void> _addCity() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add city'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
                labelText: 'City',
                helperText: 'Starts with the default rules; edit after.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    final city = ctrl.text.trim();
    if (ok != true || city.isEmpty) return;
    final base = Map<String, dynamic>.from(_rulesFor('*'))
      ..['city'] = city
      ..remove('updated_at');
    await _run(() => _db.from('mkt_city_rules').insert(base), '$city added');
  }

  Future<void> _editRules(Map<String, dynamic> r) async {
    final ctrls = {
      for (final (k, _) in _ruleFields)
        k: TextEditingController(text: '${r[k]}'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r['city'] == '*' ? 'Default rules' : '${r['city']}'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (k, label) in _ruleFields)
                TextField(
                  controller: ctrls[k],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: label),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final data = <String, dynamic>{};
    for (final (k, _) in _ruleFields) {
      final v = num.tryParse(ctrls[k]!.text.trim());
      if (v == null) return _toast('Every rule needs a number.');
      data[k] = v;
    }
    data['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _run(
        () => _db.from('mkt_city_rules').update(data).eq('city', r['city']),
        'Rules saved');
  }

  Future<void> _editWeight(Map<String, dynamic> w, int total) async {
    final ctrl = TextEditingController(text: '${w['weight']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${w['factor']}'.replaceAll('_', ' ')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
              helperText:
                  'Weights should total 100 (now $total). Adjust another factor to balance.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    final v = int.tryParse(ctrl.text);
    if (ok != true || v == null || v > 100) return;
    await _run(
        () => _db
            .from('mkt_tier_weights')
            .update({'weight': v}).eq('factor', w['factor']),
        'Weight saved');
  }
}
