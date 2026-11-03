import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '/backend/edge_function_errors.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/l10n/gen/app_localizations.dart';

/// Sales › Nagarva jobs (Claude Design handoff, screen `mkt`): moves that
/// customers booked with Nagarva, broadcast to vendors by tier.
///
/// Everything goes through the functions in
/// `supabase/20261030_marketplace_vendor.sql` (live since 30 Oct 2026,
/// checked by query): jobs come from mkt_vendor_jobs(), which hides the
/// customer until this vendor accepts; accept, pass, each step, the
/// delivery code and wallet requests are mkt_* functions that refuse
/// anyone but this org's owner or manager.
///
/// Top up and Withdraw only REQUEST: a Nagarva admin marks them done once
/// the money has actually moved. No payment gateway is wired yet (it
/// waits on which entity collects, CLAUDE.md Item 31).
class MarketplaceJobsPage extends StatefulWidget {
  const MarketplaceJobsPage({super.key});

  static const routeName = 'MarketplaceJobsPage';
  static const routePath = '/nagarva-jobs';

  @override
  State<MarketplaceJobsPage> createState() => _MarketplaceJobsPageState();
}

const _kSteps = [
  'accepted',
  'on_the_way',
  'arrived',
  'loading',
  'in_transit',
  'delivered',
];

class _MarketplaceJobsPageState extends State<MarketplaceJobsPage> {
  int _tab = 0; // 0 jobs, 1 wallet, 2 tier
  int _filter = 0; // 0 new, 1 accepted, 2 completed
  bool _loading = true;
  bool _busy = false;

  Map<String, dynamic>? _vendor;
  Map<String, dynamic>? _rules;
  double _balance = 0;
  List<Map<String, dynamic>> _jobs = const [];
  List<Map<String, dynamic>> _wallet = const [];
  List<Map<String, dynamic>> _weights = const [];

