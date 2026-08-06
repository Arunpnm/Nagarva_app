import '../database.dart';

/// Single source of truth for every material quantity change (migration
/// 005, Session 4). `materials.quantity` is maintained entirely by the
/// `apply_stock_movement()` trigger on this table — never write it
/// directly from app code.
class StockMovementsTable extends SupabaseTable<StockMovementsRow> {
  @override
  String get tableName => 'stock_movements';

  @override
  StockMovementsRow createRow(Map<String, dynamic> data) =>
      StockMovementsRow(data);
}

class StockMovementsRow extends SupabaseDataRow {
  StockMovementsRow(super.data);

  @override
  SupabaseTable get table => StockMovementsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get materialId => getField<String>('material_id')!;
  set materialId(String value) => setField<String>('material_id', value);

  /// purchase | consumption | return | adjustment | transfer_in |
  /// transfer_out | damage | opening
  String get movementType => getField<String>('movement_type')!;
  set movementType(String value) => setField<String>('movement_type', value);

  /// Positive for in, negative for out.
  double get quantity => getField<double>('quantity')!;
  set quantity(double value) => setField<double>('quantity', value);

  double get rate => getField<double>('rate') ?? 0;
  set rate(double value) => setField<double>('rate', value);

  double get value => getField<double>('value') ?? 0;
  set value(double value) => setField<double>('value', value);

  /// grn | order | adjustment | transfer
  String? get refType => getField<String>('ref_type');
  set refType(String? value) => setField<String>('ref_type', value);

  String? get refId => getField<String>('ref_id');
  set refId(String? value) => setField<String>('ref_id', value);

  /// Order this consumption feeds — order_pnl_section.dart sums
  /// movement_type='consumption' rows by this column for the Materials
  /// P&L line.
  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get grnId => getField<String>('grn_id');
  set grnId(String? value) => setField<String>('grn_id', value);

  String? get warehouseId => getField<String>('warehouse_id');
  set warehouseId(String? value) => setField<String>('warehouse_id', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  double? get balanceAfter => getField<double>('balance_after');
  set balanceAfter(double? value) => setField<double>('balance_after', value);

  DateTime? get movementDate => getField<DateTime>('movement_date');
  set movementDate(DateTime? value) =>
      setField<DateTime>('movement_date', value);

  String? get note => getField<String>('note');
  set note(String? value) => setField<String>('note', value);

  String? get createdBy => getField<String>('created_by');
  set createdBy(String? value) => setField<String>('created_by', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
