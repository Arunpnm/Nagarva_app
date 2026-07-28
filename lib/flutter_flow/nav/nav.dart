import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/main.dart';
import '/app_session.dart';
import '/flutter_flow/flutter_flow_util.dart';

import '/index.dart';

export 'package:go_router/go_router.dart';
export 'serialization_util.dart';

const kTransitionInfoKey = '__transition_info__';

GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class AppStateNotifier extends ChangeNotifier {
  AppStateNotifier._();

  static AppStateNotifier? _instance;
  static AppStateNotifier get instance => _instance ??= AppStateNotifier._();

  bool showSplashImage = true;

  void stopShowingSplashImage() {
    showSplashImage = false;
    notifyListeners();
  }
}

// Routes reachable without an AppSession — everything else bounces to
// /login. Found missing during item 1's retest: navigating straight to
// e.g. /calendar after Logout rendered the page with empty data instead
// of redirecting, since nothing but each page's own queries enforced
// auth. main() fully awaits Supabase session restore before runApp() (see
// main.dart), so this can't race a still-restoring session on cold start.
const _kPublicRoutePrefixes = ['/login', '/signup', '/survey', '/quote'];

bool _isPublicRoute(String path) =>
    path == '/' || _kPublicRoutePrefixes.any((p) => path.startsWith(p));

/// Refresh-after-write fix (parity brief Part 1, 27 Jul 2026).
///
/// Root cause: NavBarPage swaps its single `body` slot between tab widgets
/// (Home/Orders/Leads/... — see main.dart's `_tabs`/`_currentPage`), so a
/// tab's State is created once and reused for as long as that tab stays
/// selected. Every list/dashboard page fetched its data once in `initState`
/// with no way to know a route pushed on top of it (RecordPaymentPage,
/// NewOrderPage, a staff-advance sheet, ...) had written new data — popping
/// back just revealed the same State object with its stale in-memory list.
/// Switching tabs "fixed" it only because that path *does* dispose/recreate
/// the State, which is what made this look like a per-screen quirk instead
/// of one systemic gap.
///
/// Fix: a single RouteObserver on the root Navigator, subscribed to by every
/// affected page via the RefreshOnPopMixin below. `didPopNext()` fires
/// exactly when a route pushed on top of a subscribed page is popped, so
/// each page can re-run its existing load method without needing every push
/// call site to be awaited/chained individually.
///
/// Typed on [ModalRoute] rather than [PageRoute]: several of the write
/// surfaces this needs to catch (StaffLedgerSheet's Pay/Advance/Settle,
/// staff_form_sheet, plan_edit_sheet, ...) are `showModalBottomSheet`/
/// `showDialog` routes, which are [PopupRoute]s, not [PageRoute]s — both
/// extend [ModalRoute], which is the common type that covers full pushed
/// pages, dialogs, and bottom sheets alike. `RouteObserver.didPop` only
/// fires when both the popped route and the route below it match the
/// observer's generic type, so `PageRoute` would silently miss every
/// sheet/dialog dismissal.
final RouteObserver<ModalRoute<dynamic>> nagarvaRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();

/// Mix into a page's State to re-fetch data whenever a route pushed on top
/// of it is popped. Implement [onPageRefresh] to call the page's existing
/// load method (e.g. `_loadData()`); everything else is handled here.
mixin RefreshOnPopMixin<T extends StatefulWidget> on State<T>
    implements RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      nagarvaRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    nagarvaRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void didPushNext() {}

  @override
  void didPopNext() => onPageRefresh();

  /// Called when this page becomes visible again after a route pushed on
  /// top of it was popped — re-run the page's data load here.
  void onPageRefresh();
}

