import '../database.dart';

class DashboardKpisViewTable extends SupabaseTable<DashboardKpisViewRow> {
  @override
  String get tableName => 'dashboard_kpis_view';

  @override
  DashboardKpisViewRow createRow(Map<String, dynamic> data) =>
      DashboardKpisViewRow(data);
}

class DashboardKpisViewRow extends SupabaseDataRow {
  DashboardKpisViewRow(super.data);

  @override
  SupabaseTable get table => DashboardKpisViewTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added along with the org_id column on the view (Phase 1 multi-tenancy
  // pass) — see supabase/phase1_add_org_id.sql and the updated
  // dashboard_kpis_view in supabase/views_dashboard_and_ops.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  double? get revenueThisMonth => getField<double>('revenue_this_month');
  set revenueThisMonth(double? value) =>
      setField<double>('revenue_this_month', value);

  double? get labourThisMonth => getField<double>('labour_this_month');
  set labourThisMonth(double? value) =>
      setField<double>('labour_this_month', value);

  double? get expensesThisMonth => getField<double>('expenses_this_month');
  set expensesThisMonth(double? value) =>
      setField<double>('expenses_this_month', value);

  double? get porterCommThisMonth => getField<double>('porter_comm_this_month');
  set porterCommThisMonth(double? value) =>
      setField<double>('porter_comm_this_month', value);

  double? get netProfitThisMonth => getField<double>('net_profit_this_month');
  set netProfitThisMonth(double? value) =>
      setField<double>('net_profit_this_month', value);

  double? get activeLeads => getField<double>('active_leads');
  set activeLeads(double? value) => setField<double>('active_leads', value);

  double? get ordersThisMonth => getField<double>('orders_this_month');
  set ordersThisMonth(double? value) =>
      setField<double>('orders_this_month', value);

  double? get outstandingAmount => getField<double>('outstanding_amount');
  set outstandingAmount(double? value) =>
      setField<double>('outstanding_amount', value);

  /// Quotations created this calendar month.
  ///
  /// Added with 20260825_dashboard_kpis_quotes_and_active_moves.sql. The
  /// Dart classes in this directory have repeatedly lagged the live
  /// schema (see CLAUDE.md's Item 11 and 12C entries), so these two are
  /// added in the same change as the migration rather than discovered
  /// missing later.
  double? get quotesThisMonth => getField<double>('quotes_this_month');
  set quotesThisMonth(double? value) =>
      setField<double>('quotes_this_month', value);

  /// Orders currently in flight: status in (booked, confirmed, transit).
  ///
  /// NOT month-scoped, unlike [ordersThisMonth] — a job booked last
  /// month and still in transit is active now. The view uses an explicit
  /// inclusion list; see the migration header for why an exclusion list
  /// would be the more dangerous choice.
  double? get activeMoves => getField<double>('active_moves');
  set activeMoves(double? value) => setField<double>('active_moves', value);

  double? get remindersToday => getField<double>('reminders_today');
  set remindersToday(double? value) =>
      setField<double>('reminders_today', value);
}
