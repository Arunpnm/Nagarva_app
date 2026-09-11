import '../database.dart';

/// Quote revision history — one row per version of a quotation.
///
/// Created by `supabase/nagarva_migration_004_*`; given its only writer
/// on 11 Sept 2026 by `supabase/20260911_revise_quote_rpc.sql`.
///
/// THE ONLY WRITER IS `revise_quote()`, AND THAT IS THE POINT. Nothing
/// in Dart inserts here — a client-supplied diff would be a second
/// account of the same event, free to disagree with the values it
/// describes. The RPC computes [changedFields] and [changeSummary]
/// server-side from the snapshot it is given and the snapshot it
/// replaces. Read this table; never write it.
///
/// HISTORY IS LAZY, so an empty result means "never revised", NOT
/// "history lost". `quote_versions` had zero rows for every live quote
/// because migration 004's backfill ran when no quotations existed. The
/// first revision of any quote therefore captures the CURRENT row as
/// version 1 before writing the revision as version 2 — otherwise the
/// state the customer was originally sent would be unrecoverable and
/// history would begin at v2 with nothing to diff against.
///
/// Pairs with `quotations.version`, which is where the quote is NOW.
class QuoteVersionsTable extends SupabaseTable<QuoteVersionsRow> {
  @override
  String get tableName => 'quote_versions';

  @override
  QuoteVersionsRow createRow(Map<String, dynamic> data) =>
      QuoteVersionsRow(data);
}

class QuoteVersionsRow extends SupabaseDataRow {
  QuoteVersionsRow(super.data);

  @override
  SupabaseTable get table => QuoteVersionsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  /// TEXT, matching `quotations.id` — not a uuid column.
  String? get quoteId => getField<String>('quote_id');
  set quoteId(String? value) => setField<String>('quote_id', value);

  /// 1 is the original quote, captured lazily at the first revision.
  /// The first REVISION is therefore always 2, never 1.
  int? get version => getField<int>('version');
  set version(int? value) => setField<int>('version', value);

  /// The complete quotation row as it stood at this version. Server-set:
  /// version 1 holds `to_jsonb(quotations)`, later versions hold the
  /// snapshot the caller submitted.
  dynamic get snapshot => getField<dynamic>('snapshot');
  set snapshot(dynamic value) => setField<dynamic>('snapshot', value);

  /// Human-readable, computed server-side — e.g.
  /// "Total 45000.00 -> 47500.00 (3 fields changed)". When a reason was
  /// given it is appended after " -- ", so this single field carries
  /// both what changed and why.
  String? get changeSummary => getField<String>('change_summary');
  set changeSummary(String? value) =>
      setField<String>('change_summary', value);

  /// Keys whose values differ from the previous version. `version`,
  /// `status`, `created_at` and `updated_at` are excluded, so a revision
  /// never reports itself as a change.
  List<String>? get changedFields => getListField<String>('changed_fields');
  set changedFields(List<String>? value) =>
      setListField<String>('changed_fields', value);

  double? get totalAmount => getField<double>('total_amount');
  set totalAmount(double? value) => setField<double>('total_amount', value);

  /// `auth.uid()` as text, server-derived — NOT a name.
  ///
  /// A name cannot be resolved server-side (every staff row still has
  /// `auth_user_id = NULL`) and a client-supplied one would be forgeable,
  /// which is worthless in the dispute a version history exists to
  /// settle. Same position as `audit_row()`. Populating
  /// `staff.auth_user_id` at PIN login resolves this retroactively for
  /// every row already written.
  String? get createdBy => getField<String>('created_by');
  set createdBy(String? value) => setField<String>('created_by', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
