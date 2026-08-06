import '../database.dart';

/// Vendors — subcontractors/suppliers (Session 4, Part C-6). Live schema
/// confirmed directly against the DB. Carries soft-delete columns, now in
/// kSoftDeleteTables.
class VendorsTable extends SupabaseTable<VendorsRow> {
  @override
  String get tableName => 'vendors';

  @override
  VendorsRow createRow(Map<String, dynamic> data) => VendorsRow(data);
}

class VendorsRow extends SupabaseDataRow {
  VendorsRow(super.data);

  @override
  SupabaseTable get table => VendorsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  /// porter | vehicle | packing_material | labour | other — no live
  /// catalogue verified beyond usage, treated as free text.
  String? get vendorType => getField<String>('vendor_type');
  set vendorType(String? value) => setField<String>('vendor_type', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String? get contactPerson => getField<String>('contact_person');
  set contactPerson(String? value) => setField<String>('contact_person', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  String? get email => getField<String>('email');
  set email(String? value) => setField<String>('email', value);

  String? get gstin => getField<String>('gstin');
  set gstin(String? value) => setField<String>('gstin', value);

  String? get pan => getField<String>('pan');
  set pan(String? value) => setField<String>('pan', value);

  String? get address => getField<String>('address');
  set address(String? value) => setField<String>('address', value);

  String? get city => getField<String>('city');
  set city(String? value) => setField<String>('city', value);

  String? get bankName => getField<String>('bank_name');
  set bankName(String? value) => setField<String>('bank_name', value);

  String? get bankAccount => getField<String>('bank_account');
  set bankAccount(String? value) => setField<String>('bank_account', value);

  String? get bankIfsc => getField<String>('bank_ifsc');
  set bankIfsc(String? value) => setField<String>('bank_ifsc', value);

  String? get upiId => getField<String>('upi_id');
  set upiId(String? value) => setField<String>('upi_id', value);

  bool get tdsApplicable => getField<bool>('tds_applicable') ?? false;
  set tdsApplicable(bool value) => setField<bool>('tds_applicable', value);

  String? get tdsSection => getField<String>('tds_section');
  set tdsSection(String? value) => setField<String>('tds_section', value);

  double? get tdsRatePct => getField<double>('tds_rate_pct');
  set tdsRatePct(double? value) => setField<double>('tds_rate_pct', value);

  bool get isUnregistered => getField<bool>('is_unregistered') ?? false;
  set isUnregistered(bool value) => setField<bool>('is_unregistered', value);

  int? get paymentTermsDays => getField<int>('payment_terms_days');
  set paymentTermsDays(int? value) => setField<int>('payment_terms_days', value);

  bool get active => getField<bool>('active') ?? true;
  set active(bool value) => setField<bool>('active', value);

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
