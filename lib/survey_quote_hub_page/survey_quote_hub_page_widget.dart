import 'package:flutter/material.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/components/share_link_sheet.dart';
import '/config/app_config.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// Survey & Quote standalone (Session 4, Part B4) — was a ComingSoonPage
/// stub ('SurveyComingSoon', `/survey-new`). Distinct from
/// `SurveyQuotePageWidget` (`/survey-quote`), the itemized builder this
/// page's "Start Walk-in Quote" button opens — that page already accepted
/// a nullable `leadId` (used for the lead-linked path from
/// LeadDetailPage), so "start with no lead" needed no change there, only
/// a standalone entry point that calls it with every leadXxx param null.
///
/// Item 12 (17 Aug 2026): the CFT catalogue editor that used to be this
/// page's second tab moved to Settings → Survey & Pricing
/// (`SurveyPricingPage`), alongside the new vehicle/crew slabs editor —
/// per Arun: "a vendor setting up their fleet shouldn't have to know
/// these live in different menus." This page is now just the cross-lead
/// quote list + walk-in entry point; the AppBar's tune icon links to the
/// editors for anyone who looks for them here out of habit.
class SurveyQuoteHubPageWidget extends StatefulWidget {
  const SurveyQuoteHubPageWidget({super.key, this.navLead});

  /// Optional deep-link seed from the lead screen — when set, "Start
  /// Walk-in Quote" pre-fills from that lead instead of starting blank.
  final String? navLead;

  static String routeName = 'SurveyQuoteHubPage';
  static String routePath = '/survey-new';

  @override
  State<SurveyQuoteHubPageWidget> createState() =>
      _SurveyQuoteHubPageWidgetState();
}

class _SurveyQuoteHubPageWidgetState extends State<SurveyQuoteHubPageWidget>
    with RefreshOnPopMixin<SurveyQuoteHubPageWidget> {
  bool _loadingQuotes = true;
  List<QuotationsRow> _quotes = [];
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  @override
  void onPageRefresh() {
    _loadQuotes();
  }

  Future<void> _loadQuotes() async {
    setState(() => _loadingQuotes = true);
    try {
      _quotes = await QuotationsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('created_at', ascending: false),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load quotes: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingQuotes = false);
    }
  }

  void _startWalkIn() {
    context.pushNamed(
      SurveyQuotePageWidget.routeName,
      queryParameters: {
        if (widget.navLead != null)
          'leadId': serializeParam(widget.navLead, ParamType.String),
      }.withoutNulls,
    );
  }

  List<String> get _statuses =>
      _quotes.map((q) => q.status).whereType<String>().toSet().toList()..sort();

  List<QuotationsRow> get _filteredQuotes => _statusFilter == null
      ? _quotes
      : _quotes.where((q) => q.status == _statusFilter).toList();

  NgStatus _quoteTone(String? st) => switch ((st ?? '').toLowerCase()) {
        'accepted' || 'confirmed' => NgStatus.green,
        'rejected' || 'lost' => NgStatus.red,
        'sent' || 'revised' => NgStatus.amber,
        'draft' => NgStatus.blue,
        _ => NgStatus.neutral,
      };

  String _pretty(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _loadQuotes),
      body: _loadingQuotes
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadQuotes,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  NgModuleHeader('Survey & Quote', actions: [
                    // The catalogue editor lives in Settings -> CFT &
                    // packages; the shortcut stays because the surveyor
                    // who notices a missing item is standing here.
                    NgHeaderButtonBox(
                      tooltip: 'CFT & packages',
                      icon: Icons.tune_rounded,
                      onTap: () =>
                          context.pushNamed(SurveyPricingPage.routeName),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Material(
                    color: c.accBtn,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _startWalkIn,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.add_task_rounded,
                                size: 24, color: NgPalette.onAcc),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Walk-in quote',
                                      style: NgFonts.geist(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: NgPalette.onAcc)),
                                  Text('Start a survey without a lead',
                                      style: NgFonts.geist(
                                          fontSize: 12.5,
                                          color: NgPalette.onAcc)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_rounded,
                                color: NgPalette.onAcc),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  NgChipRow(edge: 0, chips: [
                    NgChip(
                      label: 'All',
                      count: _quotes.length,
                      selected: _statusFilter == null,
                      onTap: () => setState(() => _statusFilter = null),
                    ),
                    for (final st in _statuses)
                      NgChip(
                        label: _pretty(st),
                        count: _quotes.where((q) => q.status == st).length,
                        selected: _statusFilter == st,
                        onTap: () => setState(() => _statusFilter = st),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  if (_filteredQuotes.isEmpty)
                    NgCard(
                      child: Text('No quotes yet.',
                          textAlign: TextAlign.center,
                          style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                    )
                  else
                    NgCardList(children: [
                      for (final q in _filteredQuotes) _quoteRow(q),
                    ]),
                ],
              ),
            ),
    );
  }

  Widget _quoteRow(QuotationsRow q) {
    final c = NgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(q.customer ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NgFonts.geist(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: c.text)),
                    ),
                    if ((q.status ?? '').isNotEmpty) ...[
                      const SizedBox(width: 6),
                      NgPill(_pretty(q.status!), status: _quoteTone(q.status)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (q.createdAt != null)
                      DateFormat('d MMM').format(q.createdAt!),
                    if (q.leadId == null) 'walk-in',
                  ].join(' · '),
                  style: NgFonts.mono(fontSize: 12, color: c.mute),
                ),
              ],
            ),
          ),
          Text(functions.inrFull(q.total ?? 0),
              style: NgFonts.geist(
                  fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
          if (q.leadId != null)
            IconButton(
              tooltip: 'Open lead',
              icon: Icon(Icons.person_outline_rounded, size: 19, color: c.mute),
              onPressed: () => context.pushNamed(
                LeadDetailPageWidget.routeName,
                queryParameters: {
                  'leadId': serializeParam(q.leadId, ParamType.String),
                }.withoutNulls,
              ),
            ),
          // Hidden until /quote is actually hosted — see kQuoteLinkHosted.
          if (kQuoteLinkHosted && (q.token ?? '').isNotEmpty)
            IconButton(
              tooltip: 'Share quote link',
              icon: Icon(Icons.share_outlined, size: 19, color: c.mute),
              onPressed: () => ShareLinkSheet.show(
                context,
                title: 'Quote link',
                subtitle: 'Share this quote with the customer.',
                link: buildTokenLink('/quote', q.token!),
                phone: q.phone,
                message:
                    'Hello${(q.customer ?? '').isEmpty ? '' : ' ${q.customer}'}, '
                    'please review your quotation:',
              ),
            ),
          IconButton(
            tooltip: 'Delete quote',
            icon: Icon(Icons.delete_outline_rounded, size: 19, color: c.faint),
            onPressed: () => _deleteQuote(q),
          ),
        ],
      ),
    );
  }

  // Item 11 sweep (16 Aug 2026): canDeleteQuote already existed in
  // soft_delete.dart but was never called anywhere — this hub's quote
  // list was the only real place for it to live.
  Future<void> _deleteQuote(QuotationsRow q) async {
    final deleted = await DeleteAction.run(
      context,
      table: 'quotations',
      id: q.id,
      entityLabel: 'quote',
      check: () => SoftDeleteService.canDeleteQuote(q.id),
      reasonRequired: true,
      onDeleted: _loadQuotes,
    );
    if (deleted) await _loadQuotes();
  }

}
