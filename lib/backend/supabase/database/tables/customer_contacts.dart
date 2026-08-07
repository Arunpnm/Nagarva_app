import '../database.dart';

/// Additional contact persons for a corporate customer (Session 4, Part
/// C-7).
class CustomerContactsTable extends SupabaseTable<CustomerContactsRow> {
  @override
  String get tableName => 'customer_contacts';

  @override
  CustomerContactsRow createRow(Map<String, dynamic> data) =>
      CustomerContactsRow(data);
}

class CustomerContactsRow extends SupabaseDataRow {
  CustomerContactsRow(super.data);

  @override
  SupabaseTable get table => CustomerContactsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String? get designation => getField<String>('designation');
  set designation(String? value) => setField<String>('designation', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  String? get email => getField<String>('email');
  set email(String? value) => setField<String>('email', value);

  bool get isPrimary => getField<bool>('is_primary') ?? false;
  set isPrimary(bool value) => setField<bool>('is_primary', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
