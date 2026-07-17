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
import 'index.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    try {
      final member = await SupaFlow.client
          .from('org_members')
          .select('org_id')
          .eq('user_id', restoredUser.id)
          .limit(1)
          .maybeSingle();
      final orgId = member == null ? null : member['org_id'] as String?;
      if (orgId != null) {
        final org = await SupaFlow.client
            .from('organizations')
            .select('name, slug, plan_id, trial_ends_at')
            .eq('id', orgId)
            .maybeSingle();

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
        AppSession.instance.setVendorSession(
          authUserId: restoredUser.id,
          orgId: orgId,
          orgName: org == null ? '' : (org['name'] as String? ?? ''),
          orgSlug: org == null ? '' : (org['slug'] as String? ?? ''),
          limits: limits,
          features: features,
          planName: planName,
          trialEndsAt: trialRaw is String ? DateTime.tryParse(trialRaw) : null,
        );
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

  static const _navItems = [
    (name: 'HomePage', icon: Icons.dashboard, label: 'Dashboard'),
    (name: 'OrdersPage', icon: Icons.assignment, label: 'Orders'),
    (name: 'LeadsPage', icon: Icons.people, label: 'Leads / CRM'),
    (name: 'OperationsPage', icon: Icons.local_shipping, label: 'Operations'),
    (name: 'PaymentsPage', icon: Icons.payments, label: 'Payments'),
    (name: 'ExpensePage', icon: Icons.receipt_long, label: 'Expenses'),
    (name: 'SalaryPage', icon: Icons.badge, label: 'Salary'),
    (name: 'FleetPage', icon: Icons.directions_car, label: 'Fleet'),
    (name: 'SettingsPage', icon: Icons.settings, label: 'Settings'),
  ];

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
        'SalaryPage': const SalaryPageWidget(),
        'FleetPage': const FleetPageWidget(),
        'SettingsPage': const SettingsPageWidget(),
      };

  void _selectTab(int i) => safeSetState(() {
        _currentPage = null;
        _currentPageName = _navItems[i].name;
      });

  /// Lock: keep the vendor's Supabase Auth session on the device (so
  /// staff PIN login still works — the Slack model), but clear the
  /// in-app session and return to the login screen.
  void _lockDevice() {
    AppSession.instance.clear();
    context.go('/login');
  }

  /// Logout: full sign-out. Removes the Supabase Auth session too, so
  /// the device needs a fresh vendor login before staff PINs work again.
  Future<void> _logout() async {
    try {
      await SupaFlow.client.auth.signOut();
    } catch (_) {}
    AppSession.instance.clear();
    if (mounted) context.go('/login');
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

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
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
                            children: [
                              Icon(Icons.local_shipping,
                                  color: FlutterFlowTheme.of(context).primary,
                                  size: 26),
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
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        fontSize: 15,
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
