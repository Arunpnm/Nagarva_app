import '../database.dart';

/// Line items (damaged/lost goods) within a claim (Session 4, Part C-8).
class ClaimItemsTable extends SupabaseTable<ClaimItemsRow> {
  @override
  String get tableName => 'claim_items';

  @override
  ClaimItemsRow createRow(Map<String, dynamic> data) => ClaimItemsRow(data);
}

class ClaimItemsRow extends SupabaseDataRow {
  ClaimItemsRow(super.data);

  @override
  SupabaseTable get table => ClaimItemsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get claimId => getField<String>('claim_id');
  set claimId(String? value) => setField<String>('claim_id', value);

  String get itemName => getField<String>('item_name')!;
  set itemName(String value) => setField<String>('item_name', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  double get quantity => getField<double>('quantity') ?? 1.0;
  set quantity(double value) => setField<double>('quantity', value);

  double? get declaredValue => getField<double>('declared_value');
  set declaredValue(double? value) => setField<double>('declared_value', value);

  double get claimedAmount => getField<double>('claimed_amount') ?? 0.0;
  set claimedAmount(double value) => setField<double>('claimed_amount', value);

  double? get assessedAmount => getField<double>('assessed_amount');
  set assessedAmount(double? value) => setField<double>('assessed_amount', value);

  /// damaged | lost | broken | other — no live catalogue verified beyond
  /// usage, treated as free text.
  String? get damageType => getField<String>('damage_type');
  set damageType(String? value) => setField<String>('damage_type', value);

  List<String> get photoUrls =>
      getListField<String>('photo_urls');
  set photoUrls(List<String> value) => setListField<String>('photo_urls', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
