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

  // Order Details Session 1 (migration 001): links to the customers master.
  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

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

  // Added by nagarva_migration_003_industry / 004_crm — missing from this
  // generated class until Order Details Session 1.
  String? get rateCardId => getField<String>('rate_card_id');
  set rateCardId(String? value) => setField<String>('rate_card_id', value);

  String? get contractId => getField<String>('contract_id');
  set contractId(String? value) => setField<String>('contract_id', value);

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

  // Pre-dates migrations 001-006 (confirmed live via migration 007's own
  // header note + schema_snapshot_2026-08-01.csv) — missing from this
  // generated class until Mark Order Complete needed it.
  DateTime? get closedAt => getField<DateTime>('closed_at');
  set closedAt(DateTime? value) => setField<DateTime>('closed_at', value);

  DateTime? get deliveredAt => getField<DateTime>('delivered_at');
  set deliveredAt(DateTime? value) => setField<DateTime>('delivered_at', value);

  String? get invoiceNo => getField<String>('invoice_no');
  set invoiceNo(String? value) => setField<String>('invoice_no', value);

  // Real column (reference schema + migration 002's gstr1_b2b_view already
  // read it), just never had a Dart getter — Session 1's kickoff brief
  // even said to write it ("Write invoice_no, invoice_issued_at") but
  // nothing ever did. This is the Money Receipt's "Dated {invoice_date}"
  // source (Session 3 follow-up fix) — stamped once, at first invoice
  // generation, alongside invoice_no.
  DateTime? get invoiceIssuedAt => getField<DateTime>('invoice_issued_at');
  set invoiceIssuedAt(DateTime? value) =>
      setField<DateTime>('invoice_issued_at', value);

  String? get supervisorStatus => getField<String>('supervisor_status');
  set supervisorStatus(String? value) =>
      setField<String>('supervisor_status', value);

  // LEGACY (18 Aug 2026): held the completion OTP, which proved nothing —
  // the supervisor's own screen displayed it before they typed it back.
  // No longer written. Kept only so in-flight jobs created before the
  // switch don't break; drop in a later cleanup.
  String? get jobOtp => getField<String>('job_otp');
  set jobOtp(String? value) => setField<String>('job_otp', value);

  /// Shared with the customer at confirmation; the supervisor enters it
  /// on arrival to mark shifting started. Not a security boundary — it
  /// proves the customer passed it on. Completion is proven by the
  /// signature on `pod_records`, never by a code.
  String? get arrivalCode => getField<String>('arrival_code');
  set arrivalCode(String? value) => setField<String>('arrival_code', value);

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

  /// Does this job owe a commission at all?
  ///
  /// Renamed from `is_porter` on 2 Sept 2026. SNAPSHOTTED at order time
  /// from `lead_sources.is_paid`, alongside [commissionPct] and
  /// [leadSourceId] — the three travel together and are never re-read from
  /// the source afterwards (brief §44).
  ///
  /// This is what separates "no commission is owed" from "a commission is
  /// owed and nobody has priced it". Without it those two collapse into
  /// one null and the app must guess which it is: warn on everything, or
  /// warn on nothing. Both are wrong.
  bool? get commissionExpected => getField<bool>('commission_expected');
  set commissionExpected(bool? value) =>
      setField<bool>('commission_expected', value);

  /// The `lead_sources` row this job came from. Stored for attribution and
  /// reporting; the COMMERCIAL terms are snapshotted onto the order itself
  /// (see [commissionPct]) rather than read back through this FK.
  String? get leadSourceId => getField<String>('lead_source_id');
  set leadSourceId(String? value) => setField<String>('lead_source_id', value);

  /// Commission rate for this order, as a percentage of order value.
  ///
  /// Renamed from `porter_commission_pct` on 2 Sept 2026 when commission
  /// stopped being a porter-only idea: it is now a property of the LEAD
  /// SOURCE the job came from (`lead_sources.commission_pct`), so a paid
  /// directory or a referral partner that takes a cut is priced the same
  /// way a porter job is.
  ///
  /// **This is a SNAPSHOT, taken at order time, not a pointer.** It is
  /// copied from the selected lead source when the order is created and
  /// never re-read afterwards — the same rule the staff-pay brief §44
  /// sets for storage rates: "Each storage record stores the rate it was
  /// booked at, not a pointer to the current rate card", because
  /// otherwise "a price revision silently re-bills every existing
  /// customer". Changing a lead source's rate must never re-price a job
  /// that is already closed and settled.
  ///
  /// **Null means NOT PRICED — it does not mean zero.** Nothing may
  /// substitute a rate for a null (this column's predecessor was read as
  /// `?? 16` in four places, which quietly costed every unpriced order at
  /// APC's own porter rate). Route every read through
  /// `/backend/commission_pricing.dart`, which distinguishes "no
  /// commission applies" from "nobody has priced this yet".
  double? get commissionPct => getField<double>('commission_pct');
  set commissionPct(double? value) =>
      setField<double>('commission_pct', value);

  String? get porterOrderNo => getField<String>('porter_order_no');
  set porterOrderNo(String? value) =>
      setField<String>('porter_order_no', value);

  String? get trackingStatus => getField<String>('tracking_status');
  set trackingStatus(String? value) =>
      setField<String>('tracking_status', value);

  // Added by supabase/20260728_public_links_sign_and_track.sql (item 6) —
  // the credential for the public /track?token=... page. Null-safe read:
  // returns null on any row predating that migration.
  String? get trackingToken => getField<String>('tracking_token');
  set trackingToken(String? value) =>
      setField<String>('tracking_token', value);

  // ---- Order-time quote snapshot (item 2) --------------------------------
  // Added by supabase/20260729_order_quote_snapshot.sql. Frozen at Convert
  // to Order so a later quote revision or signature can't change what the
  // order was confirmed on. `quotationId` above stays the LIVE link; these
  // are the historic record. All null-safe: they simply return null on any
  // row predating the migration, and `quoteSnapshotAt == null` is the flag
  // for "no snapshot, fall back to the linked quote".
  dynamic get quoteItems => getField<dynamic>('quote_items');
  dynamic get quoteCharges => getField<dynamic>('quote_charges');
  double? get quoteSubtotal => getField<double>('quote_subtotal');
  double? get quoteGstPct => getField<double>('quote_gst_pct');
  double? get quoteGstAmount => getField<double>('quote_gst_amount');
  double? get quoteTotal => getField<double>('quote_total');

  /// 'inter' | 'intra' — resolved at conversion, never 'auto'.
  String? get quoteGstMode => getField<String>('quote_gst_mode');
  String? get quotePackingType => getField<String>('quote_packing_type');
  double? get quoteTotalCft => getField<double>('quote_total_cft');

  // Item 12C (20260817_item12c_package_columns.sql) — the frozen
  // suggestion and the surveyor's actual choice, copied off the quotation
  // at conversion. Deliberately NOT re-derived from the org's slab table:
  // a later Settings edit must never rewrite a dispatched job.
  String? get suggestedPackage => getField<String>('suggested_package');
  String? get suggestedVehicle => getField<String>('suggested_vehicle');
  int? get suggestedCrew => getField<int>('suggested_crew');
  String? get chosenPackage => getField<String>('chosen_package');
  String? get chosenVehicle => getField<String>('chosen_vehicle');
  int? get chosenCrew => getField<int>('chosen_crew');
  int? get quoteVersion => getField<int>('quote_version');
  DateTime? get quoteSnapshotAt => getField<DateTime>('quote_snapshot_at');

  // migration 003/004 — the LR this order links to. Never had a getter.
  String? get lrId => getField<String>('lr_id');
  set lrId(String? value) => setField<String>('lr_id', value);

  // Added by nagarva_migration_009_documents (Session 3).
  DateTime? get packingDate => getField<DateTime>('packing_date');
  set packingDate(DateTime? value) =>
      setField<DateTime>('packing_date', value);

  DateTime? get deliveryDate => getField<DateTime>('delivery_date');
  set deliveryDate(DateTime? value) =>
      setField<DateTime>('delivery_date', value);

  /// 'full_load' | 'part_load'
  String? get loadType => getField<String>('load_type');
  set loadType(String? value) => setField<String>('load_type', value);

  /// 'dedicated' | 'shared'
  String? get vehicleType => getField<String>('vehicle_type');
  set vehicleType(String? value) => setField<String>('vehicle_type', value);

  /// 'road' | 'rail' | 'air' | 'ship'
  String? get transportMode => getField<String>('transport_mode');
  set transportMode(String? value) =>
      setField<String>('transport_mode', value);

  bool? get fromHasLift => getField<bool>('from_has_lift');
  set fromHasLift(bool? value) => setField<bool>('from_has_lift', value);

  bool? get toHasLift => getField<bool>('to_has_lift');
  set toHasLift(bool? value) => setField<bool>('to_has_lift', value);

  /// Billing party can differ from the consignor (corporate relocation
  /// billed to the employer). Null means "bill the customer" — the
  /// invoice's Bill To block falls back to `customer`/`phone` when this
  /// is unset, per the Session 3 brief.
  String? get billingPartyName => getField<String>('billing_party_name');
  set billingPartyName(String? value) =>
      setField<String>('billing_party_name', value);

  String? get billingPartyGstin => getField<String>('billing_party_gstin');
  set billingPartyGstin(String? value) =>
      setField<String>('billing_party_gstin', value);

  String? get billingPartyAddress =>
      getField<String>('billing_party_address');
  set billingPartyAddress(String? value) =>
      setField<String>('billing_party_address', value);

  String? get billingPartyPhone => getField<String>('billing_party_phone');
  set billingPartyPhone(String? value) =>
      setField<String>('billing_party_phone', value);

  /// SAC 996719 = goods transport / packers and movers. Tenant-overridable,
  /// but the DB default already covers every order that never sets it.
  String? get hsnSacCode => getField<String>('hsn_sac_code');
  set hsnSacCode(String? value) => setField<String>('hsn_sac_code', value);

  bool? get reverseCharge => getField<bool>('reverse_charge');
  set reverseCharge(bool? value) => setField<bool>('reverse_charge', value);

  String? get paymentRemark => getField<String>('payment_remark');
  set paymentRemark(String? value) =>
      setField<String>('payment_remark', value);
}
