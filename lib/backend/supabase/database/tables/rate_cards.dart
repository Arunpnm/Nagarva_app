import '../database.dart';

/// Rate cards (Session 4, Part C-2). Live schema confirmed directly
/// against the DB. Soft-delete columns present (deleted_at/deleted_by/
/// delete_reason) but 'rate_cards' is not in kSoftDeleteTables — reads go
/// through the plain OrgScope filter, not the soft-delete one, until it's
/// added there.
class RateCardsTable extends SupabaseTable<RateCardsRow> {
  @override
  String get tableName => 'rate_cards';

  @override
  RateCardsRow createRow(Map<String, dynamic> data) => RateCardsRow(data);
}

class RateCardsRow extends SupabaseDataRow {
  RateCardsRow(super.data);

  @override
  SupabaseTable get table => RateCardsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String? get code => getField<String>('code');
  set code(String? value) => setField<String>('code', value);

  /// standard | custom | corporate (no live catalogue verified beyond
  /// 'standard' — treated as free text).
  String get cardType => getField<String>('card_type') ?? 'standard';
  set cardType(String value) => setField<String>('card_type', value);

  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  DateTime? get validFrom => getField<DateTime>('valid_from');
  set validFrom(DateTime? value) => setField<DateTime>('valid_from', value);

  DateTime? get validTo => getField<DateTime>('valid_to');
  set validTo(DateTime? value) => setField<DateTime>('valid_to', value);

  bool get isDefault => getField<bool>('is_default') ?? false;
  set isDefault(bool value) => setField<bool>('is_default', value);

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
