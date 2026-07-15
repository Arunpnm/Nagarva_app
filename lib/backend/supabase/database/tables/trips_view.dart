import '../database.dart';

class TripsViewTable extends SupabaseTable<TripsViewRow> {
  @override
  String get tableName => 'trips_view';

  @override
  TripsViewRow createRow(Map<String, dynamic> data) => TripsViewRow(data);
}

class TripsViewRow extends SupabaseDataRow {
  TripsViewRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => TripsViewTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get vehicleNo => getField<String>('vehicle_no');
  set vehicleNo(String? value) => setField<String>('vehicle_no', value);

  String? get driverName => getField<String>('driver_name');
  set driverName(String? value) => setField<String>('driver_name', value);

  String? get fromLoc => getField<String>('from_loc');
  set fromLoc(String? value) => setField<String>('from_loc', value);

  String? get toLoc => getField<String>('to_loc');
  set toLoc(String? value) => setField<String>('to_loc', value);

  double? get kmStart => getField<double>('km_start');
  set kmStart(double? value) => setField<double>('km_start', value);

  double? get kmEnd => getField<double>('km_end');
  set kmEnd(double? value) => setField<double>('km_end', value);

  double? get fuelAmount => getField<double>('fuel_amount');
  set fuelAmount(double? value) => setField<double>('fuel_amount', value);

  double? get tollAmount => getField<double>('toll_amount');
  set tollAmount(double? value) => setField<double>('toll_amount', value);

  double? get driverBata => getField<double>('driver_bata');
  set driverBata(double? value) => setField<double>('driver_bata', value);

  String? get tripDate => getField<String>('trip_date');
  set tripDate(String? value) => setField<String>('trip_date', value);

  String? get tripType => getField<String>('trip_type');
  set tripType(String? value) => setField<String>('trip_type', value);

  String? get note => getField<String>('note');
  set note(String? value) => setField<String>('note', value);

  String? get orderCustomer => getField<String>('order_customer');
  set orderCustomer(String? value) => setField<String>('order_customer', value);
}
