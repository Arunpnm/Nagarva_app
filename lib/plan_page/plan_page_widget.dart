import '/l10n/gen/app_localizations.dart';
import '/backend/edge_function_errors.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/org_session_loader.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
// flutter_flow_widgets.dart (FFButtonWidget) dropped 18 Aug 2026 with the
// dead "Upgrade Plan" button — re-add it when the WhatsApp support CTA
// is wired.
import '/app_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'plan_page_model.dart';
export 'plan_page_model.dart';

class PlanPageWidget extends StatefulWidget {
  const PlanPageWidget({super.key});

  static String routeName = 'PlanPage';
  static String routePath = '/plan';

  @override
  State<PlanPageWidget> createState() => _PlanPageWidgetState();
}

class _PlanPageWidgetState extends State<PlanPageWidget>
    with WidgetsBindingObserver {
  late PlanPageModel _model;

  /// Autopay (11 Nov 2026): what plan-billing last said. Null until it
  /// answers; [_billingReady] stays false when online payment is not set
  /// up, and the page then looks exactly as it did before Autopay.
  Map<String, dynamic>? _sub;
  Map<String, Map<String, dynamic>> _priceByCode = {};
  bool _billingReady = false;
  bool _billingTest = false;

  /// A plan change waiting to take over when the paid month ends
  /// (13 Nov 2026). Null when there is none.
  Map<String, dynamic>? _next;
  bool _billingBusy = false;

  /// Set after the vendor is sent to Razorpay, so coming back to the app
  /// checks the payment without a tap.
  bool _awaitingApproval = false;

  /// Live usage for the limit bars. Null until counted, so a bar never
  /// shows a zero that was not measured.
  int? _users;
  int? _ordersThisMonth;
  List<SubscriptionPlansRow> _plans = const [];

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PlanPageModel());
    WidgetsBinding.instance.addObserver(this);
    _loadUsage();
    _loadBilling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingApproval) {
      _loadBilling();
    }
  }

  /// Only the company owner pays: plan-billing refuses anyone else, and
  /// org_members.role = 'owner' is what it checks. A staff PIN session
  /// never sees the buttons (same owner-only gate as Business settings).
  bool get _isOwner => AppSession.instance.currentStaffId == null;

  Future<Map<String, dynamic>> _billing(Map<String, dynamic> body) async {
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) throw Exception('Please sign in again.');
    final res = await SupaFlow.client.functions
        .invoke('plan-billing', body: {...body, 'org_id': orgId});
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }

  Future<void> _loadBilling() async {
    if (!_isOwner) return;
    try {
      final before = _sub?['status'];
      final data = await _billing({'action': 'status'});
      final plans = (data['plans'] as List?) ?? const [];
      _priceByCode = {
        for (final p in plans)
          if (p is Map) '${p['code']}': Map<String, dynamic>.from(p),
      };
      _sub = data['subscription'] is Map
          ? Map<String, dynamic>.from(data['subscription'] as Map)
          : null;
      _next = data['next'] is Map
          ? Map<String, dynamic>.from(data['next'] as Map)
          : null;
      _billingTest = data['test_mode'] == true;
      _billingReady = true;
      final now = _sub?['status'];
      if ((now == 'active' || now == 'authenticated') &&
          _next?['status'] != 'created') {
        _awaitingApproval = false;
      }
      // A payment (or a stop) moved the company: reload the plan the
      // whole app reads, not just this page.
      if (before != now) await _reloadSessionPlan();
    } catch (_) {
      // Not set up (no keys) or offline: keep the page as it was.
      _billingReady = _billingReady && _sub != null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _reloadSessionPlan() async {
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return;
    try {
      final d = await loadOrgSessionData(orgId);
      AppSession.instance.setOrgOnly(
        orgId: d.orgId,
        limits: d.limits,
        features: d.features,
        planName: d.planName,
        planStatus: d.planStatus,
        trialEndsAt: d.trialEndsAt,
        graceDays: d.graceDays,
        orgActive: d.orgActive,
        trialFallsBackToFree: d.trialFallsBackToFree,
        trialEndedToFree: d.trialEndedToFree,
      );
    } catch (_) {}
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  /// On a trial with more than a day left, Autopay waits for the trial
  /// end before the first charge (plan-billing sets start_at; 12 Nov 2026).
  DateTime? get _trialEnd {
    final s = AppSession.instance;
    final end = s.trialEndsAt;
    if (s.planStatus != 'trial' || end == null) return null;
    return end.isAfter(DateTime.now().add(const Duration(days: 1)))
        ? end
        : null;
  }

  Future<void> _startAutopay(SubscriptionPlansRow p) async {
    final price = _priceByCode[p.code];
    if (price == null) return;
    final total = _inrPaise((price['total_inr'] as num).toDouble());
    final base = _inrPaise((price['price_inr'] as num).toDouble());
    final per = price['billing_period'] == 'annual' ? 'year' : 'month';
    final trialEnd = _trialEnd;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trialEnd == null
            ? 'Pay for ${p.name} with Autopay?'
            : 'Turn on Autopay for ${p.name}?'),
        content: Text(trialEnd == null
            ? '$total a $per ($base + ${price['gst_pct']}% GST).\n\n'
                'You approve UPI Autopay once on the Razorpay page. It is then '
                'charged every $per until you stop it here.'
                '${_billingTest ? '\n\nTest mode: no real money is taken.' : ''}'
            : 'Nothing is charged today. Razorpay takes a ₹5 check and '
                'gives it back.\n\n'
                'Your trial ends on ${_formatDate(trialEnd)}. On that day '
                '$total ($base + ${price['gst_pct']}% GST) is charged, and then '
                'every $per, so ${p.name} continues without a break. Stop it '
                'here any time before then and nothing is charged.'
                '${_billingTest ? '\n\nTest mode: no real money is taken.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _billingBusy = true);
    try {
      final data = await _billing({'action': 'start', 'plan_code': p.code});
      final url = data['short_url'] as String?;
      if (url == null || url.isEmpty) throw Exception();
      _awaitingApproval = true;
      await launchURL(url);
      _say('Finish the approval on the Razorpay page, then come back here.');
      await _loadBilling();
    } catch (e) {
      _say(friendlyError(e));
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  /// Move to another plan. It applies when the month already paid for
  /// ends, never in between (Arun, 13 Nov 2026). Razorpay cannot change
  /// the plan of a UPI Autopay, so the vendor approves a new one whose
  /// first charge is that day; the server stops the old one that day.
  Future<void> _changePlan(SubscriptionPlansRow p) async {
    final price = _priceByCode[p.code];
    if (price == null) return;
    final total = _inrPaise((price['total_inr'] as num).toDouble());
    final base = _inrPaise((price['price_inr'] as num).toDouble());
    final per = price['billing_period'] == 'annual' ? 'year' : 'month';
    final now = _sub?['plan_name'] as String? ?? 'Your plan';
    final until = _paidUntil();
    // Autopay set up during the trial has not charged yet: the swap
    // keeps the same first day, the day the trial ends.
    final notChargedYet = _sub?['status'] == 'authenticated';
    final trialEnd = _trialEnd;
    final String body;
    if (notChargedYet) {
      body = 'Autopay moves from $now to ${p.name}. Nothing is charged '
          'today. Razorpay takes a ₹5 check and gives it back.\n\n'
          '${trialEnd == null ? 'The first payment' : 'On ${_formatDate(trialEnd)}, when your trial ends,'} '
          '${trialEnd == null ? 'is $total' : '$total is charged'} '
          '($base + ${price['gst_pct']}% GST), and then every $per.';
    } else {
      body = '$now stays until ${until ?? 'the end of the month you paid for'}. '
          'From that day ${p.name} starts, at $total a $per '
          '($base + ${price['gst_pct']}% GST).\n\n'
          'You approve a new UPI Autopay on the Razorpay page now. Razorpay '
          'takes a ₹5 check and gives it back. Nothing else is charged '
          'today, and nothing is refunded.';
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.code == _sub?['plan_code']
            ? 'Keep ${p.name}?'
            : 'Change to ${p.name}?'),
        content: Text(
            '$body${_billingTest ? '\n\nTest mode: no real money is taken.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _billingBusy = true);
    try {
      final data = await _billing({'action': 'change', 'plan_code': p.code});
      final url = data['short_url'] as String?;
      if (url != null && url.isNotEmpty) {
        _awaitingApproval = true;
        await launchURL(url);
        _say('Finish the approval on the Razorpay page, then come back here.');
      }
      await _loadBilling();
    } catch (e) {
      _say(friendlyError(e));
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  DateTime? _nextStart() {
    final raw = _next?['starts_at'];
    return raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  }

  Future<void> _stopAutopay() async {
    final until = _paidUntil();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Autopay?'),
        content: Text(until == null
            ? 'No more payments will be taken.'
            : 'No more payments will be taken. Your plan stays until $until.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Autopay')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop Autopay')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _billingBusy = true);
    try {
      await _billing({'action': 'cancel'});
      _say(until == null
          ? 'Autopay stopped.'
          : 'Autopay stopped. Your plan stays until $until.');
      await _loadBilling();
    } catch (e) {
      _say(friendlyError(e));
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  String? _paidUntil() {
    final raw = _sub?['current_period_end'];
    final dt = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
    return dt == null ? null : _formatDate(dt);
  }

  /// Autopay that is set up and taking (or about to take) payments.
  bool get _autopayRunning => const {'authenticated', 'active', 'pending'}
      .contains(_sub?['status']);

  Future<void> _loadUsage() async {
    try {
      final now = DateTime.now();
      final first = DateTime(now.year, now.month).toIso8601String();
      final results = await Future.wait([
        StaffTable().queryRows(queryFn: (q) => OrgScope.read(q)),
        OrdersTable().queryRows(
            queryFn: (q) => OrgScope.read(q).gte('created_at', first)),
        SubscriptionPlansTable().queryRows(
            // Cheapest first (order() is descending by default).
            queryFn: (q) =>
                q.eq('active', true).order('price_inr', ascending: true)),
      ]);
      _users = results[0].length;
      _ordersThisMonth = results[1].length;
      // BUG-019 (3 Nov 2026): the separate "Trial" plan (5 users, 50
      // orders) confused vendors — a trial is now full Pro — so it isn't
      // offered as a plan to pick.
      _plans = results[2]
          .cast<SubscriptionPlansRow>()
          .where((p) => p.code != 'trial')
          .toList();
    } catch (_) {
      // Usage is supplementary: the plan and its limits still render.
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.dispose();
    super.dispose();
  }

  int? _limit(Map limits, String key) {
    final raw = limits[key];
    return raw is int ? raw : (raw as num?)?.toInt();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final session = context.watch<AppSession>();
    final planName = session.planName ?? 'Free Trial';
    final limits = session.planLimits;
    final features = session.planFeatures;
    final trialEnds = session.trialEndsAt;
    final onTrial = session.planStatus == 'trial' && trialEnds != null;
    final expired = session.isTrialExpired;
    final tone = expired
        ? NgStatus.red
        : onTrial
            ? (session.trialDaysRemaining <= 3 ? NgStatus.amber : NgStatus.blue)
            : NgStatus.green;

    Widget usage(String label, int? used, int? max) {
      final unlimited = max == null || max < 0;
      final frac = (used == null || unlimited || max == 0)
          ? 0.0
          : (used / max).clamp(0.0, 1.0);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.inset,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
              const SizedBox(height: 6),
              Text(
                  '${used ?? '—'} / ${unlimited ? 'Unlimited' : max}',
                  style: NgFonts.mono(
                      fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 8),
              NgProgressBar(
                  value: frac,
                  color: frac >= 0.9 ? c.red : c.green,
                  height: 4),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _loadUsage),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          const NgModuleHeader('Plan & billing'),
          const SizedBox(height: 14),
          NgCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    NgIconTile(
                        icon: Icons.workspace_premium_outlined,
                        status: tone,
                        size: 44,
                        iconSize: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(planName,
                              style: NgFonts.geist(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: c.text)),
                          if (session.currentOrgName != null)
                            Text(session.currentOrgName!,
                                style: NgFonts.geist(
                                    fontSize: 12.5, color: c.mute)),
                        ],
                      ),
                    ),
                    NgPill(
                        expired
                            ? 'Ended'
                            : onTrial
                                ? 'Trial'
                                : session.planStatus == 'grace'
                                    ? 'Autopay off'
                                    : 'Active',
                        status: session.planStatus == 'grace'
                            ? NgStatus.amber
                            : tone),
                  ],
                ),
                if (onTrial) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          // A signup Pro trial drops to Free, so say so.
                          session.trialFallsBackToFree
                              ? AppLocalizations.of(context).plTrEnds(
                                  _formatDate(trialEnds),
                                  '${session.trialDaysRemaining.clamp(0, 9999)}')
                              : 'Trial ends ${_formatDate(trialEnds)}',
                          style: NgFonts.geist(fontSize: 13, color: c.mute),
                        ),
                      ),
                      if (!expired)
                        Text(
                            '${session.trialDaysRemaining.clamp(0, 9999)} days left',
                            style: NgFonts.geist(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: c.status(tone).fg)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  NgProgressBar(
                      value: expired
                          ? 0.04
                          : (session.trialDaysRemaining / 30).clamp(0.04, 1.0),
                      color: c.status(tone).fg,
                      height: 4),
                ],
                if (session.trialEndedToFree) ...[
                  const SizedBox(height: 10),
                  Text(AppLocalizations.of(context).plTrEnded,
                      style: NgFonts.geist(
                          fontSize: 13, height: 1.4, color: c.soft)),
                ],
                if (limits.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    usage('Users', _users, _limit(limits, 'max_users')),
                    const SizedBox(width: 8),
                    usage('Orders this month', _ordersThisMonth,
                        _limit(limits, 'max_orders_per_month')),
                  ]),
                ],
              ],
            ),
          ),
          if (_billingReady && _isOwner) ...[
            const SizedBox(height: 10),
            _autopayCard(session),
          ],
          if (features.isNotEmpty) ...[
            _sectionTitle('What your plan includes'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in features.entries)
                  _featureChip(_featureLabel(e.key), e.value == true),
              ],
            ),
          ],
          if (_plans.isNotEmpty) ...[
            _sectionTitle('Plans'),
            for (final p in _plans) ...[
              _planCard(p, isCurrent: p.name == session.planName),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 4),
          // No payment rail yet (Item 31 is on hold), so there is no
          // Upgrade / Renew button: one that answered "coming soon" was a
          // dead end shown to the vendor least willing to tolerate one.
          // WIRE THE WHATSAPP CTA HERE once kNagarvaSupportPhone is set.
          NgCard(
            child: Row(
              children: [
                Icon(Icons.support_agent_outlined, size: 22, color: c.mute),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _billingReady && _isOwner
                        ? 'Need help with your plan or a payment? Contact Nagarva support.'
                        : session.isTrialExpired
                            ? 'Your trial has ended. Contact Nagarva support to activate your plan.'
                            : 'Contact Nagarva support to change your plan.',
                    style: NgFonts.geist(
                        fontSize: 13.5, height: 1.4, color: c.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(SubscriptionPlansRow p, {required bool isCurrent}) {
    final c = NgPalette.of(context);
    final limits = p.limits is Map ? p.limits as Map : const {};
    final features = p.features is Map ? p.features as Map : const {};
    String lim(String key, String unit) {
      final v = _limit(limits, key);
      if (v == null) return '';
      return v < 0 ? 'Unlimited $unit' : '$v $unit';
    }

    final price = p.priceInr ?? 0;
    final session = AppSession.instance;
    final gst = _billingReady ? _priceByCode[p.code] : null;
    // Buy button: owner, online payment set up, a paid plan, and no
    // Autopay already running (changing plan = stop, then pay again).
    // An unfinished approval for another plan is replaced by a new one.
    final canBuy = _isOwner &&
        gst != null &&
        !_autopayRunning &&
        !(_sub?['status'] == 'created' && _sub?['plan_code'] == p.code);
    // Change plan: Autopay is running (paid, or set up in the trial) and
    // this is not simply the plan it already pays for. A plan that is
    // already waiting to start shows its date instead of a button.
    final subPlan = _sub?['plan_code'];
    final subStatus = _sub?['status'];
    final ending = _sub?['ends_at_period_end'] == true;
    final isNext = _next != null && _next!['plan_code'] == p.code;
    final canChange = _isOwner &&
        gst != null &&
        (subStatus == 'active' || subStatus == 'authenticated') &&
        !isNext &&
        (p.code != subPlan || (ending && subStatus == 'active'));
    final lines = [
      lim('max_users', 'users'),
      lim('max_orders_per_month', 'orders a month'),
      for (final e in features.entries)
        if (e.value == true) _featureLabel(e.key as String),
    ].where((x) => x.isNotEmpty).toList();
    return NgCard(
      color: isCurrent ? c.sel : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(children: [
                  Text(p.name ?? '',
                      style: NgFonts.geist(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    const NgPill('Current', status: NgStatus.accent),
                  ],
                  if (isNext) ...[
                    const SizedBox(width: 8),
                    NgPill(
                        _nextStart() == null
                            ? 'Next'
                            : 'From ${_formatDate(_nextStart()!)}',
                        status: NgStatus.blue),
                  ],
                ]),
              ),
              Text(
                  price <= 0
                      ? 'Free'
                      : '${functions.inrFull(price)} / ${p.billingPeriod == 'annual' ? 'year' : 'month'}',
                  style: NgFonts.geist(
                      fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
            ],
          ),
          if (gst != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                    '+ ${gst['gst_pct']}% GST = ${_inrPaise((gst['total_inr'] as num).toDouble())}',
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
              ),
            ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.check_rounded, size: 16, color: c.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(line,
                      style: NgFonts.geist(fontSize: 13.5, color: c.soft)),
                ),
              ]),
            ),
          if (canBuy) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _billingBusy ? null : () => _startAutopay(p),
                icon: const Icon(Icons.autorenew_rounded, size: 18),
                label: Text(isCurrent &&
                        (session.planStatus == 'active' || _trialEnd != null)
                    ? 'Turn on Autopay'
                    : 'Pay with Autopay'),
              ),
            ),
          ],
          if (canChange) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _billingBusy ? null : () => _changePlan(p),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(p.code == subPlan
                    ? 'Keep ${p.name}'
                    : 'Change to ${p.name}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The Autopay state in one card: what is set up, what was paid, what
  /// to do next. Every line is plain words (app rule).
  Widget _autopayCard(AppSession session) {
    final c = NgPalette.of(context);
    final st = _sub?['status'] as String?;
    final until = _paidUntil();
    final amount = _sub?['amount_inr'] is num
        ? _inrPaise((_sub!['amount_inr'] as num).toDouble())
        : null;
    final plan = _sub?['plan_name'] as String? ?? '';
    final endsAtEnd = _sub?['ends_at_period_end'] == true;

    String text;
    NgStatus tone = NgStatus.neutral;
    final buttons = <Widget>[];
    switch (st) {
      case 'created':
        text = 'Autopay for $plan is not approved yet. Open the Razorpay '
            'page to finish, then come back here.';
        tone = NgStatus.amber;
        final url = _sub?['short_url'] as String?;
        if (url != null && url.isNotEmpty) {
          buttons.add(FilledButton(
              onPressed: _billingBusy
                  ? null
                  : () {
                      _awaitingApproval = true;
                      launchURL(url);
                    },
              child: const Text('Open approval page')));
        }
        buttons.add(OutlinedButton(
            onPressed: _billingBusy ? null : _loadBilling,
            child: const Text('Check payment')));
        break;
      case 'authenticated':
        final startRaw = _sub?['starts_at'];
        final DateTime? start = startRaw is String
            ? DateTime.tryParse(startRaw)?.toLocal()
            : null;
        text = start != null && start.isAfter(DateTime.now())
            ? 'Autopay is on for $plan. Nothing is charged during your trial. '
                'The first payment${amount == null ? '' : ' of $amount'} is on '
                '${_formatDate(start)}, when the trial ends.'
            : 'Autopay for $plan is approved. The first payment is on its '
                'way; this page updates when it is received.';
        tone = NgStatus.blue;
        buttons.add(OutlinedButton(
            onPressed: _billingBusy ? null : _loadBilling,
            child: const Text('Check payment')));
        break;
      case 'active' when _next != null:
        final nPlan = _next!['plan_name'] as String? ?? '';
        final nAmount = _next!['amount_inr'] is num
            ? _inrPaise((_next!['amount_inr'] as num).toDouble())
            : null;
        final day = until ?? 'the end of this month';
        if (_next!['status'] == 'created') {
          text = 'Your change to $nPlan is not approved yet. Open the '
              'Razorpay page to finish. $plan stays until $day. If you do '
              'not finish, Autopay stops on that day.';
          tone = NgStatus.amber;
          final url = _next!['short_url'] as String?;
          if (url != null && url.isNotEmpty) {
            buttons.add(FilledButton(
                onPressed: _billingBusy
                    ? null
                    : () {
                        _awaitingApproval = true;
                        launchURL(url);
                      },
                child: const Text('Open approval page')));
          }
          buttons.add(OutlinedButton(
              onPressed: _billingBusy ? null : _loadBilling,
              child: const Text('Check')));
        } else {
          text = '$plan stays until $day. From that day your plan is '
              '$nPlan${nAmount == null ? '' : ', at $nAmount'}, paid by Autopay.';
          tone = NgStatus.green;
        }
        break;
      case 'active':
        text = endsAtEnd
            ? 'Autopay is stopped. $plan stays until ${until ?? 'the end of this month'}.'
            : 'Autopay is on for $plan${amount == null ? '' : ' at $amount'}. '
                'Paid until ${until ?? '—'}.';
        tone = endsAtEnd ? NgStatus.amber : NgStatus.green;
        break;
      case 'pending':
        text = 'The last Autopay payment did not go through. Razorpay will '
            'try again in the next few days; please keep money in the account.';
        tone = NgStatus.amber;
        break;
      default:
        text = session.planStatus == 'grace'
            ? 'Autopay is off. Your plan is paid until ${_formatDate(session.trialEndsAt ?? DateTime.now())}. Pay with Autopay below to keep it.'
            : _trialEnd != null
                ? 'Your trial ends on ${_formatDate(_trialEnd!)}. Turn on '
                    'Autopay now so your plan continues without a break. '
                    'Nothing is charged until the trial ends.'
                : 'Pay for your plan with UPI Autopay: approve once, and it is '
                    'charged every month until you stop it. GST is added to the plan price.';
        tone = session.planStatus == 'grace' ? NgStatus.amber : NgStatus.blue;
    }
    if (_autopayRunning && (!endsAtEnd || _next != null)) {
      buttons.add(TextButton(
          onPressed: _billingBusy ? null : _stopAutopay,
          child: const Text('Stop Autopay')));
    }

    return NgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            NgIconTile(
                icon: Icons.autorenew_rounded, status: tone, size: 36, iconSize: 19),
            const SizedBox(width: 10),
            Text('Autopay',
                style: NgFonts.geist(
                    fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
            const Spacer(),
            if (_billingTest) const NgPill('Test mode', status: NgStatus.amber),
          ]),
          const SizedBox(height: 10),
          Text(text,
              style: NgFonts.geist(fontSize: 13.5, height: 1.4, color: c.soft)),
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Text(title,
            style: NgFonts.geist(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: NgPalette.of(context).text)),
      );

  Widget _featureChip(String label, bool enabled) {
    final c = NgPalette.of(context);
    final s = c.status(enabled ? NgStatus.green : NgStatus.neutral);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(enabled ? Icons.check_rounded : Icons.lock_outline_rounded,
              size: 15, color: s.fg),
          const SizedBox(width: 6),
          Text(label,
              style: NgFonts.geist(
                  fontSize: 13, fontWeight: FontWeight.w500, color: s.fg)),
        ],
      ),
    );
  }

  String _featureLabel(String key) {
    const labels = {
      'whatsapp': 'WhatsApp alerts',
      'reports': 'P&L reports',
      'invoice': 'GST invoice',
      'gst_invoice': 'GST invoice',
      'fleet': 'Fleet tracking',
      'salary': 'Salary & PF',
      'multi_branch': 'Multiple branches',
      'ai_survey': 'AI photo survey',
    };
    return labels[key] ??
        (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1).replaceAll('_', ' '));
  }

  String _formatDate(DateTime dt) => DateFormat('d MMM yyyy').format(dt);

  /// Rupees with paise when there are any: a plan + 18% GST is rarely a
  /// round number (Pro = Rs 3,538.82), and the amount charged must read
  /// exactly as Razorpay shows it -- inrFull rounds to whole rupees.
  String _inrPaise(double amount) {
    final cents = (amount * 100).round();
    final whole = functions.inrFull((cents ~/ 100).toDouble());
    final p = cents % 100;
    return p == 0 ? whole : '$whole.${p.toString().padLeft(2, '0')}';
  }
}
