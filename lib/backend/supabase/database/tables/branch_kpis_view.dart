import '../database.dart';

class BranchKpisViewTable extends SupabaseTable<BranchKpisViewRow> {
  @override
  String get tableName => 'branch_kpis_view';

  @override
  BranchKpisViewRow createRow(Map<String, dynamic> data) =>
      BranchKpisViewRow(data);
}

class BranchKpisViewRow extends SupabaseDataRow {
  BranchKpisViewRow(super.data);

  @override
  SupabaseTable get table => BranchKpisViewTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // See dashboard_kpis_view.dart — same Phase 1 org_id passthrough.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  double? get revenue => getField<double>('revenue');
  set revenue(double? value) => setField<double>('revenue', value);

  double? get orderCount => getField<double>('order_count');
  set orderCount(double? value) => setField<double>('order_count', value);

  double? get outstanding => getField<double>('outstanding');
  set outstanding(double? value) => setField<double>('outstanding', value);

  double? get netProfit => getField<double>('net_profit');
  set netProfit(double? value) => setField<double>('net_profit', value);
}
