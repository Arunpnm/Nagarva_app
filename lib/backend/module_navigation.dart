import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// Opens a module screen so that BACK always lands on the Dashboard.
///
/// Arun, 3 Sept 2026: *"when i click back button in most of the pages it
/// is not redirecting to dashboard in some cases it should move to
/// previous screen"*.
///
/// The cause is that every module route in `nav.dart` builds its own
/// `NavBarPage` — a whole app shell. So `pushNamed` from the menu did not
/// swap the screen, it STACKED another shell on top. Open Customers from
/// the Dashboard, then Vendors from the menu, then Tasks, and the stack
/// is four shells deep: back goes Tasks -> Vendors -> Customers ->
/// Dashboard, one press at a time, through screens the person never
/// thinks of as a trail they walked. Which shell you land on depends
/// entirely on the order menu items were tapped, so the same button does
/// something different every time — that is the unpredictability, not a
/// missing handler.
///
/// The rule here is: **at most one module sits above the Dashboard.**
/// From the Dashboard, push. From anywhere else, REPLACE. Back from any
/// module is then the Dashboard, always, from any depth of wandering.
///
/// Detail screens are deliberately NOT routed through this. An order,
/// a lead, a customer is pushed normally on top of its list, so back
/// there returns to the list — which is the other half of what Arun
/// asked for ("in some cases it should move to previous screen"). The
/// distinction is: a MODULE is a place you go, a DETAIL is a thing you
/// opened, and only the second one has a meaningful "previous".
void openModule(BuildContext context, String routeName) {
  final onDashboard =
      GoRouterState.of(context).uri.path == HomePageWidget.routePath;
  if (onDashboard) {
    context.pushNamed(routeName);
  } else {
    context.pushReplacementNamed(routeName);
  }
}
