import '../database.dart';

class OrderStaffTable extends SupabaseTable<OrderStaffRow> {
  @override
  String get tableName => 'order_staff';

  @override
  OrderStaffRow createRow(Map<String, dynamic> data) => OrderStaffRow(data);
}

class OrderStaffRow extends SupabaseDataRow {
  OrderStaffRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => OrderStaffTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get staffId => getField<String>('staff_id');
  set staffId(String? value) => setField<String>('staff_id', value);

  double? get salaryAmount => getField<double>('salary_amount');
  set salaryAmount(double? value) => setField<double>('salary_amount', value);

  bool? get isHalfDay => getField<bool>('is_half_day');
  set isHalfDay(bool? value) => setField<bool>('is_half_day', value);

  String? get teamType => getField<String>('team_type');
  set teamType(String? value) => setField<String>('team_type', value);
}
