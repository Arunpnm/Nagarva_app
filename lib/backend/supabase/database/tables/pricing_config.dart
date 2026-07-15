import '../database.dart';

class PricingConfigTable extends SupabaseTable<PricingConfigRow> {
  @override
  String get tableName => 'pricing_config';

  @override
  PricingConfigRow createRow(Map<String, dynamic> data) =>
      PricingConfigRow(data);
}

class PricingConfigRow extends SupabaseDataRow {
  PricingConfigRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => PricingConfigTable();

  int? get id => getField<int>('id');
  set id(int? value) => setField<int>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  dynamic? get config => getField<dynamic>('config');
  set config(dynamic? value) => setField<dynamic>('config', value);
}
