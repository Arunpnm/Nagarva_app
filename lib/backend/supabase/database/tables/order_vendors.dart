import '../database.dart';

/// Links a vendor to an order for a specific sub-contracted service
/// (Session 4, Part C-6). orders.id is TEXT — order_id here is text too.
class OrderVendorsTable extends SupabaseTable<OrderVendorsRow> {
  @override
  String get tableName => 'order_vendors';

  @override
  OrderVendorsRow createRow(Map<String, dynamic> data) => OrderVendorsRow(data);
}

class OrderVendorsRow extends SupabaseDataRow {
  OrderVendorsRow(super.data);

  @override
  SupabaseTable get table => OrderVendorsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get vendorId => getField<String>('vendor_id');
  set vendorId(String? value) => setField<String>('vendor_id', value);

  String? get serviceType => getField<String>('service_type');
  set serviceType(String? value) => setField<String>('service_type', value);

  double? get agreedAmount => getField<double>('agreed_amount');
  set agreedAmount(double? value) => setField<double>('agreed_amount', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