GoRouter createRouter(AppStateNotifier appStateNotifier) => GoRouter(
      initialLocation: '/',
      debugLogDiagnostics: true,
      refreshListenable: appStateNotifier,
      navigatorKey: appNavigatorKey,
      observers: [nagarvaRouteObserver],
      errorBuilder: (context, state) => const LoginPageWidget(),
      redirect: (context, state) {
        final path = state.uri.path;
        if (_isPublicRoute(path)) return null;
        if (!AppSession.instance.isAuthenticated) {
          return LoginPageWidget.routePath;
        }
        return null;
      },
      routes: [
        FFRoute(
          name: '_initialize',
          path: '/',
          builder: (context, _) => const LoginPageWidget(),
        ),
        FFRoute(
          name: LoginPageWidget.routeName,
          path: LoginPageWidget.routePath,
          builder: (context, params) => const LoginPageWidget(),
        ),
        FFRoute(
          name: HomePageWidget.routeName,
          path: HomePageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? const NavBarPage(initialPage: 'HomePage')
              : const HomePageWidget(),
        ),
        FFRoute(
          name: OrdersPageWidget.routeName,
          path: OrdersPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? const NavBarPage(initialPage: 'OrdersPage')
              : const OrdersPageWidget(),
        ),
        FFRoute(
          name: LeadsPageWidget.routeName,
          path: LeadsPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? const NavBarPage(initialPage: 'LeadsPage')
              : const LeadsPageWidget(),
        ),
        FFRoute(
          name: OperationsPageWidget.routeName,
          path: OperationsPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? const NavBarPage(initialPage: 'OperationsPage')
              : const OperationsPageWidget(),
        ),
        FFRoute(
          name: PaymentsPageWidget.routeName,
          path: PaymentsPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? const NavBarPage(initialPage: 'PaymentsPage')
              : const PaymentsPageWidget(),
        ),
        FFRoute(
          name: ExpensePageWidget.routeName,
          path: ExpensePageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? const NavBarPage(initialPage: 'ExpensePage')
              : const ExpensePageWidget(),
        ),
        FFRoute(
          name: SalaryPageWidget.routeName,
          path: SalaryPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? const NavBarPage(initialPage: 'SalaryPage')
              : const SalaryPageWidget(),
        ),
        FFRoute(
          name: FleetPageWidget.routeName,
          path: FleetPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? const NavBarPage(initialPage: 'FleetPage')
              : const FleetPageWidget(),
        ),
        FFRoute(
          name: QuotationPageWidget.routeName,
          path: QuotationPageWidget.routePath,
          builder: (context, params) => const QuotationPageWidget(),
        ),
        FFRoute(
          name: SurveyQuotePageWidget.routeName,
          path: SurveyQuotePageWidget.routePath,
          builder: (context, params) => SurveyQuotePageWidget(
            leadId: params.getParam('leadId', ParamType.String),
            leadCustomer: params.getParam('leadCustomer', ParamType.String),
            leadPhone: params.getParam('leadPhone', ParamType.String),
            leadFromCity: params.getParam('leadFromCity', ParamType.String),
            leadToCity: params.getParam('leadToCity', ParamType.String),
          ),
        ),
        FFRoute(
          name: AccountsPageWidget.routeName,
          path: AccountsPageWidget.routePath,
          builder: (context, params) => const AccountsPageWidget(),
        ),
        FFRoute(
          name: PLReportPageWidget.routeName,
          path: PLReportPageWidget.routePath,
          builder: (context, params) => const PLReportPageWidget(),
        ),
        FFRoute(
          name: SettingsPageWidget.routeName,
          path: SettingsPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? const NavBarPage(initialPage: 'SettingsPage')
              : const SettingsPageWidget(),
        ),
        FFRoute(
          name: CalendarPageWidget.routeName,
          path: CalendarPageWidget.routePath,
          builder: (context, params) => const CalendarPageWidget(),
        ),
        FFRoute(
          name: SuperAdminPageWidget.routeName,
          path: SuperAdminPageWidget.routePath,
          builder: (context, params) => const SuperAdminPageWidget(),
        ),
        FFRoute(
          name: MaterialsPageWidget.routeName,
          path: MaterialsPageWidget.routePath,
          builder: (context, params) => const MaterialsPageWidget(),
        ),
        FFRoute(
          name: ReportsPageWidget.routeName,
          path: ReportsPageWidget.routePath,
          builder: (context, params) => const ReportsPageWidget(),
        ),
        FFRoute(
          name: UsersPageWidget.routeName,
          path: UsersPageWidget.routePath,
          builder: (context, params) => const UsersPageWidget(),
        ),
        FFRoute(
          name: RecordPaymentPageWidget.routeName,
          path: RecordPaymentPageWidget.routePath,
          builder: (context, params) => RecordPaymentPageWidget(
            orderId: params.getParam('orderId', ParamType.String),
          ),
        ),
        FFRoute(
          name: QuickExpensePageWidget.routeName,
          path: QuickExpensePageWidget.routePath,
          builder: (context, params) => const QuickExpensePageWidget(),
        ),
        FFRoute(
          name: NewOrderPageWidget.routeName,
          path: NewOrderPageWidget.routePath,
          builder: (context, params) => NewOrderPageWidget(
            orderId: params.getParam('orderId', ParamType.String),
          ),
        ),
        FFRoute(
          name: OrderDetailPageWidget.routeName,
          path: OrderDetailPageWidget.routePath,
          builder: (context, params) => OrderDetailPageWidget(
            orderId: params.getParam(
              'orderId',
              ParamType.String,
            ),
            orderCustomer: params.getParam(
              'orderCustomer',
              ParamType.String,
            ),
            orderPhone: params.getParam(
              'orderPhone',
              ParamType.String,
            ),
            orderFromCity: params.getParam(
              'orderFromCity',
              ParamType.String,
            ),
            orderToCity: params.getParam(
              'orderToCity',
              ParamType.String,
            ),
            orderFromAddress: params.getParam(
              'orderFromAddress',
              ParamType.String,
            ),
            orderToAddress: params.getParam(
              'orderToAddress',
              ParamType.String,
            ),
            orderFromFloor: params.getParam(
              'orderFromFloor',
              ParamType.String,
            ),
            orderToFloor: params.getParam(
              'orderToFloor',
              ParamType.String,
            ),
            orderMoveDate: params.getParam(
              'orderMoveDate',
              ParamType.String,
            ),
            orderAmount: params.getParam(
              'orderAmount',
              ParamType.String,
            ),
            orderAdvancePaid: params.getParam(
              'orderAdvancePaid',
              ParamType.String,
            ),
            orderStatus: params.getParam(
              'orderStatus',
              ParamType.String,
            ),
            orderPaymentStatus: params.getParam(
              'orderPaymentStatus',
              ParamType.String,
            ),
            orderTrackingStatus: params.getParam(
              'orderTrackingStatus',
              ParamType.String,
            ),
            orderService: params.getParam(
              'orderService',
              ParamType.String,
            ),
            orderBranch: params.getParam(
              'orderBranch',
              ParamType.String,
            ),
            orderType: params.getParam(
              'orderType',
              ParamType.String,
            ),
            orderNotes: params.getParam(
              'orderNotes',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: NewLeadPageWidget.routeName,
          path: NewLeadPageWidget.routePath,
          builder: (context, params) => NewLeadPageWidget(
            leadId: params.getParam('leadId', ParamType.String),
          ),
        ),
        FFRoute(
          name: LeadDetailPageWidget.routeName,
          path: LeadDetailPageWidget.routePath,
          builder: (context, params) => LeadDetailPageWidget(
            leadId: params.getParam(
              'leadId',
              ParamType.String,
            ),
            leadCustomer: params.getParam(
              'leadCustomer',
              ParamType.String,
            ),
            leadPhone: params.getParam(
              'leadPhone',
              ParamType.String,
            ),
            leadEmail: params.getParam(
              'leadEmail',
              ParamType.String,
            ),
            leadFromCity: params.getParam(
              'leadFromCity',
              ParamType.String,
            ),
            leadToCity: params.getParam(
              'leadToCity',
              ParamType.String,
            ),
            leadApproxDate: params.getParam(
              'leadApproxDate',
              ParamType.String,
            ),
            leadService: params.getParam(
              'leadService',
              ParamType.String,
            ),
            leadSource: params.getParam(
              'leadSource',
              ParamType.String,
            ),
            leadStatus: params.getParam(
              'leadStatus',
              ParamType.String,
            ),
            leadBranch: params.getParam(
              'leadBranch',
              ParamType.String,
            ),
            leadNotes: params.getParam(
              'leadNotes',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: QuickEntryPageWidget.routeName,
          path: QuickEntryPageWidget.routePath,
          builder: (context, params) => const QuickEntryPageWidget(),
        ),
        FFRoute(
          name: SignupPageWidget.routeName,
          path: SignupPageWidget.routePath,
          builder: (context, params) => const SignupPageWidget(),
        ),
        FFRoute(
          name: OrgSetupPageWidget.routeName,
          path: OrgSetupPageWidget.routePath,
          builder: (context, params) => const OrgSetupPageWidget(),
        ),
        FFRoute(
          name: PlanPageWidget.routeName,
          path: PlanPageWidget.routePath,
          builder: (context, params) => const PlanPageWidget(),
        ),
        FFRoute(
          name: SupervisorJobPageWidget.routeName,
          path: SupervisorJobPageWidget.routePath,
          builder: (context, params) => SupervisorJobPageWidget(
            orderId: params.getParam('orderId', ParamType.String),
          ),
        ),
        // Public, unauthenticated pages (item 8, CORE V1) — reached via a
        // shared /survey?token=... or /quote?token=... link, no login.
        FFRoute(
          name: SurveyPageWidget.routeName,
          path: SurveyPageWidget.routePath,
          builder: (context, params) => SurveyPageWidget(
            token: params.getParam('token', ParamType.String),
          ),
        ),
        FFRoute(
          name: QuotePageWidget.routeName,
          path: QuotePageWidget.routePath,
          builder: (context, params) => QuotePageWidget(
            token: params.getParam('token', ParamType.String),
          ),
        ),
      ].map((r) => r.toRoute(appStateNotifier)).toList(),
    );

extension NavParamExtensions on Map<String, String?> {
  Map<String, String> get withoutNulls => Map.fromEntries(
        entries
            .where((e) => e.value != null)
            .map((e) => MapEntry(e.key, e.value!)),
      );
}

extension NavigationExtensions on BuildContext {
  void safePop() {
    // If there is only one route on the stack, navigate to the initial
    // page instead of popping.
    if (canPop()) {
      pop();
    } else {
      go('/');
    }
  }
}

extension _GoRouterStateExtensions on GoRouterState {
  Map<String, dynamic> get extraMap =>
      extra != null ? extra as Map<String, dynamic> : {};
  Map<String, dynamic> get allParams => <String, dynamic>{}
    ..addAll(pathParameters)
    ..addAll(uri.queryParameters)
    ..addAll(extraMap);
  TransitionInfo get transitionInfo => extraMap.containsKey(kTransitionInfoKey)
      ? extraMap[kTransitionInfoKey] as TransitionInfo
      : TransitionInfo.appDefault();
}

class FFParameters {
  FFParameters(this.state, [this.asyncParams = const {}]);

  final GoRouterState state;
  final Map<String, Future<dynamic> Function(String)> asyncParams;

  Map<String, dynamic> futureParamValues = {};

  // Parameters are empty if the params map is empty or if the only parameter
  // present is the special extra parameter reserved for the transition info.
  bool get isEmpty =>
      state.allParams.isEmpty ||
      (state.allParams.length == 1 &&
          state.extraMap.containsKey(kTransitionInfoKey));
  bool isAsyncParam(MapEntry<String, dynamic> param) =>
      asyncParams.containsKey(param.key) && param.value is String;
  bool get hasFutures => state.allParams.entries.any(isAsyncParam);
  Future<bool> completeFutures() => Future.wait(
        state.allParams.entries.where(isAsyncParam).map(
          (param) async {
            final doc = await asyncParams[param.key]!(param.value)
                .onError((_, __) => null);
            if (doc != null) {
              futureParamValues[param.key] = doc;
              return true;
            }
            return false;
          },
        ),
      ).onError((_, __) => [false]).then((v) => v.every((e) => e));

  dynamic getParam<T>(
    String paramName,
    ParamType type, {
    bool isList = false,
  }) {
    if (futureParamValues.containsKey(paramName)) {
      return futureParamValues[paramName];
    }
    if (!state.allParams.containsKey(paramName)) {
      return null;
    }
    final param = state.allParams[paramName];
    // Got parameter from `extras`, so just directly return it.
    if (param is! String) {
      return param;
    }
    // Return serialized value.
    return deserializeParam<T>(
      param,
      type,
      isList,
    );
  }
}

class FFRoute {
  const FFRoute({
    required this.name,
    required this.path,
    required this.builder,
    this.requireAuth = false,
    this.asyncParams = const {},
    this.routes = const [],
  });

  final String name;
  final String path;
  final bool requireAuth;
  final Map<String, Future<dynamic> Function(String)> asyncParams;
  final Widget Function(BuildContext, FFParameters) builder;
  final List<GoRoute> routes;

  GoRoute toRoute(AppStateNotifier appStateNotifier) => GoRoute(
        name: name,
        path: path,
        pageBuilder: (context, state) {
          fixStatusBarOniOS16AndBelow(context);
          final ffParams = FFParameters(state, asyncParams);
          final page = ffParams.hasFutures
              ? FutureBuilder(
                  future: ffParams.completeFutures(),
                  builder: (context, _) => builder(context, ffParams),
                )
              : builder(context, ffParams);
          final child = page;

          final transitionInfo = state.transitionInfo;
          return transitionInfo.hasTransition
              ? CustomTransitionPage(
                  key: state.pageKey,
                  name: state.name,
                  child: child,
                  transitionDuration: transitionInfo.duration,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) =>
                          PageTransition(
                    type: transitionInfo.transitionType,
                    duration: transitionInfo.duration,
                    reverseDuration: transitionInfo.duration,
                    alignment: transitionInfo.alignment,
                    child: child,
                  ).buildTransitions(
                    context,
                    animation,
                    secondaryAnimation,
                    child,
                  ),
                )
              : MaterialPage(
                  key: state.pageKey, name: state.name, child: child);
        },
        routes: routes,
      );
}

class TransitionInfo {
  const TransitionInfo({
    required this.hasTransition,
    this.transitionType = PageTransitionType.fade,
    this.duration = const Duration(milliseconds: 300),
    this.alignment,
  });

  final bool hasTransition;
  final PageTransitionType transitionType;
  final Duration duration;
  final Alignment? alignment;

  static TransitionInfo appDefault() =>
      const TransitionInfo(hasTransition: false);
}

class RootPageContext {
  const RootPageContext(this.isRootPage, [this.errorRoute]);
  final bool isRootPage;
  final String? errorRoute;

  static bool isInactiveRootPage(BuildContext context) {
    final rootPageContext = context.read<RootPageContext?>();
    final isRootPage = rootPageContext?.isRootPage ?? false;
    final location = GoRouterState.of(context).uri.toString();
    return isRootPage &&
        location != '/' &&
        location != rootPageContext?.errorRoute;
  }

  static Widget wrap(Widget child, {String? errorRoute}) => Provider.value(
        value: RootPageContext(true, errorRoute),
        child: child,
      );
}

extension GoRouterLocationExtension on GoRouter {
  String getCurrentLocation() {
    final RouteMatch lastMatch = routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : routerDelegate.currentConfiguration;
    return matchList.uri.toString();
  }
}
