import 'dart:convert';

import '../database.dart';

class SettingsTable extends SupabaseTable<SettingsRow> {
  @override
  String get tableName => 'settings';

  @override
  SettingsRow createRow(Map<String, dynamic> data) => SettingsRow(data);
}

class SettingsRow extends SupabaseDataRow {
  SettingsRow(super.data);

  @override
  SupabaseTable get table => SettingsTable();

  String get key => getField<String>('key')!;
  set key(String value) => setField<String>('key', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  // `value` is a jsonb column (migrated from text 2026-07-14 via a
  // try_jsonb helper — valid JSON passed through as-is, plain text wrapped
  // as a JSON string). That means legacy numeric-looking values like the
  // invoice sequence counter ('1') or the opening balance ('0') were valid
  // JSON on their own and came through as JSON *numbers*, not JSON strings.
  // A plain `getField<String>('value')` does a strict `as String` cast
  // (see row.dart's `_supaDeserialize` default case) and throws on a
  // non-string JSON value — this coerces any JSON scalar (string, number,
  // bool) to its String form instead of crashing on read.
  /// `value` as a JSON OBJECT, tolerating every shape this column has
  /// held.
  ///
  /// `value` is jsonb, but `BusinessSettingsSection._saveProfile` passed
  /// `jsonEncode(profile)` — a Dart String — so the client serialised it
  /// as a jsonb SCALAR STRING: the column ends up holding
  /// `"{\"invoice_terms\":\"\"}"` rather than an object, and any
  /// `value->>'invoice_terms'` in SQL returns null. The write side is
  /// fixed; this reader has to keep working for rows written before that.
  ///
  /// Three shapes are accepted deliberately:
  ///   * a real jsonb object — what is written from now on;
  ///   * a jsonb string holding JSON — every row written until today;
  ///   * a doubly-encoded string — cheap to absorb, and the failure mode
  ///     if anything else ever re-introduces the same bug.
  ///
  /// Returns null rather than throwing on anything else. A malformed
  /// branding blob must not take out invoice generation — the vendor
  /// loses a footer, not the document.
  ///
  /// **Do not read [value] and `jsonDecode` it by hand.** On a correctly
  /// written object [value] returns Dart's `Map.toString()`
  /// (`{invoice_terms: }`), which is not JSON and throws.
  Map<String, dynamic>? get valueJson {
    dynamic raw = data['value'];
    for (var i = 0; i < 3 && raw != null; i++) {
      if (raw is Map) return Map<String, dynamic>.from(raw);
      if (raw is! String) return null;
      final t = raw.trim();
      if (t.isEmpty) return null;
      try {
        raw = jsonDecode(t);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String? get value {
    final raw = data['value'];
    if (raw == null) return null;
    if (raw is String) return raw;
    // A whole-number double (e.g. 1.0 from some jsonb round-trips) should
    // read back as "1", not "1.0" — the invoice counter and opening
    // balance both do `int.tryParse(value)`, which would silently fail on
    // "1.0" and reset the counter to 0 instead of continuing from 1.
    if (raw is double && raw == raw.roundToDouble()) {
      return raw.toInt().toString();
    }
    return raw.toString();
  }

  set value(String? value) => setField<String>('value', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);
}