  /// Loading photos taken for a job, before it moves to in transit.
  final Map<String, List<String>> _photos = {};

  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  String? get _org => OrgScope.currentOrgId;
  SupabaseClient get _db => SupaFlow.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final org = _org;
    if (org == null) return;
    try {
      final vendor = await _db
          .from('mkt_vendors')
          .select()
          .eq('org_id', org)
          .maybeSingle();
      final rules = await _db.rpc('mkt_rules_for',
          params: {'p_city': vendor?['home_city'] ?? '*'});
      final bal = await _db.rpc('mkt_wallet_balance', params: {'p_org': org});
      final jobs = await _db.rpc('mkt_vendor_jobs', params: {'p_org': org});
      final wallet = await _db
          .from('mkt_wallet_entries')
          .select()
          .eq('org_id', org)
          .order('created_at', ascending: false)
          .limit(100);
      final weights = await _db
          .from('mkt_tier_weights')
          .select()
          .order('weight', ascending: false);
      if (!mounted) return;
      setState(() {
        _vendor = vendor;
        _rules = rules is Map ? Map<String, dynamic>.from(rules) : null;
        _balance = (bal as num?)?.toDouble() ?? 0;
        _jobs = [for (final j in (jobs as List)) Map<String, dynamic>.from(j)];
        _wallet = List<Map<String, dynamic>>.from(wallet);
        _weights = List<Map<String, dynamic>>.from(weights);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _toast(extractDbErrorMessage(e,
          fallback: AppLocalizations.of(context).dwSaveFailed));
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await f();
      if (done != null) _toast(done);
      await _load();
    } catch (e) {
      _toast(extractDbErrorMessage(e, fallback: l.dwSaveFailed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- derived -----------------------------------------------------------

  double get _score => (_vendor?['score'] as num?)?.toDouble() ?? 0;
  String get _tier =>
      _score >= 80 ? 'gold' : (_score >= 60 ? 'silver' : 'bronze');
  double get _walletMin => (_rules?['wallet_min'] as num?)?.toDouble() ?? 0;
  bool get _available => _vendor?['available'] == true;
  String? get _homeCity => _vendor?['home_city'] as String?;
  List<String> get _extraCities =>
      [for (final c in (_vendor?['extra_cities'] as List? ?? [])) '$c'];

  String _tierName(AppLocalizations l, String t) => switch (t) {
        'gold' => l.mktTierGold,
        'silver' => l.mktTierSilver,
        _ => l.mktTierBronze,
      };

  String _stepName(AppLocalizations l, String s) => switch (s) {
        'accepted' => l.mktS0,
        'on_the_way' => l.mktS1,
        'arrived' => l.mktS2,
        'loading' => l.mktS3,
        'in_transit' => l.mktS4,
        _ => l.mktS5,
      };

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                children: [
                  NgModuleHeader(l.mktTitle, subtitle: l.mktSub),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: NgStatTile(
                        icon: Icons.workspace_premium_outlined,
                        label: l.mktTier,
                        value: '${_tierName(l, _tier)} · ${_score.round()}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NgStatTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: l.mktWallet,
                        value: _money.format(_balance),
                        color: _balance < _walletMin ? c.red : c.green,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  NgSegmented(
                    labels: [l.mktTJobs, l.mktTWallet, l.mktTTier],
                    selected: _tab,
                    onSelect: (i) => setState(() => _tab = i),
                  ),
                  const SizedBox(height: 12),
                  ...switch (_tab) {
                    0 => _jobsTab(c, l),
                    1 => _walletTab(c, l),
                    _ => _tierTab(c, l),
                  },
                ],
              ),
            ),
    );
  }

  // ---- Jobs tab ----------------------------------------------------------

  List<Widget> _jobsTab(NgPalette c, AppLocalizations l) {
    final home = _homeCity;
    final cities = [if (home != null) home, ..._extraCities];
    final newJobs = _jobs.where((j) => j['mine'] != true).toList();
    final mine = _jobs.where((j) => j['mine'] == true).toList();
    final active = mine.where((j) => j['status'] != 'delivered').toList();
    final done = mine.where((j) => j['status'] == 'delivered').toList();
    final shown = [newJobs, active, done][_filter];
    return [
      NgCardList(children: [
        NgListRow(
          icon: Icons.notifications_active_outlined,
          title: l.mktAv,
          subtitle: home == null
              ? l.mktNotJoined
              : (_available ? l.mktAvOn(cities.join(', ')) : l.mktAvOff),
          trailing: Switch(
            value: _available,
            onChanged: home == null || _busy
                ? null
                : (v) => _run(() => _setVendor(available: v),
                    done: v ? l.mktAvOnT : l.mktAvOffT),
          ),
        ),
        NgListRow(
          icon: Icons.place_outlined,
          title: l.mktCities,
          subtitle: cities.isEmpty ? l.mktNotJoined : cities.join(', '),
          trailing: TextButton(
              onPressed: _busy ? null : _editCities, child: Text(l.mktEdit)),
        ),
        if (home != null) _returnRow(c, l),
      ]),
      const SizedBox(height: 12),
      if (_balance < _walletMin)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: NgCard(
            child: Text(
              l.mktLow(_money.format(_walletMin - _balance),
                  _money.format(_walletMin)),
              style: NgFonts.geist(fontSize: 13, color: c.red),
            ),
          ),
        ),
      NgSegmented(
        labels: [l.mktFNew, l.mktFAcc, l.mktFDone],
        counts: [newJobs.length, active.length, done.length],
        selected: _filter,
        onSelect: (i) => setState(() => _filter = i),
      ),
      const SizedBox(height: 12),
      if (shown.isEmpty)
        NgEmptyState(
          icon: Icons.local_shipping_outlined,
          title: switch (_filter) {
            0 => _available ? l.mktENew : l.mktEOff,
            1 => l.mktEAcc,
            _ => l.mktEDone,
          },
        )
      else
        for (final j in shown) ...[
          _jobCard(c, l, j),
          const SizedBox(height: 10),
        ],
    ];
  }

  Widget _returnRow(NgPalette c, AppLocalizations l) {
    final from = _vendor?['return_from_city'] as String?;
    if (from == null) {
      return NgListRow(
        icon: Icons.u_turn_left_rounded,
        title: l.mktRtAsk,
        trailing: TextButton(
            onPressed: _busy ? null : _addReturn, child: Text(l.mktRtAdd)),
      );
    }
    return NgListRow(
      icon: Icons.u_turn_left_rounded,
      title: l.mktRtOn(from, _homeCity ?? ''),
      trailing: TextButton(
        onPressed: _busy
            ? null
            : () => _run(() => _setVendor(returnFrom: '', returnOn: null),
                done: l.mktRtEnded),
        child: Text(l.mktRtEnd),
      ),
    );
  }

  Future<void> _setVendor({
    bool? available,
    String? home,
    List<String>? extra,
    String? returnFrom,
    DateTime? returnOn,
    bool keepReturn = true,
  }) async {
    final keep = returnFrom == null && keepReturn;
    await _db.rpc('mkt_set_vendor', params: {
      'p_org': _org,
      'p_available': available ?? _available,
      'p_home_city': home ?? _homeCity,
      'p_extra_cities': extra ?? _extraCities,
      'p_return_from_city':
          keep ? (_vendor?['return_from_city']) : (returnFrom ?? ''),
      'p_return_on': keep
          ? (_vendor?['return_on'])
          : returnOn?.toIso8601String().split('T').first,
    });
  }

  Future<void> _editCities() async {
    final l = AppLocalizations.of(context);
    final home = TextEditingController(text: _homeCity ?? '');
    final extra = TextEditingController(text: _extraCities.join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.mktCities),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: home,
              decoration: InputDecoration(labelText: l.mktHomeCity)),
          TextField(
              controller: extra,
              decoration: InputDecoration(labelText: l.mktExtraCities)),
          const SizedBox(height: 8),
          Text(l.mktCitiesN,
              style: NgFonts.geist(
                  fontSize: 12.5, color: NgPalette.of(ctx).mute)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.mktCancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.mktDone2)),
        ],
      ),
    );
    if (ok != true) return;
    final cities = extra.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != home.text.trim())
        .toSet()
        .toList();
    await _run(() => _setVendor(home: home.text.trim(), extra: cities));
  }

  Future<void> _addReturn() async {
    final l = AppLocalizations.of(context);
    final from = TextEditingController();
    DateTime on = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(l.mktRtAsk),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: from,
                decoration: InputDecoration(labelText: l.mktRtFrom)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.mktRtDate),
              subtitle: Text(DateFormat('d MMM yyyy').format(on)),
              onTap: () async {
                final p = await showDatePicker(
                  context: ctx,
                  initialDate: on,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 60)),
                );
                if (p != null) setD(() => on = p);
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(l.mktCancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.mktRtAdd)),
          ],
        ),
      ),
    );
    if (ok != true || from.text.trim().isEmpty) return;
    await _run(() => _setVendor(returnFrom: from.text.trim(), returnOn: on));
  }

  Widget _jobCard(NgPalette c, AppLocalizations l, Map<String, dynamic> j) {
    final mine = j['mine'] == true;
    final status = '${j['status']}';
    final total = (j['total_inr'] as num?)?.toDouble() ?? 0;
    final gst = (j['gst_inr'] as num?)?.toDouble() ?? 0;
    final advance = (j['advance_inr'] as num?)?.toDouble() ?? 0;
    final pct = (j['commission_pct'] as num?)?.toDouble() ?? 0;
    final commission = ((total - gst) * pct / 100).roundToDouble();
    final earn = total - commission;
    final pkg = '${j['package']}';
    final pkgLabel = '${pkg[0].toUpperCase()}${pkg.substring(1)}';
    final move = DateTime.tryParse('${j['move_date']}');
    Widget kv(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(
                child: Text(k,
                    style: NgFonts.geist(fontSize: 13, color: c.mute))),
            Text(v,
                style: NgFonts.mono(fontSize: 13.5, color: color ?? c.text)),
          ]),
        );
    return NgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            NgPill(pkg == 'premium' ? '$pkgLabel · ${l.mktGoldOnly}' : pkgLabel,
                status: pkg == 'premium'
                    ? NgStatus.accent
                    : (pkg == 'standard' ? NgStatus.green : NgStatus.blue)),
            const SizedBox(width: 8),
            Text('${j['job_no']}',
                style: NgFonts.mono(fontSize: 12.5, color: c.mute)),
            const Spacer(),
            if (mine) NgPill(_stepName(l, status), status: NgStatus.amber),
          ]),
          const SizedBox(height: 8),
          Text('${j['pickup_city']} → ${j['drop_city']}',
              style: NgFonts.geist(
                  fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
          if ((j['cft'] as num?) != null)
            Text('${(j['cft'] as num).round()} CFT',
                style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          if (move != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.event_outlined, size: 17, color: c.acc),
              const SizedBox(width: 6),
              Text(
                  [
                    DateFormat('EEE d MMM').format(move),
                    if ((j['slot'] ?? '').toString().isNotEmpty) '${j['slot']}',
                  ].join(' · '),
                  style: NgFonts.geist(fontSize: 13.5, color: c.text)),
            ]),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: c.inset, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              kv(l.mktVal, _money.format(total)),
              kv(l.mktCom('${pct % 1 == 0 ? pct.round() : pct}'),
                  '- ${_money.format(commission)}'),
              kv(l.mktEarn, _money.format(earn), color: c.green),
              kv(l.mktAdv, _money.format(advance)),
              kv(l.mktBal, _money.format(total - advance)),
            ]),
          ),
          const SizedBox(height: 10),
          if (!mine) ...[
            Row(children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: c.mute),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l.mktMasked,
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: NgSecondaryButton(
                  label: l.mktPass,
                  icon: Icons.close_rounded,
                  height: 46,
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _db.rpc('mkt_pass_job',
                              params: {'p_org': _org, 'p_job': j['id']}),
                          done: l.mktPassed),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NgPrimaryButton(
                  label: l.mktAccept,
                  icon: Icons.check_circle_outline_rounded,
                  onPressed: _busy ? null : () => _accept(j),
                ),
              ),
            ]),
          ] else
            ..._mineActions(c, l, j, status, advance, commission),
        ],
      ),
    );
  }

  Future<void> _accept(Map<String, dynamic> j) async {
    final l = AppLocalizations.of(context);
    String? res;
    await _run(() async {
      res = await _db.rpc('mkt_accept_job',
          params: {'p_org': _org, 'p_job': j['id']}) as String?;
    });
    if (res == 'accepted') {
      _toast(l.mktAccepted('${j['job_no']}'));
    } else if (res != null) {
      _toast(l.mktTaken);
    }
  }

  List<Widget> _mineActions(NgPalette c, AppLocalizations l,
      Map<String, dynamic> j, String status, double advance, double commission) {
    final name = (j['customer_name'] ?? '').toString();
    final phone = (j['customer_phone'] ?? '').toString();
    final contact = <Widget>[
      if (name.isNotEmpty || phone.isNotEmpty)
        NgListRow(
          icon: Icons.person_outline_rounded,
          title: name.isEmpty ? phone : name,
          subtitle: [
            if (phone.isNotEmpty && name.isNotEmpty) phone,
            if ((j['pickup_address'] ?? '').toString().isNotEmpty)
              '${j['pickup_address']}',
          ].join('\n'),
          trailing: phone.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.call_rounded, color: c.green),
                  onPressed: () => launchURL('tel:$phone'),
                ),
        ),
    ];
    if (status == 'delivered') {
      final rating = j['rating'];
      return [
        ...contact,
        Text(
          [
            l.mktDone(_money.format(advance), _money.format(commission)),
            rating == null ? l.mktNoRate : l.mktRate('$rating'),
          ].join('\n'),
          style: NgFonts.geist(fontSize: 13, color: c.mute),
        ),
      ];
    }
    final i = _kSteps.indexOf(status);
    final next = i >= 0 && i + 1 < _kSteps.length ? _kSteps[i + 1] : null;
    final photos = _photos[j['id']] ?? const <String>[];
    return [
      ...contact,
      // Stepper
      Row(children: [
        for (var s = 0; s < _kSteps.length; s++) ...[
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: s <= i ? c.accBtn : c.w07,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (s < _kSteps.length - 1) const SizedBox(width: 3),
        ],
      ]),
      const SizedBox(height: 10),
      if (status == 'loading') ...[
        Row(children: [
          Expanded(
            child: Text(l.mktPhotos(photos.length),
                style: NgFonts.geist(fontSize: 13, color: c.text)),
          ),
          if (photos.length < 3)
            TextButton.icon(
              onPressed: _busy ? null : () => _addPhoto(j),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l.mktAddPh),
            ),
        ]),
        const SizedBox(height: 8),
      ],
      if (next != null)
        NgPrimaryButton(
          label: next == 'delivered' ? l.mktFinish : l.mktNext(_stepName(l, next)),
          onPressed: _busy ? null : () => _advance(j, next),
        ),
    ];
  }

  Future<void> _addPhoto(Map<String, dynamic> j) async {
    final shot = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    if (shot == null) return;
    final bytes = await shot.readAsBytes();
    final path =
        '$_org/mkt/${j['id']}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _run(() async {
      await _db.storage.from('job-photos').uploadBinary(path, bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'));
      _photos.putIfAbsent('${j['id']}', () => []).add(path);
    });
  }

  Future<void> _advance(Map<String, dynamic> j, String next) async {
    final l = AppLocalizations.of(context);
    String? otp;
    List<String>? photos;
    if (next == 'in_transit') {
      photos = _photos['${j['id']}'];
      if ((photos?.length ?? 0) < 3) return _toast(l.mktNeedPh);
    }
    if (next == 'delivered') {
      otp = await _askOtp();
      if (otp == null) return;
    }
    await _run(() => _db.rpc('mkt_advance_job', params: {
          'p_org': _org,
          'p_job': j['id'],
          'p_to': next,
          'p_otp': otp,
          'p_photos': photos,
        }));
  }

  Future<String?> _askOtp() {
    final l = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.mktFinish),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.mktOtpAsk),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: NgFonts.mono(fontSize: 22),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.mktCancel)),
          TextButton(
              onPressed: () => ctrl.text.length == 4
                  ? Navigator.pop(ctx, ctrl.text)
                  : null,
              child: Text(l.mktDone2)),
        ],
      ),
    );
  }

  // ---- Wallet tab --------------------------------------------------------

  List<Widget> _walletTab(NgPalette c, AppLocalizations l) {
    final ok = _balance >= _walletMin;
    final pct = (_rules?['commission_pct'] as num?) ?? 0;
    return [
      NgCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.mktWBal, style: NgFonts.geist(fontSize: 13, color: c.mute)),
            const SizedBox(height: 4),
            Text(_money.format(_balance),
                style: NgFonts.mono(
                    fontSize: 28, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 6),
            Text(
              ok
                  ? '${l.mktWOk} · ${l.mktMinL(_money.format(_walletMin))}'
                  : l.mktLow(_money.format(_walletMin - _balance),
                      _money.format(_walletMin)),
              style: NgFonts.geist(fontSize: 13, color: ok ? c.green : c.red),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: NgPrimaryButton(
                  label: l.mktTopup,
                  icon: Icons.add_rounded,
                  onPressed: _busy ? null : () => _request('topup'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NgSecondaryButton(
                  label: l.mktWWithdraw,
                  icon: Icons.account_balance_outlined,
                  height: 50,
                  onPressed: _busy ? null : () => _request('withdrawal'),
                ),
              ),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(l.mktWNote('${pct % 1 == 0 ? pct.round() : pct}'),
          style: NgFonts.geist(fontSize: 12.5, height: 1.4, color: c.mute)),
      const SizedBox(height: 12),
      if (_wallet.isNotEmpty)
        NgCardList(children: [
          for (final w in _wallet)
            NgListRow(
              icon: switch (w['kind']) {
                'topup' => Icons.add_card_outlined,
                'withdrawal' => Icons.account_balance_outlined,
                'commission' => Icons.percent_rounded,
                _ => Icons.payments_outlined,
              },
              title: switch (w['kind']) {
                'topup' => l.mktWtTop,
                'withdrawal' => l.mktWtWd,
                'advance_credit' => l.mktWtAdv(_jobNo(w['job_id'])),
                'commission' => l.mktWtCom(_jobNo(w['job_id'])),
                _ => '${w['kind']}',
              },
              subtitle: [
                if (DateTime.tryParse('${w['created_at']}') != null)
                  DateFormat('d MMM, h:mm a')
                      .format(DateTime.parse('${w['created_at']}').toLocal()),
                if (w['status'] == 'pending') l.mktPending,
              ].join(' · '),
              trailing: Text(
                '${((w['amount'] as num) >= 0) ? '+' : '−'}${_money.format((w['amount'] as num).abs())}',
                style: NgFonts.mono(
                    fontSize: 14,
                    color: w['status'] == 'pending'
                        ? c.mute
                        : ((w['amount'] as num) >= 0 ? c.green : c.text)),
              ),
            ),
        ]),
    ];
  }

  String _jobNo(dynamic id) =>
      '${_jobs.where((j) => j['id'] == id).firstOrNull?['job_no'] ?? ''}';

  Future<void> _request(String kind) async {
    final l = AppLocalizations.of(context);
    final amount = TextEditingController();
    final ref = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(kind == 'topup' ? l.mktTopup : l.mktWWithdraw),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '₹'),
          ),
          if (kind == 'topup')
            TextField(
              controller: ref,
              decoration: const InputDecoration(labelText: 'UPI ref'),
            ),
          const SizedBox(height: 8),
          Text(l.mktReqSent,
              style: NgFonts.geist(
                  fontSize: 12.5, color: NgPalette.of(ctx).mute)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.mktCancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.mktDone2)),
        ],
      ),
    );
    final a = double.tryParse(amount.text.trim());
    if (ok != true || a == null || a <= 0) return;
    await _run(
      () => _db.rpc('mkt_request_wallet', params: {
        'p_org': _org,
        'p_kind': kind,
        'p_amount': a,
        'p_reference': ref.text.trim(),
      }),
      done: l.mktReqSent,
    );
  }

  // ---- Tier tab ----------------------------------------------------------

  List<Widget> _tierTab(NgPalette c, AppLocalizations l) {
    String factor(String k) => switch (k) {
          'customer_rating' => l.mktFRating,
          'on_time_arrival' => l.mktFOnTime,
          'damage_claims' => l.mktFDamage,
          'acceptance_rate' => l.mktFAccept,
          'photo_compliance' => l.mktFPhotos,
          'vendor_cancellations' => l.mktFCancel,
          'jobs_completed' => l.mktFJobs,
          _ => k,
        };
    return [
      NgCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_tierName(l, _tier),
                style: NgFonts.geist(
                    fontSize: 22, fontWeight: FontWeight.w600, color: c.text)),
            Text(l.mktTierScore('${_score.round()}'),
                style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
            const SizedBox(height: 10),
            NgProgressBar(value: (_score / 100).clamp(0, 1).toDouble()),
            const SizedBox(height: 8),
            Text(l.mktTierBands,
                style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      NgSectionHeader(l.mktTierF),
      const SizedBox(height: 6),
      Text(l.mktFactorNote,
          style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
      const SizedBox(height: 8),
      NgCardList(children: [
        for (final w in _weights)
          NgListRow(
            title: factor('${w['factor']}'),
            trailing: Text('${w['weight']}%',
                style: NgFonts.mono(fontSize: 14, color: c.text)),
          ),
      ]),
    ];
  }
}
