import 'dart:async';

import '/backend/soft_delete.dart';
import 'database.dart';

abstract class SupabaseTable<T extends SupabaseDataRow> {
  String get tableName;
  T createRow(Map<String, dynamic> data);

  /// Materials/Staff/Fleet hang investigation (7 Aug 2026): none of
  /// `queryRows`'s callers ever bounded the wait — a request that never
  /// gets a server response (dropped connection, an auth-token-refresh
  /// collision, anything) just sits on `await` forever, with nothing to
  /// surface. Every page built on this helper was one bad network moment
  /// away from the same silent freeze; this isn't a fix for whatever is
  /// actually causing that (still being tracked down against a live
  /// repro), it just guarantees a stuck request eventually fails loudly
  /// instead of hanging indefinitely. 15s is generous for a handful-of-
  /// rows list query on a normal connection.
  static const _queryTimeout = Duration(seconds: 15);

  /// Soft delete (fix brief #2, item 11) — the read-side half.
  ///
  /// The brief calls this the risky part: "a deleted lead that vanishes
  /// from the list but still counts in dashboard numbers is worse than no
  /// delete at all", and "half-done soft delete is worse than none".
  ///
  /// So the filter is applied HERE, at the one funnel every read already
  /// passes through, rather than at ~40 individual call sites. Every
  /// `queryRows`/`querySingleRow` in the app — lists, dashboard KPIs, P&L
  /// totals, reports, dropdown lookups — gets it automatically, including
  /// queries written in future that nobody remembers to update. It is
  /// applied by TABLE, not by screen, which is what the brief asked for.
  ///
  /// `update`/`delete` deliberately do NOT go through here: they build off
  /// `.from(tableName).update(...)` directly, so restoring a deleted row
  /// still works.
  ///
  /// The ONE read that must bypass this is the recycle bin, which exists
  /// to show deleted rows — see SoftDeleteService.recycleBin, which
  /// queries `SupaFlow.client.from(...)` directly and says so.
  PostgrestFilterBuilder _select() {
    final q = SupaFlow.client.from(tableName).select();
    return kSoftDeleteTables.contains(tableName)
        ? q.isFilter('deleted_at', null)
        : q;
  }

  Future<List<T>> queryRows({
    required PostgrestTransformBuilder Function(PostgrestFilterBuilder) queryFn,
    int? limit,
  }) {
    final select = _select();
    var query = queryFn(select);
    query = limit != null ? query.limit(limit) : query;
    return query
        .select()
        .timeout(_queryTimeout,
            onTimeout: () => throw TimeoutException(
                'Query on "$tableName" took longer than '
                '${_queryTimeout.inSeconds}s — check your connection.'))
        .then((rows) => rows.map(createRow).toList());
  }

  Future<List<T>> querySingleRow({
    required PostgrestTransformBuilder Function(PostgrestFilterBuilder) queryFn,
  }) =>
      queryFn(_select())
          .limit(1)
          .select()
          .maybeSingle()
          .catchError((e) => print('Error querying row: $e'))
          .then((r) => [if (r != null) createRow(r)]);

  Future<T> insert(Map<String, dynamic> data) => SupaFlow.client
      .from(tableName)
      .insert(data)
      .select()
      .limit(1)
      .single()
      .then(createRow);

  /// Upsert — use for any table with a real unique/composite-key constraint
  /// (e.g. `settings`'s `(org_id, key)` primary key added 2026-07-14) instead
  /// of the old "try insert, catch the conflict, fall back to update" dance.
  /// `onConflict` must name the constrained column(s), comma-separated with
  /// no spaces (e.g. `'org_id,key'`), matching Postgrest's expectations.
  Future<T> upsert(
    Map<String, dynamic> data, {
    required String onConflict,
  }) =>
      SupaFlow.client
          .from(tableName)
          .upsert(data, onConflict: onConflict)
          .select()
          .limit(1)
          .single()
          .then(createRow);

  Future<List<T>> update({
    required Map<String, dynamic> data,
    required PostgrestTransformBuilder Function(PostgrestFilterBuilder)
        matchingRows,
    bool returnRows = false,
  }) async {
    final update = matchingRows(SupaFlow.client.from(tableName).update(data));
    if (!returnRows) {
      await update;
      return [];
    }
    return update.select().then((rows) => rows.map(createRow).toList());
  }

  Future<List<T>> delete({
    required PostgrestTransformBuilder Function(PostgrestFilterBuilder)
        matchingRows,
    bool returnRows = false,
  }) async {
    final delete = matchingRows(SupaFlow.client.from(tableName).delete());
    if (!returnRows) {
      await delete;
      return [];
    }
    return delete.select().then((rows) => rows.map(createRow).toList());
  }
}

extension NullSafePostgrestFilters on PostgrestFilterBuilder {
  PostgrestFilterBuilder eqOrNull(String column, dynamic value) {
    return value != null ? eq(column, value) : this;
  }

  PostgrestFilterBuilder neqOrNull(String column, dynamic value) {
    return value != null ? neq(column, value) : this;
  }

  PostgrestFilterBuilder ltOrNull(String column, dynamic value) {
    return value != null ? lt(column, value) : this;
  }

  PostgrestFilterBuilder lteOrNull(String column, dynamic value) {
    return value != null ? lte(column, value) : this;
  }

  PostgrestFilterBuilder gtOrNull(String column, dynamic value) {
    return value != null ? gt(column, value) : this;
  }

  PostgrestFilterBuilder gteOrNull(String column, dynamic value) {
    return value != null ? gte(column, value) : this;
  }

  PostgrestFilterBuilder containsOrNull(String column, dynamic value) {
    return value != null ? contains(column, value) : this;
  }

  PostgrestFilterBuilder overlapsOrNull(String column, dynamic value) {
    return value != null ? overlaps(column, value) : this;
  }

  PostgrestFilterBuilder inFilterOrNull(String column, List<dynamic>? values) {
    return values != null ? inFilter(column, values) : this;
  }
}

extension NullSafeSupabaseStreamFilters on SupabaseStreamFilterBuilder {
  SupabaseStreamBuilder eqOrNull(String column, dynamic value) {
    return value != null ? eq(column, value) : this;
  }

  SupabaseStreamBuilder neqOrNull(String column, dynamic value) {
    return value != null ? neq(column, value) : this;
  }

  SupabaseStreamBuilder ltOrNull(String column, dynamic value) {
    return value != null ? lt(column, value) : this;
  }

  SupabaseStreamBuilder lteOrNull(String column, dynamic value) {
    return value != null ? lte(column, value) : this;
  }

  SupabaseStreamBuilder gtOrNull(String column, dynamic value) {
    return value != null ? gt(column, value) : this;
  }

  SupabaseStreamBuilder gteOrNull(String column, dynamic value) {
    return value != null ? gte(column, value) : this;
  }

  SupabaseStreamBuilder inFilterOrNull(String column, List<Object>? values) {
    return values != null ? inFilter(column, values) : this;
  }
}

class PostgresTime {
  PostgresTime(this.time);
  DateTime? time;

  static PostgresTime? tryParse(String formattedString) {
    final datePrefix = DateTime.now().toIso8601String().split('T').first;
    return PostgresTime(
        DateTime.tryParse('${datePrefix}T$formattedString')?.toLocal());
  }

  String? toIso8601String() {
    return time?.toIso8601String().split('T').last;
  }

  @override
  String toString() {
    return toIso8601String() ?? '';
  }
}
