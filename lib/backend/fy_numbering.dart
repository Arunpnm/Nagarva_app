import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/edge_function_errors.dart';
import '/backend/supabase/supabase.dart';

/// Financial-year numbering (CLAUDE.md, "DEADLINE: MARCH 2027").
///
/// Every number series is scoped to one FY and the allocators RAISE when
/// the requested FY has none, so on 1 April the first document of the
/// year fails. [allocateWithRollover] turns that dead end into a prompt:
/// "2027-28 numbering hasn't been started — start it now?", runs
/// `roll_over_number_series`, and retries once. The Settings card is the
/// deliberate, ahead-of-time path; this is the safety net for whoever
/// forgot. Nothing is created without someone choosing to.

/// Indian financial year as number_series stores it, e.g. `2026-27`.
String currentFy([DateTime? now]) {
  final d = now ?? DateTime.now();
  final y = d.month >= 4 ? d.year : d.year - 1;
  return fyStarting(y);
}

/// The FY that starts in April of [year], e.g. 2027 -> `2027-28`.
String fyStarting(int year) =>
    '$year-${((year + 1) % 100).toString().padLeft(2, '0')}';

/// The FY after [fy] (`2026-27` -> `2027-28`).
String nextFy(String fy) => fyStarting(int.parse(fy.substring(0, 4)) + 1);

/// True for the allocators' "no series for this year" refusal, and for
/// nothing else. Both allocators raise P0001 with a fixed opening; every
/// other P0001 (the order-id guard, plan limits, …) must pass through
/// untouched, or the app would offer to "start the year" for a problem
/// that has nothing to do with numbering.
bool isMissingSeriesError(Object e) {
  if (e is! PostgrestException || e.code != 'P0001') return false;
  final m = e.message.trimLeft();
  return m.startsWith('No active number series') ||
      m.startsWith('No active LR series');
}

/// One row of `roll_over_number_series`' result.
class FyRolloverItem {
  FyRolloverItem(this.raw);
  final Map<String, dynamic> raw;

  String get docType => '${raw['doc_type'] ?? ''}';
  String? get branch => raw['branch'] as String?;

  /// `ready`, `waits`, `exists` or `created`.
  String get status => '${raw['status'] ?? ''}';
  String get firstNumber => '${raw['first'] ?? ''}';

  /// A yearless prefix: continues last year's counter instead of
  /// restarting, and is only created once the year has started.
  bool get continues => raw['continues'] == true;
}

class FyRolloverResult {
  FyRolloverResult(this.raw);
  final Map<String, dynamic> raw;

  String get fromFy => '${raw['from'] ?? ''}';
  String get toFy => '${raw['to'] ?? ''}';
  bool get yearStarted => raw['year_started'] == true;
  int get created => (raw['created'] as num?)?.toInt() ?? 0;
  List<FyRolloverItem> get items => [
        for (final e in (raw['series'] as List? ?? const []))
          FyRolloverItem(Map<String, dynamic>.from(e as Map)),
      ];
}

class FyNumbering {
  /// What starting [toFy] would do, without writing anything.
  static Future<FyRolloverResult> preview(String toFy) => _call(toFy, true);

  /// Create [toFy]'s series. Idempotent; existing ones are left alone.
  static Future<FyRolloverResult> start(String toFy) => _call(toFy, false);

  static Future<FyRolloverResult> _call(String toFy, bool dryRun) async {
    final res = await SupaFlow.client.rpc('roll_over_number_series', params: {
      'p_org': AppSession.instance.currentOrgId,
      'p_to_fy': toFy,
      'p_dry_run': dryRun,
    });
    return FyRolloverResult(Map<String, dynamic>.from(res as Map));
  }
}

/// Runs [allocate]; if it fails only because this FY's series is missing,
/// asks whether to start the year's numbering, does so, and tries once
/// more. Any other error, a "no", or a second failure is rethrown, so the
/// caller's existing error handling still reports it.
Future<T> allocateWithRollover<T>(
  BuildContext context,
  Future<T> Function() allocate,
) async {
  try {
    return await allocate();
  } catch (e) {
    if (!isMissingSeriesError(e) || !context.mounted) rethrow;
    final fy = currentFy();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Start $fy numbering?'),
        content: Text(
          'Numbering for the $fy financial year has not been started yet, '
          'so this document cannot get a number. Starting it carries your '
          'prefixes into $fy: series with the year in them restart at 1, '
          'the others continue from last year.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Start $fy')),
        ],
      ),
    );
    if (go != true) rethrow;
    try {
      await FyNumbering.start(fy);
    } catch (startError) {
      // e.g. a staff session: only the owner or a manager may start it.
      throw Exception(extractDbErrorMessage(startError,
          fallback: 'Could not start $fy numbering: $startError'));
    }
    return await allocate();
  }
}
