import '/config/app_config.dart';
import '/backend/lead_status.dart';
import '/backend/reminders_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/backend/detail_navigation.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'leads_page_model.dart';
export 'leads_page_model.dart';

/// CRM lead pipeline for Arun Packers.
class LeadsPageWidget extends StatefulWidget {
  const LeadsPageWidget({super.key});

  static String routeName = 'LeadsPage';
  static String routePath = '/leads';

  @override
  State<LeadsPageWidget> createState() => _LeadsPageWidgetState();
}

class _LeadsPageWidgetState extends State<LeadsPageWidget>
    with RefreshOnPopMixin<LeadsPageWidget> {
  late LeadsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LeadsPageModel());

    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadLeads());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1): re-run on load and every
  // time a pushed route (New/Edit Lead, Lead Detail) is popped back to.
  @override
  void onPageRefresh() => _loadLeads();

  Future<void> _loadLeads() async {
    // Phase 1 multi-tenancy pass: every tab below was unscoped. Requires
    // supabase/phase1_add_org_id.sql to be run first.
    _model.leadsAllOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).order('created_at'),
    );
    _model.leadsList = (_model.leadsAllOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.allLeadsList = (_model.leadsAllOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    // One query, bucketed here by canonicalLeadStatus, so every legacy
    // spelling lands in the right chip whether or not
    // supabase/20260728_lead_status_canonical.sql has run. The chips are
    // the handoff's: the lead pipeline stages themselves.
    List<LeadsRow> only(String k) => _model.allLeadsList
        .where((r) => canonicalLeadStatus(r.status) == k)
        .toList();
    _model.newLeadsList = only(kLeadStatusNew);
    _model.contactedLeadsList = only(kLeadStatusFollowUp);
    _model.qualifiedLeadsList = [
      ...only(kLeadStatusSurveyDone),
      ...only(kLeadStatusQuoted),
    ];
    _model.wonLeadsList = only(kLeadStatusConfirmed);
    _model.lostLeadsList = only(kLeadStatusLost);
    safeSetState(() {});

    // Item 10.5: which leads have an overdue follow-up. One query for the
    // whole list rather than per row.
    final overdue = await RemindersService.overdueEntityIds(kEntityLead);
    if (mounted) safeSetState(() => _overdueLeadIds = overdue);

    // Leads whose customer has actually submitted the survey. Without
    // this a vendor has to open every lead to discover a response came
    // in, which is the difference between the survey link being useful
    // and being ignored. One query for the whole list, not per row.
    try {
      final submitted = await SurveysTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('status', 'submitted'),
      );
      if (mounted) {
        safeSetState(() => _surveyRespondedLeadIds = {
              for (final s in submitted)
                if (s.leadId != null) s.leadId!,
            });
      }
    } catch (_) {
      // Badge is supplemental — never block the list over it.
    }
  }

  /// Lead ids with a submitted customer survey — drives the list badge.
  Set<String> _surveyRespondedLeadIds = {};

  /// Lead ids with at least one overdue reminder — drives the list badge.
  Set<String> _overdueLeadIds = {};

  @override
  void dispose() {
    _model.dispose();
    _searchCtrl.dispose();

    super.dispose();
  }

  final _searchCtrl = TextEditingController();

  /// Filter chips, as the handoff shows them: All, then every pipeline
  /// stage and Lost, each counted from the one list [_loadLeads] fetches.
  List<(String, String, List<LeadsRow>)> _filters(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    List<LeadsRow> only(String k) => _model.allLeadsList
        .where((r) => canonicalLeadStatus(r.status) == k)
        .toList();
    return [
      ('all', l10n.all, _model.allLeadsList),
      for (final k in [...kLeadPipeline, kLeadStatusLost])
        (k, leadStatusLabel(k), only(k)),
    ];
  }

  void _setFilter(String key, List<LeadsRow> rows) {
    _model.leadsFilter = key;
    _model.leadsList = rows.toList().cast<LeadsRow>();
    safeSetState(() {});
  }

  /// Name or phone, case-insensitive, over the current chip's list.
  ///
  /// Reads the chip's bucket fresh rather than `_model.leadsList`, which
  /// [_loadLeads] resets to ALL on every refresh — that left a "Won" chip
  /// highlighted over the full list after returning from a detail page.
  List<LeadsRow> _visibleLeads(BuildContext context) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final rows = _filters(context)
        .firstWhere((f) => f.$1 == _model.leadsFilter,
            orElse: () => _filters(context).first)
        .$3
        .toList();
    if (q.isEmpty) return rows;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return rows.where((l) {
      if (l.customer.toLowerCase().contains(q)) return true;
      final phone = (l.phone ?? '').replaceAll(RegExp(r'\D'), '');
      return digits.isNotEmpty && phone.contains(digits);
    }).toList();
  }

  static String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 30) return '${d.inDays} d ago';
    return DateFormat('d MMM').format(t);
  }

  /// The redesign's statistics card on Leads. Every figure is computed
  /// from rows already loaded — counts per bucket, conversion as won over
  /// all leads, and the lead-source mix from `leads.source`. The handoff's
  /// mock also showed pipeline value and first-reply time; leads carry no
  /// amount and no reply timestamp, so those two are left out rather than
  /// invented (CLAUDE.md: a plausible wrong number is worse than none).
  Widget _statsCard(BuildContext context) {
    final c = NgPalette.of(context);
    final all = _model.allLeadsList;
    final open = _model.newLeadsList.length +
        _model.contactedLeadsList.length +
        _model.qualifiedLeadsList.length;
    final won = _model.wonLeadsList.length;
    final conv = all.isEmpty ? null : (won * 100 / all.length).round();

    final bySource = <String, int>{};
    for (final l in all) {
      final src = (l.source ?? '').trim();
      final k = src.isEmpty ? AppLocalizations.of(context).ngOther : src;
      bySource[k] = (bySource[k] ?? 0) + 1;
    }
    final ranked = bySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(4).toList();
    final rest = ranked.skip(4).fold<int>(0, (s, e) => s + e.value);
    final segs = [
      for (final e in top) (e.key, e.value),
      if (rest > 0) (AppLocalizations.of(context).ngOther, rest),
    ];
    final segColors = [c.acc, c.blue, c.green, c.amber, c.faint];

    Widget stat(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(fontSize: 12, color: c.mute)),
              const SizedBox(height: 3),
              Text(value,
                  style: NgFonts.geist(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: c.text)),
            ],
          ),
        );

    return NgCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).ngAllLeads,
              style: NgFonts.geist(fontSize: 13, color: c.mute)),
          const SizedBox(height: 14),
          Row(
            children: [
              stat(AppLocalizations.of(context).ngConversion, conv == null ? '—' : '$conv%'),
              const SizedBox(width: 10),
              stat(AppLocalizations.of(context).ngOpen, '$open'),
              const SizedBox(width: 10),
              stat(AppLocalizations.of(context).won, '$won'),
            ],
          ),
          if (segs.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (var i = 0; i < segs.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: segs[i].$2,
                        child: ColoredBox(color: segColors[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (var i = 0; i < segs.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: segColors[i],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${segs[i].$1} ${(segs[i].$2 * 100 / all.length).round()}%',
                        style: NgFonts.geist(fontSize: 11.5, color: c.mute),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _leadCard(BuildContext context, LeadsRow l) {
    final c = NgPalette.of(context);
    final tone = leadStatusTone(l.status);
    final st = c.status(tone);
    final phone = (l.phone ?? '').trim();
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => openLeadDetail(context, l),
            child: Row(
              children: [
                NgAvatar(l.customer, status: tone, size: 40),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.customer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.text),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        [
                          if ((l.service ?? '').trim().isNotEmpty)
                            l.service!.trim(),
                          if (phone.isNotEmpty) phone,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(fontSize: 12.5, color: c.mute),
                      ),
                    ],
                  ),
                ),
                // Survey response waiting to be quoted.
                if (_surveyRespondedLeadIds.contains(l.id))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: AppLocalizations.of(context).ngSurveyResponse,
                      child: Icon(Icons.assignment_turned_in_rounded,
                          size: 18, color: c.green),
                    ),
                  ),
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: st.bg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    leadStatusLabel(l.status),
                    style: NgFonts.geist(
                        fontSize: 12, fontWeight: FontWeight.w600, color: st.fg),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Icon(Icons.route_rounded, size: 16, color: c.faint),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${l.fromCity ?? '-'} → ${l.toCity ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(fontSize: 13, color: c.mute),
                ),
              ),
              if (l.createdAt != null) ...[
                Text('  ·  ', style: NgFonts.geist(fontSize: 13, color: c.faint)),
                Text(_ago(l.createdAt),
                    style: NgFonts.geist(fontSize: 13, color: c.mute)),
              ],
            ],
          ),
          // Item 10.5: overdue follow-up, so the list itself shows which
          // leads are going quiet.
          if (_overdueLeadIds.contains(l.id)) ...[
            const SizedBox(height: 11),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.amberBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alarm_rounded, size: 16, color: c.amber),
                  const SizedBox(width: 6),
                  Text(AppLocalizations.of(context).ngFollowUpOverdue,
                      style: NgFonts.geist(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: c.amber)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: NgSecondaryButton(
                  label: AppLocalizations.of(context).ngCall,
                  icon: Icons.call_rounded,
                  iconColor: c.green,
                  height: 40,
                  onPressed: phone.isEmpty ? null : () => launchURL('tel:$phone'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NgSecondaryButton(
                  label: AppLocalizations.of(context).ngWhatsApp,
                  icon: Icons.chat_rounded,
                  iconColor: c.green,
                  height: 40,
                  onPressed: phone.isEmpty
                      ? null
                      : () => launchURL(buildWhatsAppLink(
                          phone: phone, message: 'Hi ${l.customer},')),
                ),
              ),
              const SizedBox(width: 6),
              // Handoff: Call / WhatsApp / Quote. The survey link moved to
              // Lead Details' "Request Survey", where it already lived too.
              Expanded(
                child: NgSecondaryButton(
                  label: AppLocalizations.of(context).ngQuote,
                  icon: Icons.request_quote_outlined,
                  iconColor: c.acc,
                  height: 40,
                  onPressed: () => context.pushNamed(
                    SurveyQuotePageWidget.routeName,
                    queryParameters: {
                      'leadId': serializeParam(l.id, ParamType.String),
                      'leadCustomer':
                          serializeParam(l.customer, ParamType.String),
                      'leadPhone': serializeParam(l.phone, ParamType.String),
                      'leadFromCity':
                          serializeParam(l.fromCity, ParamType.String),
                      'leadToCity': serializeParam(l.toCity, ParamType.String),
                    }.withoutNulls,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final leads = _visibleLeads(context);
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: c.bg,
        // Redesign: the shared top bar, and "New lead" moves from a FAB
        // into the screen header (handoff: each page has its own "new"
        // button in its header).
        appBar: const NgTopBar(),
        body: RefreshIndicator(
          onRefresh: _loadLeads,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              NgScreenTitle(
                AppLocalizations.of(context).leads,
                large: true,
                action: NgPrimaryButton(
                  compact: true,
                  icon: Icons.add_rounded,
                  label: AppLocalizations.of(context).ngNewLead,
                  onPressed: () =>
                      context.pushNamed(NewLeadPageWidget.routeName),
                ),
              ),
              const SizedBox(height: 14),
              _statsCard(context),
              const SizedBox(height: 14),
              NgSearchField(
                controller: _searchCtrl,
                hint: AppLocalizations.of(context).ngNameOrPhone,
                onChanged: (_) => safeSetState(() {}),
              ),
              const SizedBox(height: 14),
              NgChipRow(
                edge: 0,
                chips: [
                  for (final (key, label, rows) in _filters(context))
                    NgChip(
                      label: label,
                      count: rows.length,
                      selected: _model.leadsFilter == key,
                      onTap: () => _setFilter(key, rows),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // Empty state (18 Aug 2026): a brand-new vendor once saw four
              // invented FlutterFlow mockup customers here; an empty list
              // must read as empty.
              if (leads.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                  child: Column(
                    children: [
                      Icon(Icons.person_search_outlined, size: 42, color: c.mute),
                      const SizedBox(height: 12),
                      Text(
                        _searchCtrl.text.trim().isEmpty
                            ? AppLocalizations.of(context).ngNoLeadsYet
                            : AppLocalizations.of(context).ngNoLeadsMatch,
                        style: NgFonts.geist(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.text),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context).ngLeadsEmptyHint,
                        textAlign: TextAlign.center,
                        style: NgFonts.geist(
                            fontSize: 12.5, height: 1.4, color: c.mute),
                      ),
                    ],
                  ),
                )
              else
                for (var i = 0; i < leads.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _leadCard(context, leads[i]),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
