import '../database.dart';

class VehiclesTable extends SupabaseTable<VehiclesRow> {
  @override
  String get tableName => 'vehicles';

  @override
  VehiclesRow createRow(Map<String, dynamic> data) => VehiclesRow(data);
}

class VehiclesRow extends SupabaseDataRow {
  VehiclesRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => VehiclesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get regNo => getField<String>('reg_no')!;
  set regNo(String value) => setField<String>('reg_no', value);

  String? get vehicleType => getField<String>('vehicle_type');
  set vehicleType(String? value) => setField<String>('vehicle_type', value);

  String? get driverName => getField<String>('driver_name');
  set driverName(String? value) => setField<String>('driver_name', value);

  DateTime? get insuranceExpiry => getField<DateTime>('insurance_expiry');
  set insuranceExpiry(DateTime? value) =>
      setField<DateTime>('insurance_expiry', value);

  DateTime? get permitExpiry => getField<DateTime>('permit_expiry');
  set permitExpiry(DateTime? value) =>
      setField<DateTime>('permit_expiry', value);

  DateTime? get lastService => getField<DateTime>('last_service');
  set lastService(DateTime? value) => setField<DateTime>('last_service', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get registration => getField<String>('registration');
  set registration(String? value) => setField<String>('registration', value);

  String? get type => getField<String>('type');
  set type(String? value) => setField<String>('type', value);

  String? get driver => getField<String>('driver');
  set driver(String? value) => setField<String>('driver', value);

  String? get odometer => getField<String>('odometer');
  set odometer(String? value) => setField<String>('odometer', value);
}
