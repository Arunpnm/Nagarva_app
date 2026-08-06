import '../database.dart';

/// Server-computed low-stock feed (migration 005) — `quantity <= min_stock`
/// among materials with a real `min_stock` set, with a computed `shortfall`
/// and `stock_status` ('out_of_stock' | 'low' | 'ok'). Read-only view, no
/// primary key of its own — `material_id` is the effective key.
class LowStockViewTable extends SupabaseTable<LowStockViewRow> {
  @override
  String get tableName => 'low_stock_view';

  @override
  LowStockViewRow createRow(Map<String, dynamic> data) =>
      LowStockViewRow(data);
}

class LowStockViewRow extends SupabaseDataRow {
  LowStockViewRow(super.data);

  @override
  SupabaseTable get table => LowStockViewTable();

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get materialId => getField<String>('material_id')!;
  set materialId(String value) => setField<String>('material_id', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String? get unit => getField<String>('unit');
  set unit(String? value) => setField<String>('unit', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  double? get quantity => getField<double>('quantity');
  set quantity(double? value) => setField<double>('quantity', value);

  double? get minStock => getField<double>('min_stock');
  set minStock(double? value) => setField<double>('min_stock', value);

  double? get reorderQty => getField<double>('reorder_qty');
  set reorderQty(double? value) => setField<double>('reorder_qty', value);

  double? get costPerUnit => getField<double>('cost_per_unit');
  set costPerUnit(double? value) => setField<double>('cost_per_unit', value);

  double? get shortfall => getField<double>('shortfall');
  set shortfall(double? value) => setField<double>('shortfall', value);

  /// out_of_stock | low | ok
  String? get stockStatus => getField<String>('stock_status');
  set stockStatus(String? value) => setField<String>('stock_status', value);
}
