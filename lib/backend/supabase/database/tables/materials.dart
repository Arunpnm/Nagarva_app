import '../database.dart';

class MaterialsTable extends SupabaseTable<MaterialsRow> {
  @override
  String get tableName => 'materials';

  @override
  MaterialsRow createRow(Map<String, dynamic> data) => MaterialsRow(data);
}

class MaterialsRow extends SupabaseDataRow {
  MaterialsRow(super.data);

  @override
  SupabaseTable get table => MaterialsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String? get unit => getField<String>('unit');
  set unit(String? value) => setField<String>('unit', value);

  double? get quantity => getField<double>('quantity');
  set quantity(double? value) => setField<double>('quantity', value);

  double? get minStock => getField<double>('min_stock');
  set minStock(double? value) => setField<double>('min_stock', value);

  double? get costPerUnit => getField<double>('cost_per_unit');
  set costPerUnit(double? value) => setField<double>('cost_per_unit', value);

  DateTime? get lastUpdated => getField<DateTime>('last_updated');
  set lastUpdated(DateTime? value) => setField<DateTime>('last_updated', value);

  // Added by nagarva_migration_003_industry (Session 4) — never had getters.
  double? get sellingPrice => getField<double>('selling_price');
  set sellingPrice(double? value) => setField<double>('selling_price', value);

  String? get hsnCode => getField<String>('hsn_code');
  set hsnCode(String? value) => setField<String>('hsn_code', value);

  // Added by nagarva_migration_005_accounting (Session 4) — never had
  // getters. `quantity` above is now maintained ENTIRELY by the
  // apply_stock_movement() trigger on `stock_movements` — never set it
  // directly from app code; write a stock_movements row instead (see
  // material_detail_sheet.dart).
  String? get category => getField<String>('category');
  set category(String? value) => setField<String>('category', value);

  String? get sku => getField<String>('sku');
  set sku(String? value) => setField<String>('sku', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  String? get warehouseId => getField<String>('warehouse_id');
  set warehouseId(String? value) => setField<String>('warehouse_id', value);

  double? get reorderQty => getField<double>('reorder_qty');
  set reorderQty(double? value) => setField<double>('reorder_qty', value);

  bool? get isReturnable => getField<bool>('is_returnable');
  set isReturnable(bool? value) => setField<bool>('is_returnable', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);
}
