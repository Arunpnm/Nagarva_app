import '/app_session.dart';
import '/backend/device_org_binding.dart';
import '/backend/last_selected_org.dart';
import '/backend/session_logout.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/org_session_loader.dart';
import '/components/notification_bell.dart';
import '/components/org_switcher_sheet.dart';
import '/main.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/components/keyboard_scroll_view.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'business_settings_section.dart';
import 'settings_page_model.dart';
export 'settings_page_model.dart';

/// App settings and profile.
class SettingsPageWidget extends StatefulWidget {
  const SettingsPageWidget({super.key});

  static String routeName = 'SettingsPage';
  static String routePath = '/settings';

  @override
  State<SettingsPageWidget> createState() => _SettingsPageWidgetState();
}

class _SettingsPageWidgetState extends State<SettingsPageWidget> {
  late SettingsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SettingsPageModel());
    _model.notificationsEnabled = NotificationPrefs.popupsEnabled;

    // Was hardcoded placeholder data (CLAUDE.md known bug #4) — load the
    // real business profile for the signed-in org.
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      final orgId = AppSession.instance.currentOrgId;
      if (orgId != null) {
        final orgs = await OrganizationsTable().queryRows(
          queryFn: (q) => q.eq('id', orgId).limit(1),
        );
        _model.org = orgs.isNotEmpty ? orgs.first : null;
        safeSetState(() {});
      }
      final porterRows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'porter_enabled'),
      );
      _model.porterEnabled = porterRows.isNotEmpty &&
          (porterRows.first.value ?? '').toLowerCase() == 'true';
      safeSetState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  /// Same tri-state selector as main.dart's desktop-sidebar `_themeChip`,
  /// styled as an inline row segment for this settings card.
  Widget _themeVariantChip(BuildContext context, String label, String variant) {
    final selected = FlutterFlowTheme.effectiveVariant(context) == variant;
    final theme = FlutterFlowTheme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => MyApp.of(context).setThemeVariant(variant),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.primary : Colors.transparent,
            border: Border.all(
                color: selected ? theme.primary : theme.secondaryText),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : theme.primaryText,
            ),
          ),
        ),
      ),
    );
  }

  /// Language names are shown in their OWN script, never transliterated
  /// and never in English. A picker that lists "Tamil" in Latin script is
  /// useless to the person who most needs it — the crew member who cannot
  /// read English is the reason this control exists. Keys must match
  /// `FFLocalizations.languages()`.
  static const Map<String, String> _kLanguageNames = {
    'en': 'English',
    'ta': 'தமிழ்',
    'hi': 'हिन्दी',
    'kn': 'ಕನ್ನಡ',
  };

  /// Same segmented-chip pattern as [_themeVariantChip] above.
  ///
  /// Note this switches the app locale immediately and persists it via
  /// `FFLocalizations.storeLocale`, so it survives a restart. Coverage is
  /// currently partial by construction — only the 18 FlutterFlow-export
  /// pages read from the translation map, and none of its non-English
  /// slots are filled yet, so today every locale renders English via the
  /// fallback added in internationalization.dart. That is the intended
  /// interim state: the control and the plumbing land first, the strings
  /// follow. It must never render blank, which is what the fallback fix
  /// guarantees.
  Widget _languageChip(BuildContext context, String code) {
    final selected = FFLocalizations.of(context).languageCode == code;
    final theme = FlutterFlowTheme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => MyApp.of(context).setLocale(code),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.primary : Colors.transparent,
            border: Border.all(
                color: selected ? theme.primary : theme.secondaryText),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            _kLanguageNames[code] ?? code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : theme.primaryText,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            AppLocalizations.of(context).settings,
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w600,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleLarge.fontStyle,
                  ),
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w600,
                  fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
                ),
          ),
          actions: const [],
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryBackground,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: KeyboardScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context)
                                    .primaryBackground,
                                borderRadius: BorderRadius.circular(32.0),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Icon(
                                  Icons.person,
                                  color: FlutterFlowTheme.of(context).primary,
                                  size: 36.0,
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppSession.instance.currentStaffName ??
                                      AppSession.instance.currentOrgName ??
                                      AppLocalizations.of(context).arunPackersStaff,
                                  style: FlutterFlowTheme.of(context)
                                      .titleMedium
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .titleMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleMedium
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  _model.org?.email ??
                                      AppLocalizations.of(context).adminArunpackersIn,
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                              ].divide(const SizedBox(height: 4.0)),
                            ),
                          ].divide(const SizedBox(width: 16.0)),
                        ),
                      ),
                    ),
                    // Vendor preferences — Porter toggle. Persisted to the
                    // org-scoped settings table ('porter_enabled') and read
                    // by the dashboard to show/hide the Porter KPI card.
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 4.0),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Porter integration',
                            style: FlutterFlowTheme.of(context)
                                .titleSmall
                                .override(
                                  font: GoogleFonts.interTight(),
                                  letterSpacing: 0.0,
                                ),
                          ),
                          subtitle: Text(
                            'Show Porter commission on the dashboard. Turn on '
                            'only if your business uses Porter.',
                            style: FlutterFlowTheme.of(context)
                                .bodySmall
                                .override(
                                  font: GoogleFonts.inter(),
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText,
                                  letterSpacing: 0.0,
                                ),
                          ),
                          value: _model.porterEnabled,
                          activeColor: FlutterFlowTheme.of(context).primary,
                          onChanged: (v) async {
                            safeSetState(() => _model.porterEnabled = v);
                            await SettingsTable().upsert(
                              {
                                'key': 'porter_enabled',
                                ...OrgScope.stamp(),
                                'value': v.toString(),
                                'updated_at':
                                    DateTime.now().toIso8601String(),
                              },
                              onConflict: 'org_id,key',
                            );
                          },
                        ),
                      ),
                    ),
                    // Parity brief Part 7: owners set their own PIN here,
                    // logged in the normal (email/password) way — this is
                    // the only path that can set a PIN in the first place,
                    // since the PIN screen itself has nothing to check
                    // against until one exists. Staff-only sessions never
                    // reach this page's normal route (SettingsPage isn't in
                    // the staff nav set), so no staff-vs-owner gate is
                    // needed beyond that.
                    if (AppSession.instance.currentStaffId == null)
                      const _PinSettingCard(),
                    // Vendor self-service branding: business details, logo,
                    // e-signature — all feed the invoice PDF.
                    const BusinessSettingsSection(),
                    // Item 12: survey catalogue + vehicle/crew slabs. Moved
                    // here from the Survey & Quote hub (the catalogue half)
                    // per Arun 17 Aug 2026 — both pricing editors live in
                    // one Settings entry now.
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color:
                            FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.local_shipping_outlined,
                            color: FlutterFlowTheme.of(context).primary),
                        title: Text(
                          'Survey & Pricing',
                          style: GoogleFonts.interTight(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: FlutterFlowTheme.of(context).primaryText,
                          ),
                        ),
                        subtitle: Text(
                          'CFT item catalogue and vehicle/crew slabs',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.pushNamed(SurveyPricingPage.routeName),
                      ),
                    ),
                    // NO "Branches" entry here, deliberately (27 Aug 2026).
                    //
                    // Nagarva's model is ORG-PER-LOCATION: Bengaluru and
                    // Mysuru are two separate orgs, each with its own
                    // staff, vehicles, accounts, orders and licence — not
                    // two branches of one org. `branches` survives only as
                    // an FK target (22 tables carry a branch value) with
                    // exactly one seeded 'Head Office' row per org.
                    //
                    // A "Branches" card in Settings would teach the wrong
                    // mental model to every vendor who opened it, which is
                    // a real cost for a screen with nothing to manage.
                    // BranchesPage still EXISTS and is still routed — it is
                    // reachable from New Order's zero-branch empty state
                    // and by direct URL, both of which are recovery paths
                    // rather than navigation. See NAGARVA_MODULE_STATUS.md
                    // section 10 before re-adding this.
                    // Item 11.6: recycle bin. Owner-only, same gate as the
                    // PIN card above.
                    if (AppSession.instance.currentStaffId == null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color:
                              FlutterFlowTheme.of(context).secondaryBackground,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: ListTile(
                          leading: Icon(Icons.restore_from_trash,
                              color: FlutterFlowTheme.of(context).primary),
                          title: Text(
                            'Deleted Items',
                            style: GoogleFonts.interTight(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: FlutterFlowTheme.of(context).primaryText,
                            ),
                          ),
                          subtitle: Text(
                            'Restore anything deleted in the last 90 days',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.pushNamed(RecycleBinPage.routeName),
                        ),
                      ),
                    // Help & About. NOT owner-gated, unlike the cards
                    // above — a staff session needs the support contact
                    // and the legal links just as much, and Play Store
                    // review expects the privacy policy reachable from a
                    // normal session, not only an owner's.
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.help_outline,
                            color: FlutterFlowTheme.of(context).primary),
                        title: Text(
                          'Help & About',
                          style: GoogleFonts.interTight(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: FlutterFlowTheme.of(context).primaryText,
                          ),
                        ),
                        subtitle: Text(
                          'Support, privacy policy, terms and app version',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.pushNamed(HelpAboutPage.routeName),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0, 10.0, 16.0, 10.0),
                                child: Text(
                                  AppLocalizations.of(context).company,
                                  style: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontStyle,
                                      ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0, 14.0, 16.0, 14.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.business,
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      size: 20.0,
                                    ),
                                    Container(
                                      width: 14.0,
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            AppLocalizations.of(context).businessName,
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontStyle,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .primaryText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                          ),
                                          Text(
                                            _model.org?.name ??
                                                AppSession
                                                    .instance.currentOrgName ??
                                                AppLocalizations.of(context).settingsPageArunPackersAndCouriers,
                                            style: FlutterFlowTheme.of(context)
                                                .bodySmall
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontStyle,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodySmall
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodySmall
                                                          .fontStyle,
                                                ),
                                          ),
                                        ].divide(const SizedBox(height: 2.0)),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                      size: 18.0,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0, 14.0, 16.0, 14.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.phone,
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      size: 20.0,
                                    ),
                                    Container(
                                      width: 14.0,
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            AppLocalizations.of(context).phone,
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontStyle,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .primaryText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                          ),
                                          Text(
                                            _model.org?.phone ??
                                                AppLocalizations.of(context).n9144XxxxXxxx,
                                            style: FlutterFlowTheme.of(context)
                                                .bodySmall
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontStyle,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodySmall
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodySmall
                                                          .fontStyle,
                                                ),
                                          ),
                                        ].divide(const SizedBox(height: 2.0)),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                      size: 18.0,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0, 14.0, 16.0, 14.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.receipt,
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      size: 20.0,
                                    ),
                                    Container(
                                      width: 14.0,
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            AppLocalizations.of(context).gstNumber,
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontStyle,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .primaryText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                          ),
                                          Text(
                                            _model.org?.gstin ??
                                                AppLocalizations.of(context).xxxxxxxxxxxx,
                                            style: FlutterFlowTheme.of(context)
                                                .bodySmall
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontStyle,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodySmall
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodySmall
                                                          .fontStyle,
                                                ),
                                          ),
                                        ].divide(const SizedBox(height: 2.0)),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                      size: 18.0,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0, 10.0, 16.0, 10.0),
                                child: Text(
                                  AppLocalizations.of(context).app,
                                  style: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontStyle,
                                      ),
                                ),
                              ),
                            ),
                            // Notifications — was a static "Enabled" row with
                            // no control at all (parity brief Part 2a). Now a
                            // real per-device switch gating the disruptive
                            // in-app popup only (see NotificationPrefs doc
                            // comment) — the bell's badge/list still show
                            // everything regardless.
                            SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0, 14.0, 16.0, 14.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.notifications,
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      size: 20.0,
                                    ),
                                    Container(
                                      width: 14.0,
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Notifications',
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontWeight,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .primaryText,
                                                  letterSpacing: 0.0,
                                                ),
                                          ),
                                          Text(
                                            _model.notificationsEnabled
                                                ? 'In-app popups on'
                                                : 'In-app popups off',
                                            style: FlutterFlowTheme.of(context)
                                                .bodySmall
                                                .override(
                                                  font: GoogleFonts.inter(),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryText,
                                                  letterSpacing: 0.0,
                                                ),
                                          ),
                                        ].divide(const SizedBox(height: 2.0)),
                                      ),
                                    ),
                                    Switch(
                                      value: _model.notificationsEnabled,
                                      activeThumbColor:
                                          FlutterFlowTheme.of(context).primary,
                                      onChanged: (v) {
                                        safeSetState(
                                            () => _model.notificationsEnabled = v);
                                        NotificationPrefs.setPopupsEnabled(v);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Dark Mode — was a static "On" row with no
                            // control (parity brief Part 2a/2b). Now a real
                            // Light/Dark/Midnight selector, the same control
                            // the desktop sidebar already has, finally
                            // available on mobile too.
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  16.0, 6.0, 16.0, 14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.dark_mode,
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        size: 20.0,
                                      ),
                                      const SizedBox(width: 14.0),
                                      Text(
                                        'Theme',
                                        style: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .override(
                                              font: GoogleFonts.inter(
                                                fontWeight:
                                                    FlutterFlowTheme.of(
                                                            context)
                                                        .bodyMedium
                                                        .fontWeight,
                                              ),
                                              color: FlutterFlowTheme.of(
                                                      context)
                                                  .primaryText,
                                              letterSpacing: 0.0,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10.0),
                                  Row(
                                    children: [
                                      _themeVariantChip(context, 'Light', 'light'),
                                      const SizedBox(width: 6),
                                      _themeVariantChip(context, 'Dark', 'dark'),
                                      const SizedBox(width: 6),
                                      _themeVariantChip(
                                          context, 'Midnight', 'midnight'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Language (NG-055, 27 Aug 2026). FFLocalizations
                            // has been wired into main.dart since the
                            // FlutterFlow export — delegate registered,
                            // setLocale implemented, locale persisted — but
                            // setLocale had NO caller anywhere outside
                            // main.dart itself, so the feature was
                            // unreachable by a user. This is that caller.
                            // Deliberately not owner-gated: a driver or
                            // packer is exactly who needs it.
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  16.0, 6.0, 16.0, 14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.language,
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        size: 20.0,
                                      ),
                                      const SizedBox(width: 14.0),
                                      Text(
                                        'Language',
                                        style: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .override(
                                              font: GoogleFonts.inter(
                                                fontWeight:
                                                    FlutterFlowTheme.of(
                                                            context)
                                                        .bodyMedium
                                                        .fontWeight,
                                              ),
                                              color: FlutterFlowTheme.of(
                                                      context)
                                                  .primaryText,
                                              letterSpacing: 0.0,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10.0),
                                  Row(
                                    children: [
                                      for (final code
                                          in FFLocalizations.languages()) ...[
                                        _languageChip(context, code),
                                        if (code !=
                                            FFLocalizations.languages().last)
                                          const SizedBox(width: 6),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (AppSession.instance.availableOrgs.length > 1)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            0.0, 16.0, 0.0, 0.0),
                        child: FFButtonWidget(
                          onPressed: () async {
                            final chosen = await showOrgSwitcherSheet(context);
                            if (chosen == null ||
                                chosen == AppSession.instance.currentOrgId) {
                              return;
                            }
                            final sessionData =
                                await loadOrgSessionData(chosen);
                            AppSession.instance.setVendorSession(
                              authUserId: AppSession.instance.authUserId!,
                              orgId: sessionData.orgId,
                              orgName: sessionData.orgName,
                              orgSlug: sessionData.orgSlug,
                              logoUrl: sessionData.logoUrl,
                              limits: sessionData.limits,
                              features: sessionData.features,
                              planName: sessionData.planName,
                              planStatus: sessionData.planStatus,
                              trialEndsAt: sessionData.trialEndsAt,
                              graceDays: sessionData.graceDays,
                              orgActive: sessionData.orgActive,
                            );
                            // TODO(W2) resolved: persist this switch so a
                            // later reload restores the same org instead
                            // of falling back to the first org_members
                            // row. See last_selected_org.dart's doc
                            // comment.
                            await LastSelectedOrg.set(sessionData.orgId);
                            // CORRECTED 18 Aug 2026. This used to claim a
                            // "full route rebuild so every org-scoped page
                            // re-queries" — it does no such thing. Tab
                            // switching never changes the URL (main.dart's
                            // _selectTab only setStates `_currentPageName`),
                            // so from the Settings TAB this navigates to
                            // the location the user is already on and
                            // GoRouter does nothing at all.
                            //
                            // What actually clears stale data is the
                            // KeyedSubtree keyed on currentOrgId in
                            // main.dart's build. This go() is kept only to
                            // land the user back on the Dashboard after
                            // switching, which is the sensible place to
                            // arrive — it is NOT the mechanism, and must
                            // not be relied on as one.
                            if (mounted) {
                              context.go(HomePageWidget.routePath);
                            }
                          },
                          text: 'Switch Organization',
                          icon: const Icon(
                            Icons.swap_horiz,
                            size: 20.0,
                          ),
                          options: FFButtonOptions(
                            width: double.infinity,
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 0.0, 0.0),
                            iconPadding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 0.0, 0.0),
                            iconColor: FlutterFlowTheme.of(context).primary,
                            color: Colors.transparent,
                            textStyle: TextStyle(
                              color: FlutterFlowTheme.of(context).primary,
                            ),
                            borderSide: BorderSide(
                              color: FlutterFlowTheme.of(context).primary,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(0.0, 16.0, 0.0, 16.0),
                      child: FFButtonWidget(
                        onPressed: () => performLogout(context),
                        text: AppLocalizations.of(context).logout,
                        icon: const Icon(
                          Icons.logout,
                          size: 20.0,
                        ),
                        options: FFButtonOptions(
                          width: double.infinity,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconColor: FlutterFlowTheme.of(context).primary,
                          color: Colors.transparent,
                          textStyle: TextStyle(
                            color: FlutterFlowTheme.of(context).primary,
                          ),
                          borderSide: BorderSide(
                            color: FlutterFlowTheme.of(context).primary,
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),

                  ].divide(const SizedBox(height: 16.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Set/change the PIN used by the unified PIN login screen (parity brief
/// Part 7). Writes org_members.pin (write-only — the
/// org_members_hash_pin_trigger in 20260728_org_pin_login.sql bcrypt-hashes
/// it into pin_hash and never stores the plaintext), matched on the
/// current authenticated user's own row so a vendor can only ever set
/// their own PIN, never another org's.
class _PinSettingCard extends StatefulWidget {
  const _PinSettingCard();

  @override
  State<_PinSettingCard> createState() => _PinSettingCardState();
}

class _PinSettingCardState extends State<_PinSettingCard> {
  final _pinController = TextEditingController();
  bool _saving = false;
  String? _message;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinController.text.trim();
    if (pin.length != 4 || int.tryParse(pin) == null) {
      setState(() => _message = 'Enter exactly 4 digits.');
      return;
    }
    final userId = SupaFlow.client.auth.currentUser?.id;
    final activeOrgId = AppSession.instance.currentOrgId;
    if (userId == null || activeOrgId == null) return;

    // WHICH ORG DOES A PIN BELONG TO? (27 Aug 2026)
    //
    // The PIN lives on `org_members`, which is UNIQUE (org_id, user_id)
    // — so it is per (org, user). An owner of three orgs has three
    // separate PINs.
    //
    // This used to write against `currentOrgId` unconditionally, while
    // the PIN LOGIN screen reads `DeviceOrgBinding.boundOrgId`. Switch
    // org in Settings, set a PIN, and it lands on the active org while
    // the bound device keeps checking the other one — the PIN is
    // correct, stored, and unusable. Found live 27 Aug 2026 by exactly
    // that sequence.
    //
    // Same class as the PIN-login bug fixed the same day (see
    // org_resolution.dart): `AppSession.currentOrgId` and
    // `DeviceOrgBinding.boundOrgId` are two answers to one question.
    //
    // Resolution: when the device is BOUND, the bound org is the only
    // org this PIN could ever sign into, so that is what we write —
    // but we SAY SO first rather than silently targeting a company the
    // header does not name. Unbound, the active org is right and no
    // notice is needed.
    final boundOrgId = DeviceOrgBinding.boundOrgId;
    var orgId = activeOrgId;
    if (boundOrgId != null &&
        boundOrgId.isNotEmpty &&
        boundOrgId != activeOrgId) {
      final boundName = DeviceOrgBinding.boundOrgName ?? 'another organization';
      final activeName = AppSession.instance.currentOrgName ?? 'the current one';
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Which organization?'),
          content: Text(
            'This device signs in to $boundName. Setting a PIN here will '
            'apply to $boundName, not $activeName.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text('Set for $boundName')),
          ],
        ),
      );
      if (proceed != true) return;
      orgId = boundOrgId;
    }

    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await OrgMembersTable().update(
        data: {'pin': pin},
        matchingRows: (q) =>
            q.eq('org_id', orgId).eq('user_id', userId),
      );
      _pinController.clear();
      setState(() => _message = 'PIN updated.');
    } catch (e) {
      setState(() => _message = 'Could not update PIN: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12.0),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('App PIN',
              style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700, color: theme.primaryText)),
          const SizedBox(height: 4),
          Text(
            'Set or change the 4-digit PIN used to sign in on this and '
            'other devices.',
            style:
                GoogleFonts.inter(fontSize: 12.5, color: theme.secondaryText),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration:
                      const InputDecoration(labelText: 'New PIN', counterText: ''),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white),
                  child: Text(_saving ? 'Saving...' : 'Save'),
                ),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_message!,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: theme.secondaryText)),
            ),
        ],
      ),
    );
  }
}
