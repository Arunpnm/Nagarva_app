import '../database.dart';

/// A vehicle trip, possibly carrying multiple orders (part-load) — distinct
/// from vehicle_trips (1:1 with a single order's odometer capture, see
/// CLAUDE.md's "vehicle_trips vs trips" note). Session 4, Part C-9. Live
/// schema confirmed directly against the DB.
///
/// Only carries `deleted_at`, not `deleted_by`/`delete_reason` — NOT added
/// to kSoftDeleteTables (SoftDeleteService.softDelete writes all three
/// columns and would fail against this table's actual shape). No delete UI
/// offered here; status ('cancelled') is the intended way to retire a trip.
class TripsTable extends SupabaseTable<TripsRow> {
  @override
  String get tableName => 'trips';

  @override
  TripsRow createRow(Map<String, dynamic> data) => TripsRow(data);
}

class TripsRow extends SupabaseDataRow {
  TripsRow(super.data);

  @override
  SupabaseTable get table => TripsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get tripNo => getField<String>('trip_no');
  set tripNo(String? value) => setField<String>('trip_no', value);

  /// own | hired — no live catalogue verified beyond usage, treated as
  /// free text.
  String? get tripType => getField<String>('trip_type');
  set tripType(String? value) => setField<String>('trip_type', value);

  String? get vehicleId => getField<String>('vehicle_id');
  set vehicleId(String? value) => setField<String>('vehicle_id', value);

  String? get vehicleNo => getField<String>('vehicle_no');
  set vehicleNo(String? value) => setField<String>('vehicle_no', value);

  bool get isHired => getField<bool>('is_hired') ?? false;
  set isHired(bool value) => setField<bool>('is_hired', value);

  String? get vendorId => getField<String>('vendor_id');
  set vendorId(String? value) => setField<String>('vendor_id', value);

  double? get hireAmount => getField<double>('hire_amount');
  set hireAmount(double? value) => setField<double>('hire_amount', value);

  String? get driverName => getField<String>('driver_name');
  set driverName(String? value) => setField<String>('driver_name', value);

  String? get driverPhone => getField<String>('driver_phone');
  set driverPhone(String? value) => setField<String>('driver_phone', value);

  String? get fromLoc => getField<String>('from_loc');
  set fromLoc(String? value) => setField<String>('from_loc', value);

  String? get toLoc => getField<String>('to_loc');
  set toLoc(String? value) => setField<String>('to_loc', value);

  DateTime? get startDate => getField<DateTime>('start_date');
  set startDate(DateTime? value) => setField<DateTime>('start_date', value);

  DateTime? get endDate => getField<DateTime>('end_date');
  set endDate(DateTime? value) => setField<DateTime>('end_date', value);

  int? get kmStart => getField<int>('km_start');
  set kmStart(int? value) => setField<int>('km_start', value);

  int? get kmEnd => getField<int>('km_end');
  set kmEnd(int? value) => setField<int>('km_end', value);

  int? get totalKm => getField<int>('total_km');
  set totalKm(int? value) => setField<int>('total_km', value);

  double? get fuelLitres => getField<double>('fuel_litres');
  set fuelLitres(double? value) => setField<double>('fuel_litres', value);

  /// planned | ongoing | completed | cancelled — no live catalogue
  /// verified beyond usage, treated as free text.
  String get status => getField<String>('status') ?? 'planned';
  set status(String value) => setField<String>('status', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);

  DateTime? get deletedAt => getField<DateTime>('deleted_at');
  set deletedAt(DateTime? value) => setField<DateTime>('deleted_at', value);
}
