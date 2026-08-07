import '../database.dart';

/// Saved addresses for a customer (Session 4, Part C-7) — separate from
/// customers.billing_address, used for repeat-customer pickup/drop presets.
class CustomerAddressesTable extends SupabaseTable<CustomerAddressesRow> {
  @override
  String get tableName => 'customer_addresses';

  @override
  CustomerAddressesRow createRow(Map<String, dynamic> data) =>
      CustomerAddressesRow(data);
}

class CustomerAddressesRow extends SupabaseDataRow {
  CustomerAddressesRow(super.data);

  @override
  SupabaseTable get table => CustomerAddressesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

  String? get label => getField<String>('label');
  set label(String? value) => setField<String>('label', value);

  String? get address => getField<String>('address');
  set address(String? value) => setField<String>('address', value);

  String? get city => getField<String>('city');
  set city(String? value) => setField<String>('city', value);

  int? get floor => getField<int>('floor');
  set floor(int? value) => setField<int>('floor', value);

  bool get hasLift => getField<bool>('has_lift') ?? false;
  set hasLift(bool value) => setField<bool>('has_lift', value);

  String? get pincode => getField<String>('pincode');
  set pincode(String? value) => setField<String>('pincode', value);

  bool get isPrimary => getField<bool>('is_primary') ?? false;
  set isPrimary(bool value) => setField<bool>('is_primary', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
