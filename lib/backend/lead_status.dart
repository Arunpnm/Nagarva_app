/// Canonical lead status vocabulary — the single source of truth.
///
/// Live-test fix brief #2, item 5. Before this file the vocabulary was
/// spread across pages and had genuinely drifted apart:
///
///   * `leads_page_widget.dart`'s "Won" tab queried `status = 'converted'`
///   * `lead_detail_page_widget.dart`'s Convert to Order wrote `'confirmed'`
///   * PLReportPage's lead-source conversion rate also reads `'confirmed'`
///
/// so a converted lead was written as `confirmed` and then never appeared
/// in the Won tab that was looking for `converted`. Two spellings of the
/// same state, one of them unreachable. Everything now routes through the
/// constants below, and `supabase/20260728_lead_status_canonical.sql`
/// backfills the legacy spellings.
library;

import 'package:flutter/material.dart';

const String kLeadStatusNew = 'new';
const String kLeadStatusFollowUp = 'follow_up';
const String kLeadStatusSurveyDone = 'survey_done';
const String kLeadStatusQuoted = 'quoted';
const String kLeadStatusConfirmed = 'confirmed';
const String kLeadStatusLost = 'lost';

/// The pipeline, in order. `lost` is deliberately excluded — it is a
/// terminal side-exit, not a stage, and the progress strip renders it as a
/// separate state rather than a sixth step.
const List<String> kLeadPipeline = [
  kLeadStatusNew,
  kLeadStatusFollowUp,
  kLeadStatusSurveyDone,
  kLeadStatusQuoted,
  kLeadStatusConfirmed,
];

/// Legacy spellings still present in the database, mapped to canonical.
/// Reads go through [canonicalLeadStatus] so the app behaves correctly
/// even on rows the backfill migration hasn't touched yet (or if it is
/// never run).
const Map<String, String> _kLegacyAliases = {
  'contacted': kLeadStatusFollowUp,
  'followup': kLeadStatusFollowUp,
  'follow up': kLeadStatusFollowUp,
  'converted': kLeadStatusConfirmed,
  'won': kLeadStatusConfirmed,
  'booked': kLeadStatusConfirmed,
  'survey': kLeadStatusSurveyDone,
  'surveydone': kLeadStatusSurveyDone,
  'quote_sent': kLeadStatusQuoted,
  'quotation_sent': kLeadStatusQuoted,
};

/// Normalises any stored value to one of the canonical constants.
/// Unknown values fall back to [kLeadStatusNew] rather than throwing, so a
/// stray value can never blank out a list page.
String canonicalLeadStatus(String? raw) {
  if (raw == null) return kLeadStatusNew;
  final v = raw.trim().toLowerCase();
  if (v.isEmpty) return kLeadStatusNew;
  if (kLeadPipeline.contains(v) || v == kLeadStatusLost) return v;
  return _kLegacyAliases[v] ?? kLeadStatusNew;
}

/// Every value that should be matched when filtering for [canonical] —
/// the canonical spelling plus any legacy aliases that mean the same
/// thing. Use with `.inFilter('status', leadStatusMatchValues(x))` so list
/// tabs keep working on un-backfilled rows.
List<String> leadStatusMatchValues(String canonical) => [
      canonical,
      ..._kLegacyAliases.entries
          .where((e) => e.value == canonical)
          .map((e) => e.key),
    ];

String leadStatusLabel(String? raw) {
  switch (canonicalLeadStatus(raw)) {
    case kLeadStatusFollowUp:
      return 'Follow Up';
    case kLeadStatusSurveyDone:
      return 'Survey Done';
    case kLeadStatusQuoted:
      return 'Quoted';
    case kLeadStatusConfirmed:
      return 'Confirmed';
    case kLeadStatusLost:
      return 'Lost';
    default:
      return 'New Lead';
  }
}

/// Short label for the cramped progress strip (matches APC's
/// New / Follow Up / Survey / Quoted / Order).
String leadStageShortLabel(String canonical) {
  switch (canonical) {
    case kLeadStatusFollowUp:
      return 'Follow Up';
    case kLeadStatusSurveyDone:
      return 'Survey';
    case kLeadStatusQuoted:
      return 'Quoted';
    case kLeadStatusConfirmed:
      return 'Order';
    default:
      return 'New';
  }
}

Color leadStatusColor(String? raw) {
  switch (canonicalLeadStatus(raw)) {
    case kLeadStatusFollowUp:
      return const Color(0xFFE3B23C); // brand gold
    case kLeadStatusSurveyDone:
      return const Color(0xFF3B82F6);
    case kLeadStatusQuoted:
      return const Color(0xFF8B5CF6);
    case kLeadStatusConfirmed:
      return const Color(0xFF1FA98C); // brand teal
    case kLeadStatusLost:
      return const Color(0xFFEF4444);
    default:
      return const Color(0xFF6B7280);
  }
}

/// Zero-based position in [kLeadPipeline]; -1 for `lost`.
int leadStageIndex(String? raw) {
  final c = canonicalLeadStatus(raw);
  if (c == kLeadStatusLost) return -1;
  return kLeadPipeline.indexOf(c);
}

/// "Never auto-downgrade" (fix brief #2, item 5.2).
///
/// Returns the status the lead should end up in after an event that
/// implies [target], given it is currently [current]. Advancing past a
/// `lost` lead is allowed — reviving a lost lead by quoting it again is a
/// real thing — but a lead already at `confirmed` is never pulled back to
/// `quoted` just because someone re-sent a quote.
String advanceLeadStatus(String? current, String target) {
  final from = canonicalLeadStatus(current);
  final to = canonicalLeadStatus(target);
  if (from == kLeadStatusLost) return to;
  final fromIdx = leadStageIndex(from);
  final toIdx = leadStageIndex(to);
  return toIdx > fromIdx ? to : from;
}
