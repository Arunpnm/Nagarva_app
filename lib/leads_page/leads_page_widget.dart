import 'dart:math';

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
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:uuid/uuid.dart';
import 'leads_page_model.dart';
export 'leads_page_model.dart';

/// Same scheme as lead_detail_page_widget.dart's `_generateHexToken` —
/// surveys.token has no working DB default.
String _generateSurveyToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

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
    // Live-test fix brief #2, item 5: every tab below matched a single
    // hand-written status string, and the "Won" tab's string was
    // 'converted' while Convert to Order actually writes 'confirmed' — so
    // won leads never appeared in it. Tabs now match against the canonical
    // value PLUS its known legacy spellings (leadStatusMatchValues), so
    // they are correct whether or not
    // supabase/20260728_lead_status_canonical.sql has been run yet.
    _model.leadsNewOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .inFilter('status', leadStatusMatchValues(kLeadStatusNew)),
    );
    _model.newLeadsList = (_model.leadsNewOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.leadsContactedOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .inFilter('status', leadStatusMatchValues(kLeadStatusFollowUp)),
    );
    _model.contactedLeadsList =
        (_model.leadsContactedOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.leadsQualifiedOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).inFilter('status', [
        ...leadStatusMatchValues(kLeadStatusSurveyDone),
        ...leadStatusMatchValues(kLeadStatusQuoted),
      ]),
    );
    _model.qualifiedLeadsList =
        (_model.leadsQualifiedOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.leadsWonOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .inFilter('status', leadStatusMatchValues(kLeadStatusConfirmed)),
    );
    _model.wonLeadsList = (_model.leadsWonOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.leadsLostOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .inFilter('status', leadStatusMatchValues(kLeadStatusLost)),
    );
    _model.lostLeadsList =
        (_model.leadsLostOut ?? []).toList().cast<LeadsRow>();
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

  // Parity brief Part 4b: LeadDetailPage already had "Request Survey"
  // (see its _requestSurvey) — the missing piece was a quick entry point
  // right on the list card, without needing to open the full detail page
  // first. surveys.lead_id is uuid (matches LeadsRow.id's type).
  bool _generatingSurveyFor(String? leadId) =>
      leadId != null && _model.surveyLinkLoadingLeadId == leadId;

  Future<void> _quickSurveyLink(LeadsRow lead) async {
    if (lead.id == null) return;
    safeSetState(() => _model.surveyLinkLoadingLeadId = lead.id);
    try {
      final row = await SurveysTable().insert({
        'id': const Uuid().v4(),
        'token': _generateSurveyToken(),
        ...OrgScope.stamp(),
        'lead_id': lead.id,
        'customer_name': lead.customer,
        'customer_phone': lead.phone ?? '',
        'from_address': lead.fromCity ?? '',
        'to_address': lead.toCity ?? '',
      });
      // Not Uri.base.origin — that is file:/// inside an APK and throws.
      // See kPublicBaseUrl in lib/config/app_config.dart.
      final link = buildTokenLink('/survey', row.token);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Survey link created'),
          content: SelectableText(link),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                Navigator.of(context).pop();
              },
              child: const Text('Copy & close'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create survey link: $e')),
        );
      }
    } finally {
      if (mounted) safeSetState(() => _model.surveyLinkLoadingLeadId = null);
    }
  }

  final _searchCtrl = TextEditingController();

  /// Filter chips, in the order the redesign shows them. Each maps to one
  /// of the lists [_loadLeads] already fetches — the same buckets the old
  /// tab row used ('contacted' is the follow-up bucket, 'qualified' is
  /// survey done + quoted).
  List<(String, String, List<LeadsRow>)> _filters(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      ('all', l10n.all, _model.allLeadsList),
      ('new', l10n.statusNew, _model.newLeadsList),
      ('contacted', l10n.contacted, _model.contactedLeadsList),
      ('qualified', l10n.qualified, _model.qualifiedLeadsList),
      ('won', l10n.won, _model.wonLeadsList),
      ('lost', l10n.lost, _model.lostLeadsList),
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
      final k = src.isEmpty ? 'Other' : src;
      bySource[k] = (bySource[k] ?? 0) + 1;
    }
    final ranked = bySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(4).toList();
    final rest = ranked.skip(4).fold<int>(0, (s, e) => s + e.value);
    final segs = [
      for (final e in top) (e.key, e.value),
      if (rest > 0) ('Other', rest),
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
          Text('All leads',
              style: NgFonts.geist(fontSize: 13, color: c.mute)),
          const SizedBox(height: 14),
          Row(
            children: [
              stat('Conversion', conv == null ? '—' : '$conv%'),
              const SizedBox(width: 10),
              stat('Open', '$open'),
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
                      message: 'Survey response received',
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
                  Text('Follow-up overdue',
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
                  label: 'Call',
                  icon: Icons.call_rounded,
                  iconColor: c.green,
                  height: 40,
                  onPressed: phone.isEmpty ? null : () => launchURL('tel:$phone'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NgSecondaryButton(
                  label: 'WhatsApp',
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
              // Parity brief Part 4b: quick "Generate Survey Link" right on
              // the card — LeadDetailPage's "Request Survey" covers the
              // detail-page half.
              Expanded(
                child: _generatingSurveyFor(l.id)
                    ? const SizedBox(
                        height: 40,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : NgSecondaryButton(
                        label: 'Survey',
                        icon: Icons.assignment_rounded,
                        iconColor: c.acc,
                        height: 40,
                        onPressed: () => _quickSurveyLink(l),
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
                AppLocalizations.of(context).leadsCrm,
                action: NgPrimaryButton(
                  compact: true,
                  icon: Icons.add_rounded,
                  label: 'New lead',
                  onPressed: () =>
                      context.pushNamed(NewLeadPageWidget.routeName),
                ),
              ),
              const SizedBox(height: 14),
              _statsCard(context),
              const SizedBox(height: 14),
              NgSearchField(
                controller: _searchCtrl,
                hint: 'Name or phone',
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
                            ? 'No leads yet'
                            : 'No leads match',
                        style: NgFonts.geist(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.text),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add an enquiry with New lead and it will show up here.',
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
