import '../database.dart';

/// Seasonal/weekday pricing multipliers per card (Session 4, Part C-2).
/// Live schema confirmed.
class RateCardMultipliersTable extends SupabaseTable<RateCardMultipliersRow> {
  @override
  String get tableName => 'rate_card_multipliers';

  @override
  RateCardMultipliersRow createRow(Map<String, dynamic> data) =>
      RateCardMultipliersRow(data);
}

class RateCardMultipliersRow extends SupabaseDataRow {
  RateCardMultipliersRow(super.data);

  @override
  SupabaseTable get table => RateCardMultipliersTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get cardId => getField<String>('card_id')!;
  set cardId(String value) => setField<String>('card_id', value);

  String? get name => getField<String>('name');
  set name(String? value) => setField<String>('name', value);

  DateTime? get dateFrom => getField<DateTime>('date_from');
  set dateFrom(DateTime? value) => setField<DateTime>('date_from', value);

  DateTime? get dateTo => getField<DateTime>('date_to');
  set dateTo(DateTime? value) => setField<DateTime>('date_to', value);

  /// int[] — 1-7 weekday numbers this multiplier applies to. Empty means
  /// "every day" (no live catalogue verified for the exact convention).
  List<int> get weekdayMask => getListField<int>('weekday_mask');
  set weekdayMask(List<int> value) => setListField<int>('weekday_mask', value);

  double get multiplierPct => getField<double>('multiplier_pct') ?? 100;
  set multiplierPct(double value) => setField<double>('multiplier_pct', value);

  /// total | base | transport (free text, no live catalogue verified
  /// beyond 'total').
  String get appliesTo => getField<String>('applies_to') ?? 'total';
  set appliesTo(String value) => setField<String>('applies_to', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
