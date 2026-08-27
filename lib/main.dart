import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_session_loader.dart';
import '/backend/approval_queue.dart';
import '/backend/survey_queue.dart';
import '/backend/auth_deep_link.dart';
import '/backend/device_org_binding.dart';
import '/backend/last_selected_org.dart';
import '/l10n/gen/app_localizations.dart';
import '/backend/crash_reporting.dart';
import '/backend/platform_admin_status.dart';
import '/backend/session_logout.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'flutter_flow/internationalization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_session.dart';
import 'components/coming_soon_page.dart';
import 'components/load_error_state.dart';
import 'components/mobile_bottom_nav.dart';
import 'components/nav_badge.dart';
import 'components/notification_bell.dart';
import 'nav_items.dart';
import 'permissions.dart';
import 'staff_auth.dart';
import 'index.dart';

/// Beta-hardening safety net (item 13, NAGARVA_STATUS.md): a widget that
/// throws during build previously showed Flutter's default red error
/// screen in debug and a blank/broken page in release — neither is
/// something to hand a beta user. Logs to console for now; swap the
/// `debugPrint` calls for a real crash-reporting SDK (Sentry etc.) once
/// the owner has an account/DSN for one — that's a genuine blocker this
/// pass can't fabricate without a real API key, same class of gap as
/// item 11's Razorpay keys.
void _installErrorHandlers() {
  // CHAIN, never replace. This runs inside initCrashReporting's
  // appRunner, i.e. AFTER SentryFlutter.init has installed its own
  // FlutterError.onError and PlatformDispatcher.onError. Overwriting
  // them — which this did until 20 Aug 2026 — silently disconnected
  // crash reporting from every Flutter framework error and every
  // uncaught async error, which is to say from every crash it exists to
  // catch. Nothing failed loudly: the unit tests and even the live
  // redaction test call Sentry.captureException directly and so never
  // touch this chain. Only running the real APK on a device showed it.
  //
  // `priorOnError` is Sentry's handler when a DSN is configured, and
  // Flutter's own presentError when it is not — so calling it covers
  // both cases, and replaces the explicit presentError that used to sit
  // here (calling both would double-present).
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    // Was exceptionAsString() only — the message, never the stack. That's
    // the "error boundary swallowing the stack trace" gap: a widget that
    // throws during build reaches this handler (Element.performRebuild
    // calls FlutterError.reportError before ErrorWidget.builder renders
    // the same `details` as the on-screen fallback), so this one line
    // covers every build/layout/paint error that produces "Something went
    // wrong loading this screen" — no separate logging needed inside
    // ErrorWidget.builder itself, since it never sees anything this
    // handler didn't already receive first. debugPrint no-ops in release
    // builds, so nothing extra reaches a shipped APK's logcat.
    debugPrint(
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}');
    priorOnError?.call(details);
  };
  final priorPlatformOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
    // Sentry's OnErrorIntegration lives here when a DSN is configured.
    priorPlatformOnError?.call(error, stack);
    return true; // handled — don't crash the isolate.
  };
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFFF5F5F5),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                SizedBox(height: 12),
                Text(
                  'Something went wrong loading this screen.\n'
                  'Try going back and reopening it.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
}

