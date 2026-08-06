import '../database.dart';

/// Floor-band charges per card (Session 4, Part C-2). Live schema
/// confirmed.
class RateCardFloorChargesTable extends SupabaseTable<RateCardFloorChargesRow> {
  @override
  String get tableName => 'rate_card_floor_charges';

  @override
  RateCardFloorChargesRow createRow(Map<String, dynamic> data) =>
      RateCardFloorChargesRow(data);
}

class RateCardFloorChargesRow extends SupabaseDataRow {
  RateCardFloorChargesRow(super.data);

  @override
  SupabaseTable get table => RateCardFloorChargesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get cardId => getField<String>('card_id')!;
  set cardId(String value) => setField<String>('card_id', value);

  int get floorFrom => getField<int>('floor_from') ?? 0;
  set floorFrom(int value) => setField<int>('floor_from', value);

  int get floorTo => getField<int>('floor_to') ?? 0;
  set floorTo(int value) => setField<int>('floor_to', value);

  bool get hasLift => getField<bool>('has_lift') ?? false;
  set hasLift(bool value) => setField<bool>('has_lift', value);

  /// flat | per_floor (free text, no live catalogue verified beyond
  /// 'flat').
  String get chargeType => getField<String>('charge_type') ?? 'flat';
  set chargeType(String value) => setField<String>('charge_type', value);

  double get amount => getField<double>('amount') ?? 0;
  set amount(double value) => setField<double>('amount', value);

  int get longCarryM => getField<int>('long_carry_m') ?? 0;
  set longCarryM(int value) => setField<int>('long_carry_m', value);

  double get longCarryRate => getField<double>('long_carry_rate') ?? 0;
  set longCarryRate(double value) => setField<double>('long_carry_rate', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
