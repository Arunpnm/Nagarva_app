import '../database.dart';

class OrganizationsTable extends SupabaseTable<OrganizationsRow> {
  @override
  String get tableName => 'organizations';

  @override
  OrganizationsRow createRow(Map<String, dynamic> data) =>
      OrganizationsRow(data);
}

class OrganizationsRow extends SupabaseDataRow {
  OrganizationsRow(super.data);

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

  // Added by nagarva_migration_006_compliance — missing from this generated
  // class until Order Details Session 1's utility row needed it (Copy UPI).
  String? get upiId => getField<String>('upi_id');
  set upiId(String? value) => setField<String>('upi_id', value);

  String? get address => getField<String>('address');
  set address(String? value) => setField<String>('address', value);

  // Rest of migration 006 — never had getters at all until Session 3's
  // document work needed them for the shared PDF header.
  String? get city => getField<String>('city');
  set city(String? value) => setField<String>('city', value);

  String? get state => getField<String>('state');
  set state(String? value) => setField<String>('state', value);

  int? get stateCode => getField<int>('state_code');
  set stateCode(int? value) => setField<int>('state_code', value);

  String? get pincode => getField<String>('pincode');
  set pincode(String? value) => setField<String>('pincode', value);

  String? get pan => getField<String>('pan');
  set pan(String? value) => setField<String>('pan', value);

  String? get website => getField<String>('website');
  set website(String? value) => setField<String>('website', value);

  String? get supportEmail => getField<String>('support_email');
  set supportEmail(String? value) => setField<String>('support_email', value);

  String? get tagline => getField<String>('tagline');
  set tagline(String? value) => setField<String>('tagline', value);

  // Added by nagarva_migration_009_documents — the shared document header
  // block (Session 3). All nullable; the header degrades gracefully when
  // a tenant hasn't filled these in yet, same convention as the rest of
  // this class.
  String? get phoneSecondary => getField<String>('phone_secondary');
  set phoneSecondary(String? value) =>
      setField<String>('phone_secondary', value);

  String? get phoneTertiary => getField<String>('phone_tertiary');
  set phoneTertiary(String? value) =>
      setField<String>('phone_tertiary', value);

  String? get phoneQuaternary => getField<String>('phone_quaternary');
  set phoneQuaternary(String? value) =>
      setField<String>('phone_quaternary', value);

  String? get landline => getField<String>('landline');
  set landline(String? value) => setField<String>('landline', value);

  String? get udyamNo => getField<String>('udyam_no');
  set udyamNo(String? value) => setField<String>('udyam_no', value);

  String? get affiliationText => getField<String>('affiliation_text');
  set affiliationText(String? value) =>
      setField<String>('affiliation_text', value);

  String? get branchListText => getField<String>('branch_list_text');
  set branchListText(String? value) =>
      setField<String>('branch_list_text', value);

  String? get signatoryImageUrl => getField<String>('signatory_image_url');
  set signatoryImageUrl(String? value) =>
      setField<String>('signatory_image_url', value);

  String? get signatoryName => getField<String>('signatory_name');
  set signatoryName(String? value) =>
      setField<String>('signatory_name', value);

  String? get beneficiaryName => getField<String>('beneficiary_name');
  set beneficiaryName(String? value) =>
      setField<String>('beneficiary_name', value);

  String? get bankName => getField<String>('bank_name');
  set bankName(String? value) => setField<String>('bank_name', value);

  String? get bankAccountNo => getField<String>('bank_account_no');
  set bankAccountNo(String? value) =>
      setField<String>('bank_account_no', value);

  String? get bankIfsc => getField<String>('bank_ifsc');
  set bankIfsc(String? value) => setField<String>('bank_ifsc', value);

  String? get upiDisplayNumber => getField<String>('upi_display_number');
  set upiDisplayNumber(String? value) =>
      setField<String>('upi_display_number', value);
}
