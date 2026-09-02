import '../database.dart';

/// A stay of customer goods in a warehouse.
///
/// Columns verified directly against the live schema (2 Sep 2026).
///
/// A storage job hangs off an ORDER (`order_id`) rather than replacing
/// one: storage is a revenue line inside the order, so the inbound job,
/// the storage period and the outbound delivery all stay on one record
/// chain (brief §37).
///
/// [rate] and [minBillingDays] are SNAPSHOTTED at booking, never read
/// live from a rate card (§44). A vendor raising prices must not re-bill
/// goods already in store, so these columns hold what was agreed on the
/// day and are not pointers.
///
/// Soft-delete columns are all three present here, unlike `warehouses`.
class StorageJobsTable extends SupabaseTable<StorageJobsRow> {
  @override
  String get tableName => 'storage_jobs';

  @override
  StorageJobsRow createRow(Map<String, dynamic> data) => StorageJobsRow(data);
}

class StorageJobsRow extends SupabaseDataRow {
  StorageJobsRow(super.data);

  @override
  SupabaseTable get table => StorageJobsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get jobNo => getField<String>('job_no');
  set jobNo(String? value) => setField<String>('job_no', value);

  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

  /// Text, matching `orders.id`.
  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get warehouseId => getField<String>('warehouse_id');
  set warehouseId(String? value) => setField<String>('warehouse_id', value);

  /// Goods in. Defaults to CURRENT_DATE at the DB.
  DateTime? get inDate => getField<DateTime>('in_date');
  set inDate(DateTime? value) => setField<DateTime>('in_date', value);

  DateTime? get expectedOutDate => getField<DateTime>('expected_out_date');
  set expectedOutDate(DateTime? value) =>
      setField<DateTime>('expected_out_date', value);

  /// Goods out. Null means still in store, which is what makes the charge
  /// an accrual rather than a settled figure.
  DateTime? get outDate => getField<DateTime>('out_date');
  set outDate(DateTime? value) => setField<DateTime>('out_date', value);

  double get totalCft => getField<double>('total_cft') ?? 0;
  set totalCft(double value) => setField<double>('total_cft', value);

  int get packageCount => getField<int>('package_count') ?? 0;
  set packageCount(int value) => setField<int>('package_count', value);

  /// per_day | per_month | custom — see storage_billing.dart. Chosen by the
  /// customer at booking and LOCKED for the stay; never derived from how
  /// long the goods actually stayed.
  String get billingMode => getField<String>('billing_mode') ?? 'per_month';
  set billingMode(String value) => setField<String>('billing_mode', value);

  /// The agreed rate, snapshotted. Per day or per month according to
  /// [billingMode].
  double get rate => getField<double>('rate') ?? 0;
  set rate(double value) => setField<double>('rate', value);

  /// Minimum billable days on the daily plan (vendor default 15).
  int get minBillingDays => getField<int>('min_billing_days') ?? 0;
  set minBillingDays(int value) => setField<int>('min_billing_days', value);

  double get securityDeposit => getField<double>('security_deposit') ?? 0;
  set securityDeposit(double value) =>
      setField<double>('security_deposit', value);

  /// Loading in / unloading out are billed SEPARATELY from rent (§40).
  double get handlingInCharge => getField<double>('handling_in_charge') ?? 0;
  set handlingInCharge(double value) =>
      setField<double>('handling_in_charge', value);

  double get handlingOutCharge => getField<double>('handling_out_charge') ?? 0;
  set handlingOutCharge(double value) =>
      setField<double>('handling_out_charge', value);

  double get declaredValue => getField<double>('declared_value') ?? 0;
  set declaredValue(double value) => setField<double>('declared_value', value);

  String? get insurancePolicyId => getField<String>('insurance_policy_id');
  set insurancePolicyId(String? value) =>
      setField<String>('insurance_policy_id', value);

  /// in_storage | partially_delivered | closed.
  String get status => getField<String>('status') ?? 'in_storage';
  set status(String value) => setField<String>('status', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);

  DateTime? get deletedAt => getField<DateTime>('deleted_at');
  set deletedAt(DateTime? value) => setField<DateTime>('deleted_at', value);

  String? get deletedBy => getField<String>('deleted_by');
  set deletedBy(String? value) => setField<String>('deleted_by', value);

  String? get deleteReason => getField<String>('delete_reason');
  set deleteReason(String? value) => setField<String>('delete_reason', value);
}
