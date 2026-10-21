import '/l10n/gen/app_localizations.dart';
import '/backend/supabase/org_scope.dart';
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

class _PlanPageWidgetState extends State<PlanPageWidget> {
  late PlanPageModel _model;

  /// Live usage for the limit bars. Null until counted, so a bar never
  /// shows a zero that was not measured.
  int? _users;
  int? _ordersThisMonth;
  List<SubscriptionPlansRow> _plans = const [];

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PlanPageModel());
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    try {
      final now = DateTime.now();
      final first = DateTime(now.year, now.month).toIso8601String();
      final results = await Future.wait([
        StaffTable().queryRows(queryFn: (q) => OrgScope.read(q)),
        OrdersTable().queryRows(
            queryFn: (q) => OrgScope.read(q).gte('created_at', first)),
        SubscriptionPlansTable().queryRows(
            queryFn: (q) => q.eq('active', true).order('price_inr')),
      ]);
      _users = results[0].length;
      _ordersThisMonth = results[1].length;
      _plans = results[2].cast<SubscriptionPlansRow>();
    } catch (_) {
      // Usage is supplementary: the plan and its limits still render.
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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
                                : 'Active',
                        status: tone),
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
                    session.isTrialExpired
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
    };
    return labels[key] ??
        (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1).replaceAll('_', ' '));
  }

  String _formatDate(DateTime dt) => DateFormat('d MMM yyyy').format(dt);
}
