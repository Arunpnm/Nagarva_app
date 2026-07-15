import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:page_transition/page_transition.dart';
import 'package:provider/provider.dart';

import '/backend/supabase/supabase.dart';

import '/main.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/lat_lng.dart';
import '/flutter_flow/place.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'serialization_util.dart';

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

GoRouter createRouter(AppStateNotifier appStateNotifier) => GoRouter(
      initialLocation: '/',
      debugLogDiagnostics: true,
      refreshListenable: appStateNotifier,
      navigatorKey: appNavigatorKey,
      errorBuilder: (context, state) => LoginPageWidget(),
      routes: [
        FFRoute(
          name: '_initialize',
          path: '/',
          builder: (context, _) => LoginPageWidget(),
        ),
        FFRoute(
          name: LoginPageWidget.routeName,
          path: LoginPageWidget.routePath,
          builder: (context, params) => LoginPageWidget(),
        ),
        FFRoute(
          name: HomePageWidget.routeName,
          path: HomePageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? NavBarPage(initialPage: 'HomePage')
              : HomePageWidget(),
        ),
        FFRoute(
          name: OrdersPageWidget.routeName,
          path: OrdersPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? NavBarPage(initialPage: 'OrdersPage')
              : OrdersPageWidget(),
        ),
        FFRoute(
          name: LeadsPageWidget.routeName,
          path: LeadsPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? NavBarPage(initialPage: 'LeadsPage')
              : LeadsPageWidget(),
        ),
        FFRoute(
          name: OperationsPageWidget.routeName,
          path: OperationsPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? NavBarPage(initialPage: 'OperationsPage')
              : OperationsPageWidget(),
        ),
        FFRoute(
          name: PaymentsPageWidget.routeName,
          path: PaymentsPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? NavBarPage(initialPage: 'PaymentsPage')
              : PaymentsPageWidget(),
        ),
        FFRoute(
          name: ExpensePageWidget.routeName,
          path: ExpensePageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? NavBarPage(initialPage: 'ExpensePage')
              : ExpensePageWidget(),
        ),
        FFRoute(
          name: SalaryPageWidget.routeName,
          path: SalaryPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? NavBarPage(initialPage: 'SalaryPage')
              : SalaryPageWidget(),
        ),
        FFRoute(
          name: FleetPageWidget.routeName,
          path: FleetPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? NavBarPage(initialPage: 'FleetPage')
              : FleetPageWidget(),
        ),
        FFRoute(
          name: QuotationPageWidget.routeName,
          path: QuotationPageWidget.routePath,
          builder: (context, params) => QuotationPageWidget(),
        ),
        FFRoute(
          name: AccountsPageWidget.routeName,
          path: AccountsPageWidget.routePath,
          builder: (context, params) => AccountsPageWidget(),
        ),
        FFRoute(
          name: PLReportPageWidget.routeName,
          path: PLReportPageWidget.routePath,
          builder: (context, params) => PLReportPageWidget(),
        ),
        FFRoute(
          name: SettingsPageWidget.routeName,
          path: SettingsPageWidget.routePath,
          builder: (context, params) => params.isEmpty
              ? NavBarPage(initialPage: 'SettingsPage')
              : SettingsPageWidget(),
        ),
        FFRoute(
          name: CalendarPageWidget.routeName,
          path: CalendarPageWidget.routePath,
          builder: (context, params) => CalendarPageWidget(),
        ),
        FFRoute(
          name: MaterialsPageWidget.routeName,
          path: MaterialsPageWidget.routePath,
          builder: (context, params) => MaterialsPageWidget(),
        ),
        FFRoute(
          name: ReportsPageWidget.routeName,
          path: ReportsPageWidget.routePath,
          builder: (context, params) => ReportsPageWidget(),
        ),
        FFRoute(
          name: UsersPageWidget.routeName,
          path: UsersPageWidget.routePath,
          builder: (context, params) => UsersPageWidget(),
        ),
        FFRoute(
          name: RecordPaymentPageWidget.routeName,
          path: RecordPaymentPageWidget.routePath,
          builder: (context, params) => RecordPaymentPageWidget(),
        ),
        FFRoute(
          name: QuickExpensePageWidget.routeName,
          path: QuickExpensePageWidget.routePath,
          builder: (context, params) => QuickExpensePageWidget(),
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
          builder: (context, params) => QuickEntryPageWidget(),
        ),
        FFRoute(
          name: SignupPageWidget.routeName,
          path: SignupPageWidget.routePath,
          builder: (context, params) => SignupPageWidget(),
        ),
        FFRoute(
          name: OrgSetupPageWidget.routeName,
          path: OrgSetupPageWidget.routePath,
          builder: (context, params) => OrgSetupPageWidget(),
        ),
        FFRoute(
          name: PlanPageWidget.routeName,
          path: PlanPageWidget.routePath,
          builder: (context, params) => PlanPageWidget(),
        ),
        FFRoute(
          name: SupervisorJobPageWidget.routeName,
          path: SupervisorJobPageWidget.routePath,
          builder: (context, params) => SupervisorJobPageWidget(
            orderId: params.getParam('orderId', ParamType.String),
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

  static TransitionInfo appDefault() => TransitionInfo(hasTransition: false);
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