void main() async {
  // Crash reporting wraps the ENTIRE startup, including
  // WidgetsFlutterBinding and every await below, so a crash during
  // Supabase init or session restore is captured too — those are exactly
  // the failures a tester cannot describe usefully over WhatsApp.
  // No DSN configured -> this runs _startApp directly and changes
  // nothing.
  await initCrashReporting(_startApp);
}

Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();
  GoRouter.optionURLReflectsImperativeAPIs = true;
  usePathUrlStrategy();

  // Allow google_fonts to fetch font files at runtime. The proper v1
  // launch fix is to bundle Inter / InterTight TTFs in assets/fonts/
  // and declare them in pubspec.yaml, then set this back to false so
  // the app works offline (job sites often have poor data).
  // NOTE: if any other file sets this to false AFTER main() runs
  // (e.g. inside FlutterFlowTheme), that assignment wins — it must be
  // removed there too.
  GoogleFonts.config.allowRuntimeFetching = true;

  await SupaFlow.initialize();

  // Email-confirmation deep link, cold start — checked first, before the
  // ordinary session-recovery wait below, since a fresh confirmation is a
  // brand-new device/install with no persisted session to wait for at
  // all. On success this populates AppSession the same way the "restore
  // full session" block further down does, so that block's own
  // `AppSession.instance.currentOrgId == null` guard naturally skips —
  // no double-work, no conflict. See auth_deep_link.dart's own header.
  await AuthDeepLinkHandler.handleInitialLink();

  // supabase_flutter's local-storage session recovery (recoverSession())
  // runs in the background and is NOT awaited by Supabase.initialize() —
  // reading .currentUser immediately afterward can see null even though a
  // valid token is sitting in local storage, because recovery hasn't
  // resolved yet. This made every reload/cold-start land on LoginPage
  // instead of restoring the session (found testing item 1's "F5 while
  // logged in" case: the token was provably in localStorage but the app
  // showed the login screen anyway). Wait for the first auth-state event —
  // always AuthChangeEvent.initialSession once recovery finishes, session
  // or not — before trusting .currentUser, with a timeout as a safety net
  // in case the event already fired before this listener attached.
  final initialSessionSeen = Completer<void>();
  final authSub = SupaFlow.client.auth.onAuthStateChange.listen((state) {
    if (state.event == AuthChangeEvent.initialSession &&
        !initialSessionSeen.isCompleted) {
      initialSessionSeen.complete();
    }
  });
  if (SupaFlow.client.auth.currentUser == null) {
    await initialSessionSeen.future
        .timeout(const Duration(seconds: 5), onTimeout: () {});
  }
  await authSub.cancel();

  // Restore the full session on app start (browser reload / cold start).
  // Supabase restores the auth user automatically, but AppSession is
  // only populated during the login flow — without this, org-scoped
  // queries trip the OrgScope guard rail and pages render blank, and
  // isAuthenticated / plan gating silently break after a reload.
  // Mirrors the vendor login flow: member -> org -> plan -> session.
  final restoredUser = SupaFlow.client.auth.currentUser;
  if (restoredUser != null && AppSession.instance.currentOrgId == null) {
    // Shadow staff users (minted by the staff-login Edge Function) are
    // marked with user_metadata.kind == 'staff'. On reload they must be
    // restored as STAFF (filtered sidebar, no money KPIs) — never as a
    // vendor, or a browser refresh would silently grant owner-level UI.
    final meta = restoredUser.userMetadata ?? const <String, dynamic>{};
    final restoredStaffId =
        meta['kind'] == 'staff' ? meta['staff_id'] as String? : null;
    try {
      // Every membership, not just the first — item 9's org switcher
      // needs availableOrgs populated here too, not just on a fresh
      // login. Found live-testing item 12's suspension lock screen: the
      // "Switch Organization" button never appeared after a page reload
      // because this query (unlike login_page_widget.dart's, fixed when
      // the switcher was built) still only ever restored the first
      // membership row and never populated availableOrgs at all.
      final members = await SupaFlow.client
          .from('org_members')
          .select('org_id, role')
          .eq('user_id', restoredUser.id);
      // TODO(W2) resolved: prefer the org this device last explicitly
      // switched to (LastSelectedOrg — set on login and on Settings'
      // "Switch Organization") over always restoring the first
      // org_members row, but only when that saved id is still one of
      // this user's real memberships; otherwise fall back to
      // members.first exactly as before this existed. Pure UX nicety,
      // not a security boundary — see last_selected_org.dart's own doc
      // comment.
      final memberOrgIds = members
          .map((m) => m['org_id'] as String?)
          .whereType<String>()
          .toSet();
      final savedOrgId = await LastSelectedOrg.get();
      final orgId = (savedOrgId != null && memberOrgIds.contains(savedOrgId))
          ? savedOrgId
          : (members.isNotEmpty ? members.first['org_id'] as String? : null);
      if (orgId != null) {
        // select('*') on purpose: naming logo_url here would 400 the whole
        // restore on a DB that hasn't run 20260717_org_logo_url.sql yet.
        final org = await SupaFlow.client
            .from('organizations')
            .select('*')
            .eq('id', orgId)
            .maybeSingle();

        // Same availableOrgs build as login_page_widget.dart's — silent
        // restore always keeps using the first membership (no picker on
        // a background reload), but the switcher needs the full list
        // populated regardless of which one ends up active.
        List<OrgMembershipInfo> availableOrgs = [];
        if (restoredStaffId == null || restoredStaffId.isEmpty) {
          final orgIds = members
              .map((m) => m['org_id'] as String?)
              .whereType<String>()
              .toSet()
              .toList();
          if (orgIds.length > 1) {
            final orgRows = await SupaFlow.client
                .from('organizations')
                .select('id, name')
                .inFilter('id', orgIds);
            final orgNameById = {
              for (final o in orgRows) o['id'] as String: o['name'] as String?
            };
            availableOrgs = members
                .map((m) => OrgMembershipInfo(
                      orgId: m['org_id'] as String,
                      orgName: orgNameById[m['org_id']] ?? '(unnamed org)',
                      role: m['role'] as String?,
                    ))
                .toList();
          }
        }

        Map<String, dynamic> limits = {};
        Map<String, dynamic> features = {};
        String? planName;
        // Item 32: grace_days drives the trial banner's read-only
        // timing. Defaults to 7 for an org whose plan predates the
        // column — never 0, which would skip grace entirely and lock the
        // moment the trial ended. Same fallback as
        // org_session_loader.dart, which is the equivalent path for
        // login and org-switch (this one is session RESTORE).
        int graceDays = 7;
        final planId = org == null ? null : org['plan_id'];
        if (planId != null) {
          final plan = await SupaFlow.client
              .from('subscription_plans')
              .select('name, limits, features, grace_days')
              .eq('id', planId)
              .maybeSingle();
          if (plan != null) {
            if (plan['grace_days'] is int) {
              graceDays = plan['grace_days'] as int;
            }
            if (plan['limits'] is Map) {
              limits = Map<String, dynamic>.from(plan['limits'] as Map);
            }
            if (plan['features'] is Map) {
              features = Map<String, dynamic>.from(plan['features'] as Map);
            }
            planName = plan['name'] as String?;
          }
        }

        final trialRaw = org == null ? null : org['trial_ends_at'];
        if (restoredStaffId != null && restoredStaffId.isNotEmpty) {
          // Staff session restore: staff identity + org context only.
          // role reads from appMetadata, not userMetadata (17 Aug 2026)
          // — see staff-login/index.ts's header comment for why:
          // userMetadata is client-writable via updateUser(), appMetadata
          // is not. This is a display/UI-preset convenience read only —
          // real authorization is Item 30's live RLS lookups, not this.
          AppSession.instance.setStaff(
            staffId: restoredStaffId,
            staffName: (meta['name'] as String?) ?? '',
            role: restoredUser.appMetadata['staff_role'] as String?,
          );
          await StaffPermissions.loadForStaff(restoredStaffId);
          AppSession.instance.setOrgOnly(
            orgId: orgId,
            orgName: org == null ? null : org['name'] as String?,
            orgSlug: org == null ? null : org['slug'] as String?,
            logoUrl: org == null ? null : org['logo_url'] as String?,
            limits: limits,
            features: features,
            planName: planName,
            planStatus: org == null ? null : org['plan_status'] as String?,
            trialEndsAt:
                trialRaw is String ? DateTime.tryParse(trialRaw) : null,
            graceDays: graceDays,
            orgActive: org == null ? true : (org['active'] as bool? ?? true),
          );
        } else {
          AppSession.instance.setVendorSession(
            authUserId: restoredUser.id,
            orgId: orgId,
            orgName: org == null ? '' : (org['name'] as String? ?? ''),
            orgSlug: org == null ? '' : (org['slug'] as String? ?? ''),
            logoUrl: org == null ? null : org['logo_url'] as String?,
            limits: limits,
            features: features,
            planName: planName,
            planStatus: org == null ? null : org['plan_status'] as String?,
            trialEndsAt:
                trialRaw is String ? DateTime.tryParse(trialRaw) : null,
            graceDays: graceDays,
            orgActive: org == null ? true : (org['active'] as bool? ?? true),
            availableOrgs: availableOrgs,
          );
          await refreshPlatformAdminStatus();
        }
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
    }
  }

  await FlutterFlowTheme.initialize();
  await NotificationPrefs.initialize();
  await DeviceOrgBinding.initialize();

  await FFLocalizations.initialize();

  runApp(
    ChangeNotifierProvider.value(
      value: AppSession.instance,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  State<MyApp> createState() => _MyAppState();

  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;
}

class MyAppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class _MyAppState extends State<MyApp> {
  Locale? _locale = FFLocalizations.getStoredLocale();

  ThemeMode _themeMode = FlutterFlowTheme.themeMode;

  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;
  String getRoute([RouteMatch? routeMatch]) {
    final RouteMatch lastMatch =
        routeMatch ?? _router.routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : _router.routerDelegate.currentConfiguration;
    return matchList.uri.path;
  }

  List<String> getRouteStack() =>
      _router.routerDelegate.currentConfiguration.matches
          .map((e) => getRoute(e))
          .toList();
  @override
  void initState() {
    super.initState();

    _appStateNotifier = AppStateNotifier.instance;
    _router = createRouter(_appStateNotifier);
    // Email-confirmation deep link, warm resume (the app was already
    // running when the link arrived) — cold start is handled separately,
    // before runApp(), in main(). See auth_deep_link.dart's own header.
    AuthDeepLinkHandler.startListening(_router);
  }

  void setLocale(String language) {
    safeSetState(() => _locale = createLocale(language));
    FFLocalizations.storeLocale(language);
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        _themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
      });

  /// Parity brief Part 2b: 'light' / 'dark' / 'midnight'. Midnight rides
  /// ThemeMode.dark (same brightness) with FlutterFlowTheme.isMidnight
  /// picking MidnightModeTheme's darker backgrounds over DarkModeTheme's.
  void setThemeVariant(String variant) => safeSetState(() {
        final mode = variant == 'light' ? ThemeMode.light : ThemeMode.dark;
        _themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
        FlutterFlowTheme.saveMidnight(variant == 'midnight');
      });

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'ArunPKRS',
      scrollBehavior: MyAppScrollBehavior(),
      localizationsDelegates: const [
        // NG-055 (27 Aug 2026): the gen_l10n class, generated from
        // lib/l10n/*.arb per l10n.yaml. Every string that used to be
        // `FFLocalizations.getText('<8-char id>')` now resolves through
        // here instead.
        AppLocalizations.delegate,
        // FFLocalizations stays registered during the transition — it
        // still owns locale PERSISTENCE (storeLocale/getStoredLocale,
        // which setLocale below calls) and languages(). Only the string
        // lookup moved. Removing this delegate would break locale
        // persistence, not just translations.
        FFLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FallbackMaterialLocalizationDelegate(),
        FallbackCupertinoLocalizationDelegate(),
      ],
      locale: _locale,
      // Tier 1 only (27 Aug 2026). Must stay in step with
      // FFLocalizations.languages() — Flutter resolves an unsupported
      // locale to supportedLocales.first, so a locale listed here but
      // absent there (or vice versa) produces a silently wrong language
      // rather than an error. The seven dropped entries were FlutterFlow
      // export defaults, never a product decision; `ar`/`ur` additionally
      // imply RTL, which this app has never been laid out for.
      supportedLocales: const [
        Locale('en'),
        Locale('ta'),
        Locale('hi'),
        Locale('kn'),
      ],
      // Item 9: these used to be bare `ThemeData(brightness: ...)` with no
      // brand colours at all, so every Material-themed widget that
      // (correctly) doesn't hardcode its own colours — Drawer, ListTile,
      // SearchDelegate's search field, dialogs, bottom sheets — resolved
      // against stock Material defaults and visibly ignored the theme
      // switch. Now derived from the same palette FlutterFlowTheme uses.
      //
      // darkTheme is chosen by variant, not just brightness: Midnight
      // rides ThemeMode.dark, so without this Dark and Midnight handed
      // back an identical ThemeData and no Material widget could tell
      // them apart.
      theme: LightModeTheme().toThemeData(),
      darkTheme: FlutterFlowTheme.isMidnight
          ? MidnightModeTheme().toThemeData()
          : DarkModeTheme().toThemeData(),
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }
}

