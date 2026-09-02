import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/doc_prefix.dart';
import '/backend/edge_function_errors.dart';
import '/components/logo_upload_card.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/app_session.dart';
import '/index.dart';
import '/users_page/staff_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'org_setup_page_model.dart';
export 'org_setup_page_model.dart';

class OrgSetupPageWidget extends StatefulWidget {
  const OrgSetupPageWidget({super.key});

  static String routeName = 'OrgSetupPage';
  static String routePath = '/org-setup';

  @override
  State<OrgSetupPageWidget> createState() => _OrgSetupPageWidgetState();
}

class _OrgSetupPageWidgetState extends State<OrgSetupPageWidget> {
  late OrgSetupPageModel _model;
  final _formKey = GlobalKey<FormState>();
  List<StaffRow> _seededStaff = [];

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => OrgSetupPageModel());
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final rows = await StaffTable().queryRows(queryFn: (q) => OrgScope.read(q));
    if (mounted) setState(() => _seededStaff = rows);
  }

  Future<void> _addTeamMember() async {
    final saved = await StaffFormSheet.show(context);
    if (saved) _loadStaff();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return;

    safeSetState(() {
      _model.isLoading = true;
      _model.errorMessage = null;
    });

    try {
      final gstin = _model.gstinController!.text.trim();
      final prefix = _model.prefixController!.text.trim();
      final address = _model.addressController!.text.trim();
      final city = _model.cityController!.text.trim();
      final state = _model.stateController!.text.trim();

      // Update organizations row with gstin
      if (gstin.isNotEmpty) {
        await OrganizationsTable().update(
          data: {'gstin': gstin},
          matchingRows: (q) => q.eq('id', orgId),
        );
      }

      // Upsert settings rows (org_id scoped key/value pairs). `settings` now
      // has a real composite PK on (org_id, key) (added 2026-07-14) — a
      // plain insert would throw a duplicate-key error if this page is ever
      // saved twice for the same org (e.g. the owner goes back and edits
      // their business details after finishing onboarding), so this uses
      // upsert instead of the insert this used to be.
      final rows = <Map<String, dynamic>>[];
      // The prefix deliberately does NOT go into `settings` any more.
      //
      // It used to be written as settings.invoice_prefix — and NOTHING IN
      // THE APP EVER READ THAT KEY. next_doc_number() reads
      // number_series.prefix and never consults settings, so a vendor
      // typed their invoice prefix here, the app accepted it, and every
      // document they issued came out on the seeded default instead.
      // User-visible on the very first invoice a new tenant raises, and
      // it is their own document identity. (Status doc section 9.1.)
      if (gstin.isNotEmpty) {
        rows.add({'key': 'gstin', 'value': gstin, ...OrgScope.stamp()});
      }
      if (address.isNotEmpty) {
        rows.add({'key': 'address', 'value': address, ...OrgScope.stamp()});
      }
      if (city.isNotEmpty) {
        rows.add({'key': 'city', 'value': city, ...OrgScope.stamp()});
      }
      if (state.isNotEmpty) {
        rows.add({'key': 'state', 'value': state, ...OrgScope.stamp()});
      }
      if (rows.isNotEmpty) {
        await SupaFlow.client
            .from('settings')
            .upsert(rows, onConflict: 'org_id,key');
      }

      // LAST, and it can halt. Deliberately after the settings write so
      // the rejection message's "your other details were saved" is true
      // — it runs before them until 2 Sep 2026, which meant a rejected
      // prefix also silently discarded the address and city.
      //
      // Halting at all is the change Arun asked for: this used to set
      // `_model.errorMessage` and then fall straight through to
      // `context.go(HomePage)`, so the message was written and discarded
      // in the same frame. The vendor landed on the dashboard believing
      // they had set a prefix they had not.
      //
      // Safe to halt now that seeding derives a per-org default from the
      // slug: refusing this prefix leaves them on a valid, unique one, so
      // they can correct the field or clear it and continue.
      final prefixError = await _applyInvoicePrefix(orgId, prefix);
      if (prefixError != null) {
        safeSetState(() {
          _model.errorMessage = prefixError;
          _model.isLoading = false;
        });
        return;
      }

      if (mounted) context.go(HomePageWidget.routePath);
    } catch (e) {
      safeSetState(() {
        _model.errorMessage = e.toString().replaceFirst('Exception: ', '');
        _model.isLoading = false;
      });
    }
  }

  /// Doc types whose prefix is the calendar-year default (`2026/`) that
  /// `seed_org_number_series()` generates. These are the ones a vendor's
  /// own prefix should replace. `LR`, `CLM-`, `PO-`, `GRN-`, `PS-`,
  /// `CTR-`, `STG-` are semantic abbreviations, not branding, and keep
  /// their seeded values.
  static const _prefixableDocTypes = <String>[
    'invoice',
    'proforma',
    'receipt',
    'quotation',
    'voucher',
    'credit_note',
    'debit_note',
  ];

  /// Writes the vendor's chosen prefix onto their seeded `number_series`
  /// rows — the thing that actually determines what prints on a document.
  ///
  /// Three guards, all deliberate:
  ///  - `last_number = 0` only. Changing a prefix once numbers have been
  ///    issued would silently continue the same counter under a new
  ///    identity, leaving the earlier numbers unreachable and breaking
  ///    Rule 46(b) consecutiveness for tax invoices (status doc 9.3). At
  ///    onboarding every counter is still 0, so this is always satisfied
  ///    here — the guard exists so this code stays correct if it is ever
  ///    reused from a settings screen.
  ///  - Format validated client-side by [validateDocPrefix], which
  ///    mirrors the `number_series_prefix_format` CHECK. Rule 46(b) caps
  ///    the whole invoice number at 16 characters and `padding` takes 4,
  ///    so the prefix budget is 12 — widened from 10 on 2 Sep 2026 so an
  ///    FY segment (`BLR/2026-27/`) fits.
  ///  - Uniqueness across tenants, checked server-side. This CANNOT be
  ///    done from here: `number_series` is RLS-scoped per org, so a
  ///    client query for "is this prefix taken" can only ever see this
  ///    org's own rows and would answer "free" every time. The
  ///    `check_doc_prefix` RPC (SECURITY DEFINER) answers it properly,
  ///    and a BEFORE INSERT/UPDATE trigger enforces it for real so a
  ///    request that bypasses the app cannot take a prefix either.
  ///
  /// Returns null on success, or the reason to show the vendor. A
  /// rejection is NOT swallowed any more: the whole point of the prefix
  /// is that it is the vendor's document identity, and quietly leaving
  /// them on a different one than they typed is how the original bug
  /// (every org printing the same first invoice number) stayed invisible.
  /// Refusing is safe because seeding now derives a unique per-org
  /// default from the slug — a rejected vendor still has a valid prefix.
  Future<String?> _applyInvoicePrefix(String orgId, String prefix) async {
    if (prefix.isEmpty) return null;

    final formatError = validateDocPrefix(prefix);
    if (formatError != null) {
      return '$formatError Your other details were saved.';
    }

    try {
      final taken = docPrefixRejection(
        await SupaFlow.client.rpc('check_doc_prefix', params: {
          'p_prefix': prefix,
          'p_org_id': orgId,
        }),
      );
      if (taken != null) {
        return '$taken Your other details were saved — '
            'pick a different prefix, or leave it blank to keep the default.';
      }

      await SupaFlow.client
          .from('number_series')
          .update({'prefix': prefix})
          .eq('org_id', orgId)
          .eq('last_number', 0)
          .inFilter('doc_type', _prefixableDocTypes);
      return null;
    } catch (e) {
      // The trigger raises P0001 with a real sentence, which
      // extractDbErrorMessage surfaces verbatim; it is also what catches
      // the race where two vendors submit the same prefix between the
      // pre-check above and this write.
      return extractDbErrorMessage(e,
          fallback: 'Could not save your invoice prefix. Your other details '
              'were saved; the default prefix is still in use.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          title: Text(
            'Business Setup',
            style: GoogleFonts.interTight(
              color: theme.primaryText,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          actions: [
            TextButton(
              onPressed: () => context.go(HomePageWidget.routePath),
              child: Text(
                'Skip',
                style: GoogleFonts.inter(
                  color: theme.secondaryText,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeader(theme, 'Tax & Invoicing'),
                  const SizedBox(height: 12),
                  _buildCard(theme, [
                    _field(
                      theme,
                      controller: _model.gstinController!,
                      focusNode: _model.gstinFocusNode!,
                      label: 'GST Number',
                      hint: '33AABCU9603R1ZX',
                      icon: Icons.receipt_long_outlined,
                    ),
                    const SizedBox(height: 14),
                    _field(
                      theme,
                      controller: _model.prefixController!,
                      focusNode: _model.prefixFocusNode!,
                      label: 'Invoice Prefix',
                      hint: 'e.g. APC  →  APC/2526/001',
                      icon: Icons.tag,
                      validator: (v) =>
                          (v != null && v.trim().isNotEmpty && v.trim().length > 6)
                              ? 'Keep it short (≤ 6 chars)'
                              : null,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _sectionHeader(theme, 'Business Address'),
                  const SizedBox(height: 12),
                  _buildCard(theme, [
                    _field(
                      theme,
                      controller: _model.addressController!,
                      focusNode: _model.addressFocusNode!,
                      label: 'Street Address',
                      hint: '12 Gandhi Road, T.Nagar',
                      icon: Icons.location_on_outlined,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            theme,
                            controller: _model.cityController!,
                            focusNode: _model.cityFocusNode!,
                            label: 'City',
                            hint: 'Chennai',
                            icon: Icons.location_city_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            theme,
                            controller: _model.stateController!,
                            focusNode: _model.stateFocusNode!,
                            label: 'State',
                            hint: 'Tamil Nadu',
                            icon: Icons.map_outlined,
                          ),
                        ),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _sectionHeader(theme, 'Branding'),
                  const SizedBox(height: 12),
                  const LogoUploadCard(),
                  const SizedBox(height: 20),
                  _sectionHeader(theme, 'Your Team'),
                  const SizedBox(height: 12),
                  _buildCard(theme, [
                    if (_seededStaff.isEmpty)
                      Text(
                        'No staff added yet — you can add drivers, packers, '
                        'and supervisors now or later from Users.',
                        style: GoogleFonts.inter(
                            color: theme.secondaryText, fontSize: 13),
                      )
                    else
                      ..._seededStaff.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.person_outline,
                                    size: 18, color: theme.secondaryText),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${s.name ?? ''} · ${s.role ?? ''}',
                                    style: GoogleFonts.inter(
                                        color: theme.primaryText,
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _addTeamMember,
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('Add Team Member'),
                    ),
                  ]),
                  if (_model.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _model.errorMessage!,
                        style: GoogleFonts.inter(
                          color: theme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FFButtonWidget(
                    text: 'Save & Continue',
                    onPressed: _model.isLoading ? null : _handleSave,
                    options: FFButtonOptions(
                      height: 52,
                      color: theme.primary,
                      textStyle: GoogleFonts.interTight(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      elevation: 0,
                    ),
                    showLoadingIndicator: _model.isLoading,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(FlutterFlowTheme theme, String title) => Text(
        title,
        style: GoogleFonts.interTight(
          color: theme.primaryText,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _buildCard(FlutterFlowTheme theme, List<Widget> children) =>
      Container(
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  Widget _field(
    FlutterFlowTheme theme, {
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.inter(color: theme.primaryText, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.inter(color: theme.secondaryText, fontSize: 13),
        hintStyle:
            GoogleFonts.inter(color: theme.secondaryText.withOpacity(0.5), fontSize: 13),
        prefixIcon: Icon(icon, color: theme.secondaryText, size: 18),
        filled: true,
        fillColor: theme.primaryBackground,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.alternate),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}
