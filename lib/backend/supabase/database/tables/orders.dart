import '../database.dart';

class OrdersTable extends SupabaseTable<OrdersRow> {
  @override
  String get tableName => 'orders';

  @override
  OrdersRow createRow(Map<String, dynamic> data) => OrdersRow(data);
}

class OrdersRow extends SupabaseDataRow {
  OrdersRow(super.data);

  @override
  SupabaseTable get table => OrdersTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  // Null-safe: getField returns null until that migration runs.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get leadId => getField<String>('lead_id');
  set leadId(String? value) => setField<String>('lead_id', value);

  String? get quotationId => getField<String>('quotation_id');
  set quotationId(String? value) => setField<String>('quotation_id', value);

  String get customer => getField<String>('customer')!;
  set customer(String value) => setField<String>('customer', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  String? get fromCity => getField<String>('from_city');
  set fromCity(String? value) => setField<String>('from_city', value);

  String? get toCity => getField<String>('to_city');
  set toCity(String? value) => setField<String>('to_city', value);

  String? get fromAddress => getField<String>('from_address');
  set fromAddress(String? value) => setField<String>('from_address', value);

  String? get toAddress => getField<String>('to_address');
  set toAddress(String? value) => setField<String>('to_address', value);

  int? get fromFloor => getField<int>('from_floor');
  set fromFloor(int? value) => setField<int>('from_floor', value);

  int? get toFloor => getField<int>('to_floor');
  set toFloor(int? value) => setField<int>('to_floor', value);

  DateTime get moveDate => getField<DateTime>('move_date')!;
  set moveDate(DateTime value) => setField<DateTime>('move_date', value);

  /// Null-safe read of the same column — use this anywhere a list of
  /// orders is read unfiltered, since one row with no move_date will
  /// otherwise throw on `.moveDate` and blank the whole page (the bug
  /// fixed for Calendar in item 5; see NAGARVA_STATUS.md item 13 for the
  /// other call sites that had the same unguarded pattern).
  DateTime? get moveDateOrNull => getField<DateTime>('move_date');

  double? get amount => getField<double>('amount');

  /// Sum of payment_entries for this order — maintained by DB trigger
  /// (20260718_payment_entries.sql). Balance due =
  /// amount - advancePaid - paidTotal.
  double get paidTotal => getField<double>('paid_total') ?? 0;
  set amount(double? value) => setField<double>('amount', value);

  String? get orderType => getField<String>('order_type');
  set orderType(String? value) => setField<String>('order_type', value);

  double? get distanceKm => getField<double>('distance_km');
  set distanceKm(double? value) => setField<double>('distance_km', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  String? get service => getField<String>('service');
  set service(String? value) => setField<String>('service', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  double? get advancePaid => getField<double>('advance_paid');
  set advancePaid(double? value) => setField<double>('advance_paid', value);

  String? get paymentStatus => getField<String>('payment_status');
  set paymentStatus(String? value) => setField<String>('payment_status', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get orderSource => getField<String>('order_source');
  set orderSource(String? value) => setField<String>('order_source', value);

  String? get vehicleNo => getField<String>('vehicle_no');
  set vehicleNo(String? value) => setField<String>('vehicle_no', value);

  String? get driverName => getField<String>('driver_name');
  set driverName(String? value) => setField<String>('driver_name', value);

  String? get supervisorId => getField<String>('supervisor_id');
  set supervisorId(String? value) => setField<String>('supervisor_id', value);

  bool? get orderComplete => getField<bool>('order_complete');
  set orderComplete(bool? value) => setField<bool>('order_complete', value);

  String? get invoiceNo => getField<String>('invoice_no');
  set invoiceNo(String? value) => setField<String>('invoice_no', value);

  String? get supervisorStatus => getField<String>('supervisor_status');
  set supervisorStatus(String? value) =>
      setField<String>('supervisor_status', value);

  String? get jobOtp => getField<String>('job_otp');
  set jobOtp(String? value) => setField<String>('job_otp', value);

  DateTime? get jobStartTime => getField<DateTime>('job_start_time');
  set jobStartTime(DateTime? value) =>
      setField<DateTime>('job_start_time', value);

  DateTime? get jobEndTime => getField<DateTime>('job_end_time');
  set jobEndTime(DateTime? value) => setField<DateTime>('job_end_time', value);

  String? get supervisorNotes => getField<String>('supervisor_notes');
  set supervisorNotes(String? value) =>
      setField<String>('supervisor_notes', value);

  dynamic get jobTeam => getField<dynamic>('job_team');
  set jobTeam(dynamic value) => setField<dynamic>('job_team', value);

  double? get porterCashCollect => getField<double>('porter_cash_collect');
  set porterCashCollect(double? value) =>
      setField<double>('porter_cash_collect', value);

  bool? get isPorter => getField<bool>('is_porter');
  set isPorter(bool? value) => setField<bool>('is_porter', value);

  double? get porterCommissionPct => getField<double>('porter_commission_pct');
  set porterCommissionPct(double? value) =>
      setField<double>('porter_commission_pct', value);

  String? get porterOrderNo => getField<String>('porter_order_no');
  set porterOrderNo(String? value) =>
      setField<String>('porter_order_no', value);

  String? get trackingStatus => getField<String>('tracking_status');
  set trackingStatus(String? value) =>
      setField<String>('tracking_status', value);
}