class NavBarPage extends StatefulWidget {
  const NavBarPage({
    super.key,
    this.initialPage,
    this.page,
    this.disableResizeToAvoidBottomInset = false,
  });

  final String? initialPage;
  final Widget? page;
  final bool disableResizeToAvoidBottomInset;

  @override
  _NavBarPageState createState() => _NavBarPageState();
}

/// This is the private State class that goes with NavBarPage.
/// Wide screens (>= 600 px, parity brief Part 5c/5d): persistent
/// collapsible left rail, like a web app — tablet (600-1024dp) and
/// desktop (>1024dp) share the same rail; nothing distinguishes them
/// beyond how much horizontal space happens to be available. Narrow
/// screens (<600dp): the custom MobileBottomNav (Part 5a/5b).
class _NavBarPageState extends State<NavBarPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String _currentPageName = 'HomePage';
  late Widget? _currentPage;

  /// Sidebar expanded (labels visible) vs collapsed (icons only).
  /// Parity brief Part 5c: this choice must persist across sessions —
  /// loaded from SharedPreferences in initState, saved on every toggle.
  bool _railExpanded = true;
  static const _kRailExpandedKey = '__rail_expanded__';

  /// Scroll-aware bottom nav (parity brief Part 5b): hidden while the
  /// user scrolls down, revealed while scrolling up. Deliberately driven
  /// only by UserScrollNotification.direction — no idle timer anywhere,
  /// so the nav can never vanish while the user is simply stationary.
  ///
  /// NG-FIX brief, bug 2a (7 Aug 2026): this used to be a plain bool
  /// (`_navVisible`) driving `MobileBottomNav`'s own internal
  /// `AnimatedSlide`, which only moved the bar's paint offset — the
  /// `Scaffold` kept reserving its full layout height regardless, so
  /// hiding the bar left a dead band at the bottom instead of returning
  /// that space to the body. `_navAnimController` now drives a
  /// `SizeTransition` around `MobileBottomNav` at the `bottomNavigationBar`
  /// call site instead (1.0 = full height/shown, 0.0 = zero height/
  /// hidden), so `Scaffold` actually reclaims the space. `_navVisible`
  /// stays as the cheap "which way are we already animating" guard so a
  /// stream of scroll notifications during one gesture doesn't restart
  /// forward()/reverse() every frame.
  bool _navVisible = true;
  late final AnimationController _navAnimController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1.0,
  );

  /// Users Kickoff Step 2: three genuinely different destination sets,
  /// not one list filtered three ways — see nav_items.dart's own header
  /// for why supervisor/field-staff aren't just a permission-filtered
  /// subset of the owner's 19 items. `navItemsForCurrentSession()` picks
  /// the right base set (and computes "staff"'s dynamic label); the
  /// per-person permission matrix is layered on top of it here, but only
  /// for owner/manager sessions — supervisor/field-staff sets are fixed
  /// by role and were never permission-matrix-driven in the first place.
  List<NavItem> get _navItems {
    final base = navItemsForCurrentSession();
    if (AppSession.instance.currentStaffId == null)
      return base; // owner/vendor: no filter at all
    if (!isOwnerOrManagerSession)
      return base; // supervisor/field-staff: fixed set
    // Manager: permission-driven subset of the 19/27, same mechanism as
    // before Step 2. activeStaffPages must already be loaded by the time
    // this is read — build()'s _needsStaffPermissions guard shows a
    // loading/error screen instead of reaching here while it's null, so
    // there is no fallback guess left to make (see the 8 Aug 2026 fix
    // below: the old hardcoded {Dashboard, Orders, Operations} default
    // silently substituted a wrong-in-both-directions permission set
    // instead of surfacing the failure).
    final allowed = StaffPermissions.activeStaffPages ?? const <String>{};
    return base.where((e) => allowed.contains(e.name)).toList();
  }

  // ----------------------------------------------------------------------
  // NG-FIX (8 Aug 2026): a manager session's nav set depends on
  // StaffPermissions.activeStaffPages having been populated by
  // StaffPermissions.loadForStaff() at login. One of the three places that
  // establish a staff session (pin_login_page_widget.dart) was missing
  // that call entirely — fixed alongside this — but the load itself can
  // still fail (network hiccup, RLS issue) or this page could in principle
  // build before a session-restore's own load finishes. Previously
  // _navItems just guessed {Dashboard, Orders, Operations} in that case,
  // silently and wrong in both directions. Now: log it, and gate the
  // whole page behind an explicit loading/error state — never render
  // _navItems/_tabs while activeStaffPages is null for a manager session.
  // ----------------------------------------------------------------------
  bool _permissionsLoadFailed = false;

  bool get _needsStaffPermissions =>
      isOwnerOrManagerSession &&
      AppSession.instance.currentStaffId != null &&
      StaffPermissions.activeStaffPages == null;

  Future<void> _loadStaffPermissions() async {
    if (!_needsStaffPermissions) return;
    final staffId = AppSession.instance.currentStaffId!;
    debugPrint('Staff permissions not loaded for manager session '
        '$staffId — loading now.');
    if (_permissionsLoadFailed)
      safeSetState(() => _permissionsLoadFailed = false);
    await StaffPermissions.loadForStaff(staffId);
    if (!mounted) return;
    final failed = StaffPermissions.activeStaffPages == null;
    if (failed) {
      debugPrint('Staff permissions load failed for manager session $staffId.');
    }
    safeSetState(() => _permissionsLoadFailed = failed);
  }

  Widget _buildPermissionsGate(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      body: Center(
        child: _permissionsLoadFailed
            ? LoadErrorState(
                message: 'Could not load your permissions.',
                onRetry: _loadStaffPermissions,
              )
            : const CircularProgressIndicator(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Users Kickoff Step 2.2/2.3 "Home redirect": only applied when the
    // caller didn't already ask for a specific landing page (e.g. a deep
    // link) — a fresh login/session-restore has no widget.initialPage,
    // so this is where a supervisor/field-staff session actually lands
    // on their own home instead of the owner's Dashboard.
    _currentPageName = widget.initialPage ?? homeNavNameForCurrentSession();
    _currentPage = widget.page;
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_kRailExpandedKey);
      if (saved != null && mounted) safeSetState(() => _railExpanded = saved);
    });
    // Seed the Operations badge so a job awaiting approval is visible
    // without having to open Operations first — the whole point of the
    // badge. Owner/manager only: no other session type has Operations in
    // its nav set, so the count would render nowhere.
    if (isOwnerOrManagerSession) {
      ApprovalQueue.instance.refresh();
      // Session 4, Part B1: same reasoning as ApprovalQueue — a submitted
      // survey waiting for review should be visible without opening
      // Surveys first.
      SurveyQueue.instance.refresh();
    }
    // Fire-and-forget, same style as the SharedPreferences load above —
    // no-ops immediately if activeStaffPages is already populated (the
    // normal case now that every setStaff() call site also loads it).
    _loadStaffPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navAnimController.dispose();
    super.dispose();
  }

  /// Item 32 follow-up (18 Aug 2026): re-read the org's plan and trial
  /// state whenever the app comes back to the foreground.
  ///
  /// `AppSession` was previously populated once — at login, org switch or
  /// session restore — and never refreshed. So a trial that lapsed
  /// overnight, or a plan changed in Super Admin, didn't take effect until
  /// the vendor happened to log out and back in. That was already wrong
  /// (the DB enforces the real limits either way, so the app could show a
  /// vendor a banner contradicting what the server would actually do), and
  /// it becomes a money problem once Item 31 lands and plan state decides
  /// what someone has paid for.
  ///
  /// Deliberately cheap and best-effort: one row from `organizations`
  /// plus its plan, on resume only. A failure here leaves the previous
  /// values in place rather than clearing them — a network blip must not
  /// make a paying vendor look unpaid.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    final orgId = AppSession.instance.currentOrgId;
    if (orgId == null) return;
    () async {
      try {
        final data = await loadOrgSessionData(orgId);
        if (!mounted) return;
        AppSession.instance.setOrgOnly(
          orgId: data.orgId,
          limits: data.limits,
          features: data.features,
          planName: data.planName,
          planStatus: data.planStatus,
          trialEndsAt: data.trialEndsAt,
          graceDays: data.graceDays,
          orgActive: data.orgActive,
        );
      } catch (_) {
        // Keep whatever we had — see doc comment.
      }
    }();
  }

  void _setRailExpanded(bool expanded) {
    safeSetState(() => _railExpanded = expanded);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_kRailExpandedKey, expanded));
  }

  Map<String, Widget> get _tabs {
    if (!isOwnerOrManagerSession) {
      // Supervisor/field-staff destinations.
      //
      // THIS MAP IS THE REAL ROUTER FOR BOTTOM-NAV TABS. NavBarPage renders
      // `tabs[_currentPageName]` directly; tapping a nav item calls
      // _selectTab, which only sets _currentPageName. It never goes through
      // GoRouter, so registering an FFRoute in nav.dart is NOT enough to
      // make a nav destination reachable — that only covers direct URLs and
      // context.pushNamed. Session 2 built five real supervisor screens,
      // registered their routes, and updated nav_items.dart, but left this
      // map's blanket `for (item in _navItems) -> ComingSoonPage`, so every
      // one of them still rendered a stub on a real supervisor session.
      // `flutter analyze` cannot catch that: it's a runtime string-keyed
      // map lookup, not a compile-time reference.
      //
      // Listed explicitly rather than looped, so adding a screen means
      // editing one obvious line here and a stub is visibly a stub.
      //
      // 'SupervisorEntryPage' and 'StaffTeamAttendance' intentionally
      // absent, in lockstep with their removal from kSupervisorNavItems
      // (nav_items.dart) — Job Entry isn't needed (supervisors work
      // assigned jobs), Team Attendance was redundant with My Team.
      // Nothing in _navItems can produce those names anymore, so no
      // ComingSoonPage fallback is needed for them either.
      return {
        'SupervisorJobsListPage': const SupervisorJobsListPageWidget(),
        'SupervisorTeamPage': const SupervisorTeamPageWidget(),
        'SupervisorEarningsPage': const SupervisorEarningsPageWidget(),
        'SupervisorAttendancePage': const SupervisorAttendancePageWidget(),
        // Field staff (driver/helper/packer) — their own two destinations
        // are still unbuilt. Note the supervisor Earnings/Attendance
        // screens above query by currentStaffId and would work for any
        // role, but pointing field staff at them is a scope call for Arun,
        // not something to do silently here.
        'MyAttComingSoon': const ComingSoonPage(title: 'My Attendance'),
        'MySalComingSoon': const ComingSoonPage(title: 'My Earnings'),
      };
    }
    return {
      'HomePage': const HomePageWidget(),
      'OrdersPage': const OrdersPageWidget(),
      'LeadsPage': const LeadsPageWidget(),
      'OperationsPage': const OperationsPageWidget(),
      'PaymentsPage': const PaymentsPageWidget(),
      'ExpensePage': const ExpensePageWidget(),
      'AccountsPage': const AccountsPageWidget(),
      'SalaryPage': const SalaryPageWidget(),
      'UsersPage': const UsersPageWidget(),
      'FleetPage': const FleetPageWidget(),
      'PLReportPage': const PLReportPageWidget(),
      'SettingsPage': const SettingsPageWidget(),
      // Newly reachable from nav (Users Kickoff Step 2.1) — none of these
      // three were in the old 12-item nav either, so they were only ever
      // reachable by typing their route directly. Real pages, not
      // placeholders — see nav_items.dart's correction note.
      'CalendarPage': const CalendarPageWidget(),
      'MaterialsPage': const MaterialsPageWidget(),
      'ReportsPage': const ReportsPageWidget(),
      // Genuinely unbuilt (Step 2.1: "route to a Coming soon placeholder").
      // Session 4, Part B1/B2/B3/B4: real screens now — see nav_items.dart's
      // matching name changes (both must agree; _tabs is the actual router
      // for bottom-nav/drawer taps, nav.dart's FFRoute only covers direct
      // URLs — the exact gap that left all 6 supervisor screens
      // unreachable in an earlier session, see that changelog entry).
      'ReviewsPage': const ReviewsPageWidget(),
      'WaInboxPage': const WaInboxPageWidget(),
      'SurveyQuoteHubPage': const SurveyQuoteHubPageWidget(),
      'CustomerSurveysPage': const CustomerSurveysPageWidget(),
      'RateCardsPage': const RateCardsPageWidget(),
      'LrRegisterPage': const LrRegisterPageWidget(),
      'OperationsStandalonePage': const OperationsStandalonePageWidget(),
      'VendorsPage': const VendorsPageWidget(),
      'CustomersPage': const CustomersPageWidget(),
      'InsuranceClaimsPage': const InsuranceClaimsPageWidget(),
      'TripsPage': const TripsPageWidget(),
      'TasksPage': const TasksPageWidget(),
    };
  }

  // Platform Admin is the one nav entry with no matching key in `_tabs` —
  // it's SuperAdminPageWidget, a real full-screen GoRouter route already
  // proven working at direct-URL access, not a page meant to be embedded
  // as one more swapped tab body inside this Scaffold's own chrome (it
  // has its own AppBar/tabs already). Routed via pushNamed instead of the
  // tab-swap so the same onTap(index) callback both the rail (line ~1000)
  // and MobileBottomNav funnel through can stay a single, ungated handler.
  void _selectTab(int i) {
    final item = _navItems[i];
    if (item.name == SuperAdminPageWidget.routeName) {
      context.pushNamed(SuperAdminPageWidget.routeName);
      return;
    }
    safeSetState(() {
      _currentPage = null;
      _currentPageName = item.name;
    });
  }

  /// Lock behaviour under the session-swap model:
  /// - STAFF session active: restore the saved vendor session first
  ///   (StaffAuth.lockToVendor, Option A) so the device is back on the
  ///   vendor's auth — staff PIN unlock keeps working and no staff
  ///   session lingers. If the restore fails (no stored token), fall
  ///   back to a full sign-out so a staff session is never left behind.
  /// - VENDOR session active: unchanged — keep the vendor's Supabase
  ///   Auth session on the device (the Slack model), clear only the
  ///   in-app session, return to the login screen.
  Future<void> _lockDevice() async {
    if (AppSession.instance.currentStaffId != null) {
      final restored = await StaffAuth.lockToVendor();
      if (!restored) {
        try {
          await SupaFlow.client.auth.signOut();
        } catch (_) {}
      }
    }
    StaffPermissions.clearActive();
    AppSession.instance.clear();
    if (mounted) context.go('/login');
  }

  /// Logout: full sign-out. Removes the Supabase Auth session AND the
  /// stored vendor refresh token, so the device needs a fresh vendor
  /// login before staff PINs work again. Shared with the supervisor
  /// overflow menu via performLogout — one real logout sequence.
  Future<void> _logout() => performLogout(context);

  /// Per-tenant logo in the sidebar header. Uses
  /// AppSession.currentOrgLogoUrl (organizations.logo_url) when set;
  /// falls back to the truck icon in a rounded amber chip so the header
  /// never renders blank for orgs without a logo.
  Widget _orgLogo({double size = 34}) {
    final url = AppSession.instance.currentOrgLogoUrl;
    final primary = FlutterFlowTheme.of(context).primary;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.local_shipping, color: primary, size: size * 0.62),
    );
    if (url == null || url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _themeChip(String label, String variant) {
    final selected = FlutterFlowTheme.effectiveVariant(context) == variant;
    final primary = FlutterFlowTheme.of(context).primary;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          MyApp.of(context).setThemeVariant(variant);
          safeSetState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            border: Border.all(
                color: selected
                    ? primary
                    : FlutterFlowTheme.of(context).secondaryText),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : FlutterFlowTheme.of(context).primaryText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _footerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: FlutterFlowTheme.of(context).primaryText,
        side: BorderSide(
            color: FlutterFlowTheme.of(context).secondaryText.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  /// Item 11's trial-expiry lock, extended in the super-admin console pass
  /// (NAGARVA_STATUS.md) to also cover Step 3's tenant suspension —
  /// AppSession.isSuspended reuses this exact screen per that task's own
  /// instruction ("must hit the same lock screen as trial-expiry... reuse
  /// it, don't build a second one"), just with different copy and no
  /// "View Plans" upsell (a suspension isn't a self-serve billing problem).
  /// Replaces the whole tab shell rather than just hiding one page, so
  /// nothing org-scoped (money figures, customer data) renders while
  /// locked out. Settings and Logout aren't reachable as normal nav tabs
  /// in this state, so Logout gets its own button here.
  /// Item 32's trial ladder (Arun's decision, 18 Aug 2026 — read-only
  /// over hard lock, 7-day grace):
  ///   - last 7 days of the trial  -> informational banner, full access
  ///   - trial ended, in grace     -> warning banner, still full access
  ///   - grace also passed         -> read-only banner, creates blocked
  ///
  /// The block itself is server-side (`assert_org_writable()`, called by
  /// every enforcement trigger). This banner exists so the vendor knows
  /// WHY a save is about to fail, rather than meeting a raw error — the
  /// same reasoning as the FY-rollover prompt. Never hides the page.
  Widget? _withTrialBanner(BuildContext context, Widget? body) {
    if (body == null) return body;
    final s = AppSession.instance;
    if (s.planStatus != 'trial' || s.trialEndsAt == null) return body;

    final readOnly = s.isReadOnly;
    final inGrace = s.isInTrialGrace;
    final daysLeft = s.trialDaysRemaining;
    // Stay quiet until the last week — a banner from day 1 of a 30-day
    // trial is just noise the vendor learns to ignore.
    if (!readOnly && !inGrace && daysLeft > 7) return body;

    final theme = FlutterFlowTheme.of(context);
    final Color bg;
    final IconData icon;
    final String message;
    if (readOnly) {
      bg = theme.error;
      icon = Icons.lock_outline;
      message = 'Your trial has ended. You can still view and export '
          'everything — upgrade to add new records.';
    } else if (inGrace) {
      final left = s.daysUntilReadOnly;
      bg = Colors.orange.shade800;
      icon = Icons.warning_amber_rounded;
      message = left <= 0
          ? 'Your trial has ended. Upgrade today to keep adding records.'
          : 'Trial ended — $left day${left == 1 ? '' : 's'} left before '
              'your account becomes read-only.';
    } else {
      bg = theme.primary;
      icon = Icons.schedule;
      message = daysLeft <= 0
          ? 'Your trial ends today.'
          : '$daysLeft day${daysLeft == 1 ? '' : 's'} left in your trial.';
    }

    return Column(
      children: [
        Material(
          color: bg,
          child: InkWell(
            onTap: () => context.push(PlanPageWidget.routePath),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    Icon(icon, size: 17, color: Colors.white),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(message,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              height: 1.3,
                              fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 8),
                    const Text('View Plans',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline)),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildLockScreen(BuildContext context, {required bool suspended}) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    suspended
                        ? Icons.block_outlined
                        : Icons.lock_clock_outlined,
                    size: 48,
                    color: suspended ? theme.error : theme.primary),
                const SizedBox(height: 16),
                Text(
                  suspended ? 'Account suspended' : 'Your trial has ended',
                  style: TextStyle(
                    color: theme.primaryText,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  suspended
                      ? '${AppSession.instance.currentOrgName ?? 'This account'} has been suspended. Contact Nagarva support to reactivate.'
                      : 'Upgrade your plan to keep using ${AppSession.instance.currentOrgName ?? 'Nagarva'}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.secondaryText, fontSize: 13.5),
                ),
                const SizedBox(height: 24),
                if (!suspended)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.push(PlanPageWidget.routePath),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('View Plans'),
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton(onPressed: _logout, child: const Text('Logout')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Suspension is still a hard lock — a suspended tenant is a platform
    // decision, not a self-serve billing state.
    if (AppSession.instance.isSuspended) {
      return _buildLockScreen(context, suspended: true);
    }
    // Item 32 / Arun's decision 18 Aug 2026: an expired trial is NO LONGER
    // a hard lock. It used to replace the whole shell with the lock
    // screen, which meant a vendor lost access to their own live job data
    // the morning their trial ran out. Now they keep full read access
    // (and export) forever, and lose the ability to CREATE records once
    // the grace window has also passed — enforced server-side by
    // assert_org_writable(), so this is presentation, not the gate.
    // See _trialBanner below for what they actually see.
    if (_needsStaffPermissions) {
      return _buildPermissionsGate(context);
    }
    final tabs = _tabs;
    // Direct-URL guard: a staff session typing /payments etc. into the
    // address bar gets bounced to the dashboard, matching the filtered nav.
    // Was a hardcoded 'HomePage' fallback — a supervisor/field-staff
    // session has no such tab (see the nav.dart HomePage route's own
    // note), so this "fix" just replaced one invalid page name with
    // another, rendering nothing (`tabs['HomePage']` is absent from
    // their `_tabs` map) instead of correcting anything. Same
    // role-aware fallback as that route now uses.
    if (AppSession.instance.currentStaffId != null &&
        !_navItems.any((e) => e.name == _currentPageName) &&
        _currentPage == null) {
      _currentPageName = homeNavNameForCurrentSession();
    }
    final currentIndex =
        _navItems.indexWhere((e) => e.name == _currentPageName);
    // Item 32: the trial ladder is a banner above whatever page is
    // showing, in both layouts — never a replacement for the page.
    //
    // KeyedSubtree keyed on the active org (18 Aug 2026): every entry in
    // `_tabs` is an unkeyed `const` widget, so Flutter matches them by
    // runtimeType and REUSES their State — including each page's
    // `_model`, which holds the last list it fetched. Switching org
    // therefore left the previous org's rows on screen until something
    // else forced a rebuild. SettingsPage's switcher tried to solve this
    // with `context.go(HomePageWidget.routePath)` under a comment
    // claiming a "full route rebuild", but tab switching never changes
    // the URL (see _selectTab — it only setStates `_currentPageName`),
    // so from the Settings TAB that call navigates to the location the
    // user is already on and GoRouter does nothing. Keying the subtree
    // by org id makes the stale case structurally impossible: the org
    // changes, the key changes, the State is disposed and initState
    // re-runs against the new org.
    final body = _withTrialBanner(
      context,
      KeyedSubtree(
        key: ValueKey('org:${AppSession.instance.currentOrgId}'),
        child: _currentPage ?? tabs[_currentPageName] ?? const SizedBox.shrink(),
      ),
    );
    // Parity brief Part 5c: tablet (600-1024dp) gets the same collapsible
    // rail as desktop (>1024dp, Part 5d — "existing sidebar unchanged")
    // rather than the cramped bottom nav a 768dp cutoff used to force on
    // small tablets. Below 600dp: MobileBottomNav (Part 5a/5b).
    final isWide = MediaQuery.of(context).size.width >= 600;

    if (!isWide) {
      // ------- MOBILE: custom bottom nav (parity brief Part 5a/5b) -------
      return Scaffold(
        resizeToAvoidBottomInset: !widget.disableResizeToAvoidBottomInset,
        body: NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            // Scroll-aware only — no idle timer anywhere, so the nav can
            // never disappear while the user is simply stationary.
            if (notification.direction == ScrollDirection.reverse) {
              if (_navVisible) {
                _navVisible = false;
                _navAnimController.reverse();
              }
            } else if (notification.direction == ScrollDirection.forward) {
              if (!_navVisible) {
                _navVisible = true;
                _navAnimController.forward();
              }
            }
            return false;
          },
          child: body ?? const SizedBox.shrink(),
        ),
        // NG-FIX brief, bug 2a: SizeTransition around the bar (not an
        // internal AnimatedSlide inside MobileBottomNav) so the Scaffold's
        // reserved bottomNavigationBar height actually shrinks to zero
        // when hidden, instead of leaving a dead band the same height as
        // the bar. extendBody stays false (default) — the bar keeps
        // participating in layout, it just animates to zero height.
        bottomNavigationBar: SizeTransition(
          sizeFactor: _navAnimController,
          axisAlignment: -1,
          child: MobileBottomNav(
            items: _navItems,
            currentIndex: currentIndex < 0 ? 0 : currentIndex,
            onTap: _selectTab,
          ),
        ),
      );
    }

    // ------- WIDE (tablet 600-1024dp + desktop >1024dp): persistent
    // collapsible sidebar -------
    return Scaffold(
      resizeToAvoidBottomInset: !widget.disableResizeToAvoidBottomInset,
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: _railExpanded ? 230 : 72,
            color: FlutterFlowTheme.of(context).secondaryBackground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: brand + collapse toggle
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    mainAxisAlignment: _railExpanded
                        ? MainAxisAlignment.spaceBetween
                        : MainAxisAlignment.center,
                    children: [
                      if (_railExpanded)
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _orgLogo(size: 34),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      AppSession.instance.currentOrgName ??
                                          'Nagarva',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        fontSize: 13.5,
                                        height: 1.15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      AppSession.instance.currentStaffName ??
                                          'Owner',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      // In-app notifications: new leads (vendor) and order
                      // assignments (supervisor). Realtime badge + popup.
                      // Expanded-only: collapsed rail is 72px and bell +
                      // toggle together would overflow it.
                      if (_railExpanded) const NotificationBell(),
                      IconButton(
                        tooltip: _railExpanded ? 'Collapse' : 'Expand',
                        icon: Icon(
                          _railExpanded
                              ? Icons.chevron_left
                              : Icons.chevron_right,
                          color: FlutterFlowTheme.of(context).secondaryText,
                        ),
                        onPressed: () => _setRailExpanded(!_railExpanded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Nav items
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _navItems.length,
                    itemBuilder: (context, i) {
                      final item = _navItems[i];
                      final selected = i == currentIndex;
                      final primary = FlutterFlowTheme.of(context).primary;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Material(
                          color: selected
                              ? primary.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _selectTab(i),
                            child: Tooltip(
                              message: _railExpanded ? '' : item.label,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 11),
                                child: Row(
                                  mainAxisAlignment: _railExpanded
                                      ? MainAxisAlignment.start
                                      : MainAxisAlignment.center,
                                  children: [
                                    if (item.name == 'OperationsPage')
                                      ValueListenableBuilder<int>(
                                        valueListenable:
                                            ApprovalQueue.instance.pendingCount,
                                        builder: (context, count, _) =>
                                            NavBadgeIcon(
                                          icon: item.icon,
                                          size: 22,
                                          color: selected
                                              ? primary
                                              : FlutterFlowTheme.of(context)
                                                  .secondaryText,
                                          count: count,
                                        ),
                                      )
                                    else if (item.name == 'CustomerSurveysPage')
                                      ValueListenableBuilder<int>(
                                        valueListenable: SurveyQueue
                                            .instance.unreviewedCount,
                                        builder: (context, count, _) =>
                                            NavBadgeIcon(
                                          icon: item.icon,
                                          size: 22,
                                          color: selected
                                              ? primary
                                              : FlutterFlowTheme.of(context)
                                                  .secondaryText,
                                          count: count,
                                        ),
                                      )
                                    else
                                      Icon(
                                        item.icon,
                                        size: 22,
                                        color: selected
                                            ? primary
                                            : FlutterFlowTheme.of(context)
                                                .secondaryText,
                                      ),
                                    if (_railExpanded) ...[
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.label,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: selected
                                                ? primary
                                                : FlutterFlowTheme.of(context)
                                                    .primaryText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // ---------- Footer: theme + lock/logout ----------
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: _railExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'THEME',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _themeChip('Light', 'light'),
                                const SizedBox(width: 6),
                                _themeChip('Dark', 'dark'),
                                const SizedBox(width: 6),
                                _themeChip('Midnight', 'midnight'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _footerButton(
                                    icon: Icons.lock_outline,
                                    label: 'Lock',
                                    onTap: _lockDevice,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _footerButton(
                                    icon: Icons.logout,
                                    label: 'Logout',
                                    onTap: _logout,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            IconButton(
                              tooltip: 'Toggle theme (Light/Dark/Midnight)',
                              icon: Icon(
                                Theme.of(context).brightness == Brightness.dark
                                    ? Icons.light_mode
                                    : Icons.dark_mode,
                                size: 20,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                              // Collapsed rail has no room for 3 chips —
                              // cycles light -> dark -> midnight -> light.
                              onPressed: () {
                                const order = ['light', 'dark', 'midnight'];
                                final next = order[(order.indexOf(
                                            FlutterFlowTheme.effectiveVariant(
                                                context)) +
                                        1) %
                                    order.length];
                                MyApp.of(context).setThemeVariant(next);
                              },
                            ),
                            IconButton(
                              tooltip: 'Lock',
                              icon: Icon(Icons.lock_outline,
                                  size: 20,
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText),
                              onPressed: _lockDevice,
                            ),
                            IconButton(
                              tooltip: 'Logout',
                              icon: Icon(Icons.logout,
                                  size: 20,
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText),
                              onPressed: _logout,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: body ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}
