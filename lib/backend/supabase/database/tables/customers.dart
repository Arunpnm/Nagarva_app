import '../database.dart';

/// Customers (Session 4, Part C-7). Live schema confirmed directly against
/// the DB. Carries soft-delete columns, now in kSoftDeleteTables.
///
/// `phone_normalized` is a DB-generated column (see CustomerLookup's own
/// doc comment) — exposed here as a read-only getter, deliberately no
/// setter, so it can never be hand-written by a client insert/update.
class CustomersTable extends SupabaseTable<CustomersRow> {
  @override
  String get tableName => 'customers';

  @override
  CustomersRow createRow(Map<String, dynamic> data) => CustomersRow(data);
}

class CustomersRow extends SupabaseDataRow {
  CustomersRow(super.data);

  @override
  SupabaseTable get table => CustomersTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  /// individual | corporate — no live catalogue verified beyond usage,
  /// treated as free text.
  String get customerType => getField<String>('customer_type') ?? 'individual';
  set customerType(String value) => setField<String>('customer_type', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String? get companyName => getField<String>('company_name');
  set companyName(String? value) => setField<String>('company_name', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  /// Read-only — DB-generated from `phone`. See class doc comment.
  String? get phoneNormalized => getField<String>('phone_normalized');

  String? get altPhone => getField<String>('alt_phone');
  set altPhone(String? value) => setField<String>('alt_phone', value);

  String? get email => getField<String>('email');
  set email(String? value) => setField<String>('email', value);

  String? get gstin => getField<String>('gstin');
  set gstin(String? value) => setField<String>('gstin', value);

  String? get pan => getField<String>('pan');
  set pan(String? value) => setField<String>('pan', value);

  String? get billingAddress => getField<String>('billing_address');
  set billingAddress(String? value) => setField<String>('billing_address', value);

  String? get city => getField<String>('city');
  set city(String? value) => setField<String>('city', value);

  String? get state => getField<String>('state');
  set state(String? value) => setField<String>('state', value);

  String? get pincode => getField<String>('pincode');
  set pincode(String? value) => setField<String>('pincode', value);

  String? get source => getField<String>('source');
  set source(String? value) => setField<String>('source', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  double? get creditLimit => getField<double>('credit_limit');
  set creditLimit(double? value) => setField<double>('credit_limit', value);

  int? get creditDays => getField<int>('credit_days');
  set creditDays(int? value) => setField<int>('credit_days', value);

  String? get rateCardId => getField<String>('rate_card_id');
  set rateCardId(String? value) => setField<String>('rate_card_id', value);

  bool get isBlacklisted => getField<bool>('is_blacklisted') ?? false;
  set isBlacklisted(bool value) => setField<bool>('is_blacklisted', value);

  String? get blacklistReason => getField<String>('blacklist_reason');
  set blacklistReason(String? value) => setField<String>('blacklist_reason', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get customerSince => getField<DateTime>('customer_since');
  set customerSince(DateTime? value) => setField<DateTime>('customer_since', value);

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
