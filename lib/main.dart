import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'flutter_flow/internationalization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_session.dart';
import 'components/notification_bell.dart';
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
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
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
  // TODO(W2): when the org switcher is built, persist the last-selected
  // org and restore that instead of the first membership row.
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
      final orgId =
          members.isNotEmpty ? members.first['org_id'] as String? : null;
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
        final planId = org == null ? null : org['plan_id'];
        if (planId != null) {
          final plan = await SupaFlow.client
              .from('subscription_plans')
              .select('name, limits, features')
              .eq('id', planId)
              .maybeSingle();
          if (plan != null) {
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
          AppSession.instance.setStaff(
            staffId: restoredStaffId,
            staffName: (meta['name'] as String?) ?? '',
            role: meta['staff_role'] as String?,
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
            orgActive: org == null ? true : (org['active'] as bool? ?? true),
            availableOrgs: availableOrgs,
          );
        }
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
    }
  }

  await FlutterFlowTheme.initialize();

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
  }

  void setLocale(String language) {
    safeSetState(() => _locale = createLocale(language));
    FFLocalizations.storeLocale(language);
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        _themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
      });

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'ArunPKRS',
      scrollBehavior: MyAppScrollBehavior(),
      localizationsDelegates: const [
        FFLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FallbackMaterialLocalizationDelegate(),
        FallbackCupertinoLocalizationDelegate(),
      ],
      locale: _locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ta'),
        Locale('kn'),
        Locale('ur'),
        Locale('gu'),
        Locale('ar'),
        Locale('fr'),
        Locale('de'),
        Locale('hi'),
        Locale('te'),
        Locale('ru'),
      ],
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: false,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: false,
      ),
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
/// Wide screens (>= 768 px): persistent collapsible left sidebar, like a
/// web app. Narrow screens: the original bottom navigation bar.
class _NavBarPageState extends State<NavBarPage> {
  String _currentPageName = 'HomePage';
  late Widget? _currentPage;

  /// Sidebar expanded (labels visible) vs collapsed (icons only).
  bool _railExpanded = true;

  static const _allNavItems = [
    (name: 'HomePage', icon: Icons.dashboard, label: 'Dashboard'),
    (name: 'OrdersPage', icon: Icons.assignment, label: 'Orders'),
    (name: 'LeadsPage', icon: Icons.people, label: 'Leads / CRM'),
    (name: 'OperationsPage', icon: Icons.local_shipping, label: 'Operations'),
    (name: 'PaymentsPage', icon: Icons.payments, label: 'Payments'),
    (name: 'ExpensePage', icon: Icons.receipt_long, label: 'Expenses'),
    (name: 'AccountsPage', icon: Icons.account_balance_wallet, label: 'Accounts'),
    (name: 'SalaryPage', icon: Icons.badge, label: 'Salary'),
    (name: 'UsersPage', icon: Icons.groups, label: 'Staff'),
    (name: 'FleetPage', icon: Icons.directions_car, label: 'Fleet'),
    (name: 'PLReportPage', icon: Icons.assessment, label: 'P & L'),
    (name: 'SettingsPage', icon: Icons.settings, label: 'Settings'),
  ];

  /// Role-based navigation. Staff PIN sessions are field users, not the
  /// owner: they only get the operational pages. Money (Payments, Expenses,
  /// Salary), Staff management, Fleet, Leads, and Settings stay owner-only.
  /// Combined with the customer-masking rules, this is the v1 supervisor
  /// restriction Arun asked for. (Server-side RLS hardening per-role is a
  /// v2 item; staff sessions ride the vendor's auth session by design.)
  List<({String name, IconData icon, String label})> get _navItems {
    if (AppSession.instance.currentStaffId == null) return _allNavItems;
    // Permission-driven sidebar (Bilty-style matrix in staff.permissions).
    // Falls back to the conservative field-crew set if permissions could
    // not be loaded for this session.
    final allowed = StaffPermissions.activeStaffPages ??
        const {'HomePage', 'OrdersPage', 'OperationsPage'};
    return _allNavItems.where((e) => allowed.contains(e.name)).toList();
  }

  @override
  void initState() {
    super.initState();
    _currentPageName = widget.initialPage ?? _currentPageName;
    _currentPage = widget.page;
  }

  Map<String, Widget> get _tabs => {
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
      };

  void _selectTab(int i) => safeSetState(() {
        _currentPage = null;
        _currentPageName = _navItems[i].name;
      });

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
  /// login before staff PINs work again.
  Future<void> _logout() async {
    try {
      await SupaFlow.client.auth.signOut();
    } catch (_) {}
    await StaffAuth.clearStoredVendorToken();
    StaffPermissions.clearActive();
    AppSession.instance.clear();
    if (mounted) context.go('/login');
  }

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

  Widget _themeChip(String label, ThemeMode mode) {
    final current = FlutterFlowTheme.themeMode;
    final selected = current == mode ||
        (current == ThemeMode.system &&
            ((mode == ThemeMode.dark) ==
                (Theme.of(context).brightness == Brightness.dark)));
    final primary = FlutterFlowTheme.of(context).primary;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          MyApp.of(context).setThemeMode(mode);
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
    if (AppSession.instance.isSuspended) {
      return _buildLockScreen(context, suspended: true);
    }
    if (AppSession.instance.isTrialExpired) {
      return _buildLockScreen(context, suspended: false);
    }
    final tabs = _tabs;
    // Direct-URL guard: a staff session typing /payments etc. into the
    // address bar gets bounced to the dashboard, matching the filtered nav.
    if (AppSession.instance.currentStaffId != null &&
        !_navItems.any((e) => e.name == _currentPageName) &&
        _currentPage == null) {
      _currentPageName = 'HomePage';
    }
    final currentIndex =
        _navItems.indexWhere((e) => e.name == _currentPageName);
    final body = _currentPage ?? tabs[_currentPageName];
    final isWide = MediaQuery.of(context).size.width >= 768;

    if (!isWide) {
      // ------- MOBILE: original bottom navigation -------
      return Scaffold(
        resizeToAvoidBottomInset: !widget.disableResizeToAvoidBottomInset,
        body: body,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex < 0 ? 0 : currentIndex,
          onTap: _selectTab,
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          selectedItemColor: FlutterFlowTheme.of(context).primary,
          unselectedItemColor: FlutterFlowTheme.of(context).secondaryText,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
          items: [
            for (final item in _navItems)
              BottomNavigationBarItem(
                icon: Icon(item.icon),
                label: '',
                tooltip: item.label,
              ),
          ],
        ),
      );
    }

    // ------- WIDE: persistent collapsible sidebar -------
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                        onPressed: () => safeSetState(
                            () => _railExpanded = !_railExpanded),
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
                                _themeChip('Light', ThemeMode.light),
                                const SizedBox(width: 6),
                                _themeChip('Dark', ThemeMode.dark),
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
                              tooltip: 'Toggle theme',
                              icon: Icon(
                                Theme.of(context).brightness == Brightness.dark
                                    ? Icons.light_mode
                                    : Icons.dark_mode,
                                size: 20,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                              onPressed: () => MyApp.of(context).setThemeMode(
                                Theme.of(context).brightness == Brightness.dark
                                    ? ThemeMode.light
                                    : ThemeMode.dark,
                              ),
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
