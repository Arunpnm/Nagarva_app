import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/backend/pricing_defaults.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// One line the customer selected on the public survey page.
///
/// `surveys.rooms` is a FLAT array, one entry per selection:
///
///     [{"cat":"Bedrooms","item":"Bed","sub":"Queen Size","cft":55,"qty":2}]
///
/// Total CFT is `sum(cft * qty)`. This shape is owned jointly by the
/// deployed survey page on link.nagarva.in and this file — changing it
/// requires redeploying that page in the same breath, per the handoff
/// brief.
class SurveyLine {
  const SurveyLine({
    required this.cat,
    required this.item,
    required this.sub,
    required this.cft,
    required this.qty,
  });

  final String cat;
  final String item;
  final String sub;
  final num cft;
  final int qty;

  num get lineCft => cft * qty;

  /// Tolerant of numbers arriving as strings — this crosses a jsonb
  /// round-trip from a hand-written JS page, so it is not safe to assume
  /// the browser sent a real number.
  static SurveyLine? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    num asNum(dynamic v, num fallback) =>
        v is num ? v : (num.tryParse('$v') ?? fallback);
    final item = '${raw['item'] ?? ''}'.trim();
    if (item.isEmpty) return null;
    return SurveyLine(
      cat: '${raw['cat'] ?? 'Other'}'.trim(),
      item: item,
      sub: '${raw['sub'] ?? ''}'.trim(),
      cft: asNum(raw['cft'], 0),
      qty: asNum(raw['qty'], 1).toInt(),
    );
  }
}

/// Parses `surveys.rooms` into lines, dropping anything unreadable rather
/// than throwing — a malformed entry must never blank the whole card.
List<SurveyLine> parseSurveyRooms(dynamic rooms) {
  if (rooms is! List) return const [];
  final out = <SurveyLine>[];
  for (final r in rooms) {
    final line = SurveyLine.tryParse(r);
    if (line != null && line.qty > 0) out.add(line);
  }
  return out;
}

num surveyTotalCft(List<SurveyLine> lines) =>
    lines.fold<num>(0, (s, l) => s + l.lineCft);

/// Groups lines by category, preserving first-seen category order so the
/// vendor reads them in the order the customer filled them in.
Map<String, List<SurveyLine>> groupSurveyLines(List<SurveyLine> lines) {
  final out = <String, List<SurveyLine>>{};
  for (final l in lines) {
    out.putIfAbsent(l.cat, () => []).add(l);
  }
  return out;
}

/// What the customer actually submitted, rendered for the vendor.
///
/// Before this, a submitted survey showed only "Survey response received"
/// — the items the customer had gone to the trouble of listing were
/// invisible in the app, so the feature delivered nothing.
class SurveyResponseSection extends StatefulWidget {
  const SurveyResponseSection({
    super.key,
    required this.survey,
    this.onBuildQuote,
  });

  final SurveysRow survey;

  /// "Build quote from this survey" — wired by the host page so the
  /// vendor doesn't re-key what the customer already entered.
  final VoidCallback? onBuildQuote;

  @override
  State<SurveyResponseSection> createState() => _SurveyResponseSectionState();
}

class _SurveyResponseSectionState extends State<SurveyResponseSection> {
  PricingConfig? _config;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    // Only needed for the suggested package/vehicle line; the item list
    // renders without it.
    PricingConfig.loadForCurrentOrg().then((c) {
      if (mounted) setState(() => _config = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final lines = parseSurveyRooms(widget.survey.rooms);
    final totalCft = surveyTotalCft(lines);
    final grouped = groupSurveyLines(lines);
    final instructions = (widget.survey.specialInstructions ?? '').trim();

    final pkg = (_config == null || totalCft <= 0)
        ? null
        : packageInfoForCft(totalCft, _config!.cftRanges, _config!.packages);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.tertiary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_turned_in, size: 18, color: theme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CUSTOMER SURVEY',
                  style: GoogleFonts.interTight(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: 0.4,
                    color: theme.primaryText,
                  ),
                ),
              ),
              if (widget.survey.submittedAt != null)
                Text(
                  DateFormat('d MMM, h:mm a')
                      .format(widget.survey.submittedAt!.toLocal()),
                  style: GoogleFonts.inter(
                      fontSize: 11, color: theme.secondaryText),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (lines.isEmpty)
            Text(
              'The customer submitted the survey without selecting any '
              'items. Worth a call before quoting.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
                color: theme.secondaryText,
              ),
            )
          else ...[
            // Headline the two numbers a vendor actually acts on.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$totalCft CFT  ·  ${lines.length} item'
                    '${lines.length == 1 ? '' : 's'}',
                    style: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: theme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pkg == null
                        ? 'Suggested package unavailable'
                        : 'Suggested: ${pkg.type} · ${pkg.crew} crew · '
                            '${pkg.vehicle}',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18, color: theme.primary),
                    const SizedBox(width: 4),
                    Text(
                      _expanded ? 'Hide items' : 'Show items',
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: theme.primary),
                    ),
                  ],
                ),
              ),
            ),

            if (_expanded)
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: theme.primary,
                          ),
                        ),
                      ),
                      Text(
                        '${surveyTotalCft(entry.value)} CFT',
                        style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: theme.secondaryText),
                      ),
                    ],
                  ),
                ),
                for (final l in entry.value) _line(theme, l),
              ],
          ],

          if (instructions.isNotEmpty) ...[
            const Divider(height: 22),
            Text(
              'Customer notes',
              style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: theme.primaryText),
            ),
            const SizedBox(height: 4),
            Text(
              instructions,
              style: GoogleFonts.inter(
                  fontSize: 13, height: 1.4, color: theme.primaryText),
            ),
          ],

          if (widget.onBuildQuote != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: widget.onBuildQuote,
                icon: const Icon(Icons.calculate, size: 19),
                label: const Text('Build quote from this survey'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(FlutterFlowTheme theme, SurveyLine l) {
    final name = [
      l.item,
      if (l.sub.isNotEmpty && l.sub != 'Qty') l.sub,
    ].join(' — ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '$name${l.qty > 1 ? '  ×${l.qty}' : ''}',
              style: GoogleFonts.inter(
                  fontSize: 12.5, color: theme.primaryText),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l.cft <= 0 ? 'no CFT' : '${l.lineCft} CFT',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: l.cft <= 0 ? theme.warning : theme.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
