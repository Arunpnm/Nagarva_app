import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'customer_survey_detail_sheet.dart';

/// Customer Surveys (Session 4, Part B1) — was a ComingSoonPage stub.
/// `customer_surveys` (29 columns, live schema confirmed directly against
/// the DB) — see customer_surveys.dart's own doc comment for the shape
/// differences from `surveys` (the other, lead-linked survey table).
class CustomerSurveysPageWidget extends StatefulWidget {
  const CustomerSurveysPageWidget({super.key});

  static String routeName = 'CustomerSurveysPage';
  static String routePath = '/surveys';

  @override
  State<CustomerSurveysPageWidget> createState() =>
      _CustomerSurveysPageWidgetState();
}

class _CustomerSurveysPageWidgetState extends State<CustomerSurveysPageWidget>
    with RefreshOnPopMixin<CustomerSurveysPageWidget> {
  bool _loading = true;
  List<CustomerSurveysRow> _surveys = [];
  Map<String, String> _leadNames = {};
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _surveys = await CustomerSurveysTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('created_at', ascending: false),
      );
      final leadIds =
          _surveys.map((s) => s.leadId).whereType<String>().toSet().toList();
      if (leadIds.isNotEmpty) {
        final leads = await LeadsTable().queryRows(
          queryFn: (q) => OrgScope.read(q).inFilter('id', leadIds),
        );
        _leadNames = {for (final l in leads) l.id!: l.customer};
      } else {
        _leadNames = {};
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load surveys: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail(CustomerSurveysRow s) async {
    if (s.id == null) return;
    final changed = await showCustomerSurveyDetailSheet(context, s.id!);
    if (changed == true) _load();
  }

  List<String> get _statuses =>
      _surveys.map((s) => s.status).toSet().toList()..sort();

  List<CustomerSurveysRow> get _filtered => _statusFilter == null
      ? _surveys
      : _surveys.where((s) => s.status == _statusFilter).toList();

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text('Customer Surveys',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
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
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('No customer surveys yet.',
                          style: GoogleFonts.inter(color: theme.secondaryText)),
                    )
                  else
                    for (final s in _filtered) _surveyRow(theme, s),
                ],
              ),
            ),
    );
  }

  Widget _surveyRow(FlutterFlowTheme theme, CustomerSurveysRow s) {
    final leadName = s.leadId != null ? _leadNames[s.leadId] : null;
    return InkWell(
      onTap: () => _openDetail(s),
      borderRadius: BorderRadius.circular(10),
      child: Container(
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
                  Text(s.customerName ?? 'Unnamed',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    [
                      s.submittedAt == null
                          ? 'Not submitted'
                          : DateFormat('d MMM yyyy').format(s.submittedAt!),
                      if (leadName != null) 'Lead: $leadName',
                    ].join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(s.status,
                  style: GoogleFonts.inter(fontSize: 10.5, color: theme.primary)),
            ),
          ],
        ),
      ),
    );
  }
}
