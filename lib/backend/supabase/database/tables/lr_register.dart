import '../database.dart';

/// Consignment note register (Session 4, Part C-3). Live schema
/// confirmed directly against the DB. Written to since Session 3 (LR PDF
/// generation, order_documents_section.dart's _genLr) via raw client
/// calls — this is its first generated Dart class, for the new
/// searchable register.
class LrRegisterTable extends SupabaseTable<LrRegisterRow> {
  @override
  String get tableName => 'lr_register';

  @override
  LrRegisterRow createRow(Map<String, dynamic> data) => LrRegisterRow(data);
}

class LrRegisterRow extends SupabaseDataRow {
  LrRegisterRow(super.data);

  @override
  SupabaseTable get table => LrRegisterTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get lrNo => getField<String>('lr_no')!;
  set lrNo(String value) => setField<String>('lr_no', value);

  DateTime? get lrDate => getField<DateTime>('lr_date');
  set lrDate(DateTime? value) => setField<DateTime>('lr_date', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get consignorName => getField<String>('consignor_name');
  set consignorName(String? value) => setField<String>('consignor_name', value);

  String? get consigneeName => getField<String>('consignee_name');
  set consigneeName(String? value) => setField<String>('consignee_name', value);

  String? get consigneePhone => getField<String>('consignee_phone');
  set consigneePhone(String? value) =>
      setField<String>('consignee_phone', value);

  String? get fromPlace => getField<String>('from_place');
  set fromPlace(String? value) => setField<String>('from_place', value);

  String? get toPlace => getField<String>('to_place');
  set toPlace(String? value) => setField<String>('to_place', value);

  int? get packageCount => getField<int>('package_count');
  set packageCount(int? value) => setField<int>('package_count', value);

  double? get freightAmount => getField<double>('freight_amount');
  set freightAmount(double? value) =>
      setField<double>('freight_amount', value);

  /// paid | to_pay | tbb
  String? get freightMode => getField<String>('freight_mode');
  set freightMode(String? value) => setField<String>('freight_mode', value);

  double? get totalAmount => getField<double>('total_amount');
  set totalAmount(double? value) => setField<double>('total_amount', value);

  String? get vehicleNo => getField<String>('vehicle_no');
  set vehicleNo(String? value) => setField<String>('vehicle_no', value);

  String? get driverName => getField<String>('driver_name');
  set driverName(String? value) => setField<String>('driver_name', value);

  /// issued | in_transit | delivered | cancelled
  String get status => getField<String>('status') ?? 'issued';
  set status(String value) => setField<String>('status', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  String? get remarks => getField<String>('remarks');
  set remarks(String? value) => setField<String>('remarks', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get deletedAt => getField<DateTime>('deleted_at');
  set deletedAt(DateTime? value) => setField<DateTime>('deleted_at', value);
}
