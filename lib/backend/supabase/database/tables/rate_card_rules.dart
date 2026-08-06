import '../database.dart';

/// Distance/CFT banded pricing rules per card (Session 4, Part C-2). Live
/// schema confirmed.
class RateCardRulesTable extends SupabaseTable<RateCardRulesRow> {
  @override
  String get tableName => 'rate_card_rules';

  @override
  RateCardRulesRow createRow(Map<String, dynamic> data) =>
      RateCardRulesRow(data);
}

class RateCardRulesRow extends SupabaseDataRow {
  RateCardRulesRow(super.data);

  @override
  SupabaseTable get table => RateCardRulesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get cardId => getField<String>('card_id')!;
  set cardId(String value) => setField<String>('card_id', value);

  String get service => getField<String>('service') ?? 'home_shifting';
  set service(String value) => setField<String>('service', value);

  /// local | outstation (free text, no live catalogue verified beyond
  /// 'local').
  String get orderType => getField<String>('order_type') ?? 'local';
  set orderType(String value) => setField<String>('order_type', value);

  double get minKm => getField<double>('min_km') ?? 0;
  set minKm(double value) => setField<double>('min_km', value);

  double? get maxKm => getField<double>('max_km');
  set maxKm(double? value) => setField<double>('max_km', value);

  double get minCft => getField<double>('min_cft') ?? 0;
  set minCft(double value) => setField<double>('min_cft', value);

  double? get maxCft => getField<double>('max_cft');
  set maxCft(double? value) => setField<double>('max_cft', value);

  double get baseAmount => getField<double>('base_amount') ?? 0;
  set baseAmount(double value) => setField<double>('base_amount', value);

  double get perKmRate => getField<double>('per_km_rate') ?? 0;
  set perKmRate(double value) => setField<double>('per_km_rate', value);

  double get perCftRate => getField<double>('per_cft_rate') ?? 0;
  set perCftRate(double value) => setField<double>('per_cft_rate', value);

  double get minCharge => getField<double>('min_charge') ?? 0;
  set minCharge(double value) => setField<double>('min_charge', value);

  String? get vehicleType => getField<String>('vehicle_type');
  set vehicleType(String? value) => setField<String>('vehicle_type', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
