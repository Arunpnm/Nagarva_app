import '../database.dart';

class OrganizationsTable extends SupabaseTable<OrganizationsRow> {
  @override
  String get tableName => 'organizations';

  @override
  OrganizationsRow createRow(Map<String, dynamic> data) =>
      OrganizationsRow(data);
}

class OrganizationsRow extends SupabaseDataRow {
  OrganizationsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => OrganizationsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String get slug => getField<String>('slug')!;
  set slug(String value) => setField<String>('slug', value);

  String? get gstin => getField<String>('gstin');
  set gstin(String? value) => setField<String>('gstin', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  // email / logo_url / owner_id (below) are NOT in the owner-confirmed live
  // schema — organizations(id, name, slug, gstin, phone, plan_id,
  // plan_status, trial_ends_at, active, created_at). Kept as best-effort
  // read-only getters (an absent column just returns null on read) so
  // existing UI code (e.g. SettingsPage) doesn't fail to compile. NEVER use
  // these three in an insert/update payload — see signup_page_widget.dart.
  String? get email => getField<String>('email');
  set email(String? value) => setField<String>('email', value);

  String? get logoUrl => getField<String>('logo_url');
  set logoUrl(String? value) => setField<String>('logo_url', value);

  bool get active => getField<bool>('active') ?? true;
  set active(bool value) => setField<bool>('active', value);

  String? get planId => getField<String>('plan_id');
  set planId(String? value) => setField<String>('plan_id', value);

  // Added 13 Jul 2026 per owner-confirmed live schema.
  String? get planStatus => getField<String>('plan_status');
  set planStatus(String? value) => setField<String>('plan_status', value);

  DateTime? get trialEndsAt => getField<DateTime>('trial_ends_at');
  set trialEndsAt(DateTime? value) =>
      setField<DateTime>('trial_ends_at', value);

  String? get ownerId => getField<String>('owner_id');
  set ownerId(String? value) => setField<String>('owner_id', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
