import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/pricing_defaults.dart';
import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/components/pdf_branding.dart';
import '/components/share_link_sheet.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text('Survey & Quote',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        actions: [
          // The catalogue editor moved to Settings -> Survey & Pricing
          // (Item 12). This shortcut stays because the surveyor who
          // notices a missing item is standing in this screen, not in
          // Settings.
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Survey & Pricing settings',
            onPressed: () => context.pushNamed(SurveyPricingPage.routeName),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startWalkIn,
        icon: const Icon(Icons.add),
        label: const Text('Walk-in Quote'),
      ),
      body: _quotesTab(theme),
    );
  }

  Widget _quotesTab(FlutterFlowTheme theme) {
    if (_loadingQuotes) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadQuotes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          if (_statuses.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _statusFilter == null,
                  onSelected: (_) => setState(() => _statusFilter = null),
                ),
                for (final s in _statuses)
                  ChoiceChip(
                    label: Text(s),
                    selected: _statusFilter == s,
                    onSelected: (_) => setState(() => _statusFilter = s),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          if (_filteredQuotes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('No quotes yet.',
                  style: GoogleFonts.inter(color: theme.secondaryText)),
            )
          else
            for (final q in _filteredQuotes) _quoteRow(theme, q),
        ],
      ),
    );
  }

  Widget _quoteRow(FlutterFlowTheme theme, QuotationsRow q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.customer ?? '—',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  [
                    if ((q.status ?? '').isNotEmpty) q.status,
                    if (q.createdAt != null) DateFormat('d MMM yyyy').format(q.createdAt!),
                  ].whereType<String>().join(' · '),
                  style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                ),
              ],
            ),
          ),
          Text(PdfBranding.rupees(q.total ?? 0),
              style: GoogleFonts.interTight(fontWeight: FontWeight.w700, fontSize: 13.5)),
          if (q.leadId != null)
            IconButton(
              tooltip: 'Open Lead',
              icon: const Icon(Icons.person_outline, size: 18),
              onPressed: () => context.pushNamed(
                LeadDetailPageWidget.routeName,
                queryParameters: {
                  'leadId': serializeParam(q.leadId, ParamType.String),
                }.withoutNulls,
              ),
            ),
          if ((q.token ?? '').isNotEmpty)
            IconButton(
              tooltip: 'Share quote link',
              icon: const Icon(Icons.share, size: 18),
              onPressed: () => ShareLinkSheet.show(
                context,
                title: 'Quote link',
                subtitle: 'Share this quote with the customer.',
                link: buildTokenLink('/quote', q.token!),
                phone: q.phone,
                message: 'Hello${(q.customer ?? '').isEmpty ? '' : ' ${q.customer}'}, '
                    'please review your quotation:',
              ),
            ),
          IconButton(
            tooltip: 'Delete quote',
            icon: Icon(Icons.delete_outline, size: 18, color: theme.error),
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
