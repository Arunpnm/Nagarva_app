import '../database.dart';

class OrderStaffTable extends SupabaseTable<OrderStaffRow> {
  @override
  String get tableName => 'order_staff';

  @override
  OrderStaffRow createRow(Map<String, dynamic> data) => OrderStaffRow(data);
}

class OrderStaffRow extends SupabaseDataRow {
  OrderStaffRow(super.data);

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

  /// Staff-pay brief §4 "Driver tag": the driver premium is a property of
  /// the ASSIGNMENT, not the person — a crew may hold three licensed
  /// drivers and the sheet records who actually drove this job. Enforced
  /// at most once per order by the partial unique index
  /// `order_staff_one_driver_per_order` (order_id WHERE is_driver); the
  /// "at least one" half of the rule lives in the crew sheet's own
  /// validation, since a partial unique index cannot express it.
  bool get isDriver => getField<bool>('is_driver') ?? false;
  set isDriver(bool value) => setField<bool>('is_driver', value);

  /// Staff-pay brief §5: A/C uninstall is a TASK, not a pay tier — an
  /// additive amount on top of the wage, never absorbed into it, so a man
  /// who drove and also uninstalled an A/C earns both and both report
  /// separately.
  double get acAmount => getField<double>('ac_amount') ?? 0;
  set acAmount(double value) => setField<double>('ac_amount', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
