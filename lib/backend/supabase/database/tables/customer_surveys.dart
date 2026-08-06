import '../database.dart';

/// Public customer-facing survey submissions (Session 4, Part B1). Live
/// schema confirmed directly against the DB (29 columns) — NOT the same
/// table as `surveys` (the lead-linked survey/quote flow's own table,
/// `rooms` jsonb array shape, handled by parseSurveyRooms() in
/// survey_response_section.dart). This is a separate, older system with a
/// materially different shape:
///   - `items` is a jsonb OBJECT of {itemKey: qty} (flat, no
///     room/category grouping) — confirmed live, e.g.
///     {"fan":4,"chair":3,"sofa3":3,"tvLarge":3,"centerTbl":3}.
///   - `custom_items` is a jsonb ARRAY, confirmed empty in every live row
///     (2/2) — its populated shape could not be verified against real
///     data. Parsed defensively (see customer_survey_parse.dart).
///   - `photos` is a jsonb OBJECT keyed by room name, each value an ARRAY
///     of inline base64 data-URI strings (confirmed live) — not Storage
///     URLs.
///   - `from_floor`/`from_lift`/`to_floor`/`to_lift` are TEXT, not
///     int/bool (confirmed live: "", "Ground", "yes") — never parsed as
///     numbers/booleans.
///   - `converted_to_order_id` is uuid but `orders.id` is TEXT — this FK
///     can never match a real order id. Flagged, not worked around;
///     "Convert to Order" deliberately does not attempt to write this
///     column until its type is fixed in a future migration.
class CustomerSurveysTable extends SupabaseTable<CustomerSurveysRow> {
  @override
  String get tableName => 'customer_surveys';

  @override
  CustomerSurveysRow createRow(Map<String, dynamic> data) =>
      CustomerSurveysRow(data);
}

class CustomerSurveysRow extends SupabaseDataRow {
  CustomerSurveysRow(super.data);

  @override
  SupabaseTable get table => CustomerSurveysTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String get token => getField<String>('token')!;
  set token(String value) => setField<String>('token', value);

  String? get leadId => getField<String>('lead_id');
  set leadId(String? value) => setField<String>('lead_id', value);

  String? get customerName => getField<String>('customer_name');
  set customerName(String? value) => setField<String>('customer_name', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  String? get email => getField<String>('email');
  set email(String? value) => setField<String>('email', value);

  String? get fromCity => getField<String>('from_city');
  set fromCity(String? value) => setField<String>('from_city', value);

  String? get fromAddress => getField<String>('from_address');
  set fromAddress(String? value) => setField<String>('from_address', value);

  /// TEXT, not int — live values include "" and "Ground".
  String? get fromFloor => getField<String>('from_floor');
  set fromFloor(String? value) => setField<String>('from_floor', value);

  /// TEXT, not bool — live values include "" and "yes".
  String? get fromLift => getField<String>('from_lift');
  set fromLift(String? value) => setField<String>('from_lift', value);

  String? get toCity => getField<String>('to_city');
  set toCity(String? value) => setField<String>('to_city', value);

  String? get toAddress => getField<String>('to_address');
  set toAddress(String? value) => setField<String>('to_address', value);

  String? get toFloor => getField<String>('to_floor');
  set toFloor(String? value) => setField<String>('to_floor', value);

  String? get toLift => getField<String>('to_lift');
  set toLift(String? value) => setField<String>('to_lift', value);

  DateTime? get moveDate => getField<DateTime>('move_date');
  set moveDate(DateTime? value) => setField<DateTime>('move_date', value);

  String get service => getField<String>('service') ?? 'Home Shifting';
  set service(String value) => setField<String>('service', value);

  /// jsonb OBJECT {itemKey: qty} — see class doc comment.
  dynamic get items => getField<dynamic>('items');
  set items(dynamic value) => setField('items', value);

  /// jsonb ARRAY — shape unverified against live data (always empty so
  /// far). See class doc comment.
  dynamic get customItems => getField<dynamic>('custom_items');
  set customItems(dynamic value) => setField('custom_items', value);

  /// jsonb OBJECT {roomName: [base64 data-URI, ...]}.
  dynamic get photos => getField<dynamic>('photos');
  set photos(dynamic value) => setField('photos', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  int? get totalCft => getField<int>('total_cft');
  set totalCft(int? value) => setField<int>('total_cft', value);

  String? get suggestedVehicle => getField<String>('suggested_vehicle');
  set suggestedVehicle(String? value) =>
      setField<String>('suggested_vehicle', value);

  /// pending | submitted | reviewed | converted | discarded (last one is
  /// this app's own addition for the Discard action — not part of the
  /// brief's stated lifecycle, no live row uses it yet).
  String get status => getField<String>('status') ?? 'pending';
  set status(String value) => setField<String>('status', value);

  DateTime? get submittedAt => getField<DateTime>('submitted_at');
  set submittedAt(DateTime? value) =>
      setField<DateTime>('submitted_at', value);

  String? get reviewedBy => getField<String>('reviewed_by');
  set reviewedBy(String? value) => setField<String>('reviewed_by', value);

  DateTime? get reviewedAt => getField<DateTime>('reviewed_at');
  set reviewedAt(DateTime? value) => setField<DateTime>('reviewed_at', value);

  /// uuid column — orders.id is TEXT. Never write this until the column
  /// type is fixed (Arun's own follow-up migration). Read-only here.
  String? get convertedToOrderId => getField<String>('converted_to_order_id');

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);
}
