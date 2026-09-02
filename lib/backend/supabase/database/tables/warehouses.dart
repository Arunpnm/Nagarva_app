import '../database.dart';

/// Warehouses / godowns a vendor stores customer goods in.
///
/// Columns verified directly against the live schema (2 Sep 2026), not
/// assumed from a brief. `deleted_at` exists but there is no
/// `deleted_by`/`delete_reason` pair, and 'warehouses' is deliberately NOT
/// in kSoftDeleteTables — see soft_delete.dart. Deactivate with [active]
/// rather than deleting: a warehouse referenced by a closed storage job is
/// part of that job's history.
class WarehousesTable extends SupabaseTable<WarehousesRow> {
  @override
  String get tableName => 'warehouses';

  @override
  WarehousesRow createRow(Map<String, dynamic> data) => WarehousesRow(data);
}

class WarehousesRow extends SupabaseDataRow {
  WarehousesRow(super.data);

  @override
  SupabaseTable get table => WarehousesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  /// Short code the vendor uses on paperwork (e.g. 'CHN-1').
  String? get code => getField<String>('code');
  set code(String? value) => setField<String>('code', value);

  String? get address => getField<String>('address');
  set address(String? value) => setField<String>('address', value);

  /// Storage rates are set per CITY (brief §38), so this is the field the
  /// rate lookup keys on — not an incidental address part.
  String? get city => getField<String>('city');
  set city(String? value) => setField<String>('city', value);

  String? get pincode => getField<String>('pincode');
  set pincode(String? value) => setField<String>('pincode', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  /// Total capacity. Used to show how full a warehouse is against the
  /// CFT of the stays currently in it.
  double? get capacityCft => getField<double>('capacity_cft');
  set capacityCft(double? value) => setField<double>('capacity_cft', value);

  String? get contactPerson => getField<String>('contact_person');
  set contactPerson(String? value) => setField<String>('contact_person', value);

  String? get contactPhone => getField<String>('contact_phone');
  set contactPhone(String? value) => setField<String>('contact_phone', value);

  /// Set when the space is rented from a third party rather than owned.
  String? get vendorId => getField<String>('vendor_id');
  set vendorId(String? value) => setField<String>('vendor_id', value);

  bool get active => getField<bool>('active') ?? true;
  set active(bool value) => setField<bool>('active', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get deletedAt => getField<DateTime>('deleted_at');
  set deletedAt(DateTime? value) => setField<DateTime>('deleted_at', value);
}
