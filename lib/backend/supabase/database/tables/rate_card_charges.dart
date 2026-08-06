import '../database.dart';

/// Per-card charge heads (Session 4, Part C-2). Live schema confirmed.
class RateCardChargesTable extends SupabaseTable<RateCardChargesRow> {
  @override
  String get tableName => 'rate_card_charges';

  @override
  RateCardChargesRow createRow(Map<String, dynamic> data) =>
      RateCardChargesRow(data);
}

class RateCardChargesRow extends SupabaseDataRow {
  RateCardChargesRow(super.data);

  @override
  SupabaseTable get table => RateCardChargesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get cardId => getField<String>('card_id')!;
  set cardId(String value) => setField<String>('card_id', value);

  String get chargeKey => getField<String>('charge_key')!;
  set chargeKey(String value) => setField<String>('charge_key', value);

  String? get label => getField<String>('label');
  set label(String? value) => setField<String>('label', value);

  /// flat | per_cft | per_km | per_floor | per_trip | percent (free text,
  /// no live catalogue verified beyond 'flat').
  String get unit => getField<String>('unit') ?? 'flat';
  set unit(String value) => setField<String>('unit', value);

  double get rate => getField<double>('rate') ?? 0;
  set rate(double value) => setField<double>('rate', value);

  double get minAmount => getField<double>('min_amount') ?? 0;
  set minAmount(double value) => setField<double>('min_amount', value);

  bool get isOptional => getField<bool>('is_optional') ?? true;
  set isOptional(bool value) => setField<bool>('is_optional', value);

  int get sortOrder => getField<int>('sort_order') ?? 0;
  set sortOrder(int value) => setField<int>('sort_order', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
