import '../database.dart';

/// Per-trip P&L rollup (Session 4, Part C-9) — revenue from carried orders
/// vs trip expenses + hire cost. Read-only view.
class TripPnlViewTable extends SupabaseTable<TripPnlViewRow> {
  @override
  String get tableName => 'trip_pnl_view';

  @override
  TripPnlViewRow createRow(Map<String, dynamic> data) => TripPnlViewRow(data);
}

class TripPnlViewRow extends SupabaseDataRow {
  TripPnlViewRow(super.data);

  @override
  SupabaseTable get table => TripPnlViewTable();

  String? get orgId => getField<String>('org_id');

  String? get tripId => getField<String>('trip_id');

  String? get tripNo => getField<String>('trip_no');

  String? get tripType => getField<String>('trip_type');

  String? get vehicleNo => getField<String>('vehicle_no');

  DateTime? get startDate => getField<DateTime>('start_date');

  int get totalKm => getField<int>('total_km') ?? 0;

  int get orderCount => getField<int>('order_count') ?? 0;

  double get grossRevenue => getField<double>('gross_revenue') ?? 0.0;

  double get tripExpenses => getField<double>('trip_expenses') ?? 0.0;

  double get hireAmount => getField<double>('hire_amount') ?? 0.0;

  double get netProfit => getField<double>('net_profit') ?? 0.0;

  double get costPerKm => getField<double>('cost_per_km') ?? 0.0;
}
