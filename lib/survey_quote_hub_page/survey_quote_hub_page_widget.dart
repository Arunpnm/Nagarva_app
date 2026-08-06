import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/pricing_defaults.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
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
/// Two more things this brief asked for that had no UI anywhere: a
/// cross-lead quote list (quotations have only ever been reachable one
/// lead at a time, via LeadDetailPage) and CFT catalogue management
/// (`pricing_config.config.survey_cats` has always been Dart-defaults-only
/// or hand-edited in Supabase — no admin screen).
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
    with SingleTickerProviderStateMixin, RefreshOnPopMixin<SurveyQuoteHubPageWidget> {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loadingQuotes = true;
  List<QuotationsRow> _quotes = [];
  String? _statusFilter;

  bool _loadingCatalogue = true;
  Map<String, List<SurveyItem>> _catalogue = {};

  @override
  void initState() {
    super.initState();
    _loadQuotes();
    _loadCatalogue();
  }

  @override
  void onPageRefresh() {
    _loadQuotes();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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

  Future<void> _loadCatalogue() async {
    setState(() => _loadingCatalogue = true);
    try {
      final config = await PricingConfig.loadForCurrentOrg();
      _catalogue = {
        for (final e in config.surveyCats.entries) e.key: List.of(e.value),
      };
    } catch (_) {
      _catalogue = Map.of(kDefaultSurveyCats);
    } finally {
      if (mounted) setState(() => _loadingCatalogue = false);
    }
  }

  Future<void> _saveCatalogue() async {
    try {
      final orgId = OrgScope.currentOrgId!;
      final payload = {
        for (final e in _catalogue.entries)
          e.key: [
            for (final item in e.value)
              {
                'name': item.name,
                'subs': [
                  for (final s in item.subs) {'label': s.label, 'cft': s.cft},
                ],
              },
          ],
      };
      final existing = await PricingConfigTable().queryRows(
        queryFn: (q) => OrgScope.read(q).limit(1),
      );
      final currentConfig = existing.isNotEmpty && existing.first.config is Map
          ? Map<String, dynamic>.from(existing.first.config as Map)
          : <String, dynamic>{};
      currentConfig['survey_cats'] = payload;
      if (existing.isNotEmpty) {
        await PricingConfigTable().update(
          data: {'config': currentConfig},
          matchingRows: (q) => OrgScope.write(q).eq('id', existing.first.id!),
        );
      } else {
        await PricingConfigTable().insert({
          'org_id': orgId,
          'config': currentConfig,
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Catalogue saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save catalogue: $e')));
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
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Quotes'), Tab(text: 'Item Catalogue')],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: _startWalkIn,
              icon: const Icon(Icons.add),
              label: const Text('Walk-in Quote'),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [_quotesTab(theme), _catalogueTab(theme)],
      ),
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
        ],
      ),
    );
  }

  Widget _catalogueTab(FlutterFlowTheme theme) {
    if (_loadingCatalogue) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              for (final cat in _catalogue.keys.toList()) _categoryTile(theme, cat),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final name = await _promptText(context, 'New category name');
                  if (name == null || name.trim().isEmpty) return;
                  setState(() => _catalogue[name.trim()] = []);
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Category'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: _saveCatalogue,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save Catalogue'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryTile(FlutterFlowTheme theme, String cat) {
    final items = _catalogue[cat] ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(cat, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        subtitle: Text('${items.length} item(s)'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () => setState(() => _catalogue.remove(cat)),
        ),
        children: [
          for (var i = 0; i < items.length; i++) _itemTile(theme, cat, i, items[i]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final name = await _promptText(context, 'New item name');
                  if (name == null || name.trim().isEmpty) return;
                  setState(() => _catalogue[cat] = [
                        ...items,
                        SurveyItem(name.trim(), const []),
                      ]);
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Item'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(FlutterFlowTheme theme, String cat, int itemIndex, SurveyItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.name,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: () => setState(() {
                  final list = List.of(_catalogue[cat]!)..removeAt(itemIndex);
                  _catalogue[cat] = list;
                }),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var s = 0; s < item.subs.length; s++)
                InputChip(
                  label: Text('${item.subs[s].label}: ${item.subs[s].cft} cft'),
                  onDeleted: () => setState(() {
                    final subs = List.of(item.subs)..removeAt(s);
                    final list = List.of(_catalogue[cat]!);
                    list[itemIndex] = SurveyItem(item.name, subs);
                    _catalogue[cat] = list;
                  }),
                  onPressed: () async {
                    final result = await _promptSub(context,
                        initialLabel: item.subs[s].label, initialCft: item.subs[s].cft);
                    if (result == null) return;
                    setState(() {
                      final subs = List.of(item.subs);
                      subs[s] = SurveySubItem(result.$1, result.$2);
                      final list = List.of(_catalogue[cat]!);
                      list[itemIndex] = SurveyItem(item.name, subs);
                      _catalogue[cat] = list;
                    });
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 14),
                label: const Text('Add'),
                onPressed: () async {
                  final result = await _promptSub(context);
                  if (result == null) return;
                  setState(() {
                    final subs = [...item.subs, SurveySubItem(result.$1, result.$2)];
                    final list = List.of(_catalogue[cat]!);
                    list[itemIndex] = SurveyItem(item.name, subs);
                    _catalogue[cat] = list;
                  });
                },
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  Future<String?> _promptText(BuildContext context, String label) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        content: TextField(controller: ctrl, decoration: InputDecoration(labelText: label), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<(String, num)?> _promptSub(BuildContext context,
      {String? initialLabel, num? initialCft}) {
    final labelCtrl = TextEditingController(text: initialLabel ?? '');
    final cftCtrl = TextEditingController(text: initialCft?.toString() ?? '');
    return showDialog<(String, num)>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sub-item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Label'),
                autofocus: true),
            TextField(
              controller: cftCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'CFT'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final label = labelCtrl.text.trim();
              final cft = num.tryParse(cftCtrl.text.trim());
              if (label.isEmpty || cft == null) return;
              Navigator.of(context).pop((label, cft));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
