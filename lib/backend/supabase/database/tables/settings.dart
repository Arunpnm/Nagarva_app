import '../database.dart';

class SettingsTable extends SupabaseTable<SettingsRow> {
  @override
  String get tableName => 'settings';

  @override
  SettingsRow createRow(Map<String, dynamic> data) => SettingsRow(data);
}

class SettingsRow extends SupabaseDataRow {
  SettingsRow(Map<String, dynamic> data) : super(data);

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
