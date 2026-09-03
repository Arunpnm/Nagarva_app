// The bottom bar's width arithmetic, pinned in a test rather than
// eyeballed on one device.
//
// Built 3 Sept 2026 with the pinned Quick/Menu actions. The risk being
// covered is specific: those two buttons are the ONLY way to reach Quick
// Entry and the module menu from anywhere but the Dashboard, so if the
// row overflows and they scroll off the right edge, the feature is gone
// on exactly the narrow phones it was added for. A screenshot on one
// viewport cannot show that; these can.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arun_p_k_r_s/components/mobile_bottom_nav.dart';
import 'package:arun_p_k_r_s/nav_items.dart';

const _items = <NavItem>[
  (name: 'HomePage', icon: Icons.dashboard, label: 'Dashboard', group: 'Sales'),
  (name: 'LeadsPage', icon: Icons.people, label: 'Leads / CRM', group: 'Sales'),
  (
    name: 'OrdersPage',
    icon: Icons.local_shipping,
    label: 'Orders',
    group: 'Operations'
  ),
  (
    name: 'OperationsPage',
    icon: Icons.route,
    label: 'Operations',
    group: 'Operations'
  ),
  (
    name: 'PaymentsPage',
    icon: Icons.payments,
    label: 'Payments',
    group: 'Money'
  ),
];

Future<void> _pumpBar(
  WidgetTester tester, {
  required double width,
  required List<NavItem> items,
  required bool withActions,
  List<String> tapped = const [],
}) async {
  // No FlutterFlowTheme.initialize() here - it awaits SharedPreferences
  // and hangs the test binding forever (found the hard way: a ten-minute
  // timeout on a suite that otherwise runs in eight seconds). The getter
  // falls back to the light theme with no initialisation, which is all
  // this layout test needs.
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      bottomNavigationBar: MobileBottomNav(
        items: items,
        currentIndex: 0,
        onTap: (_) {},
        actions: withActions
            ? [
                (
                  icon: Icons.add_circle_outline,
                  label: 'Quick',
                  onTap: () {}
                ),
                (icon: Icons.menu, label: 'Menu', onTap: () {}),
              ]
            : const [],
      ),
    ),
  ));
}

void main() {
  group('MobileBottomNav pinned actions', () {
    testWidgets('Quick and Menu are on screen at 390dp', (tester) async {
      await _pumpBar(tester,
          width: 390, items: _items, withActions: true);

      final screen = tester.view.physicalSize.width;
      for (final label in ['Quick', 'Menu']) {
        final box = tester.getRect(find.text(label));
        expect(box.right, lessThanOrEqualTo(screen),
            reason: '$label runs past the right edge');
        expect(box.left, greaterThanOrEqualTo(0));
      }
    });

    testWidgets('Quick and Menu are still on screen at 360dp',
        (tester) async {
      // A very common budget-Android width in this app's market. If the
      // pinned actions survive here they survive on the phones vendors
      // actually hold.
      await _pumpBar(tester,
          width: 360, items: _items, withActions: true);

      final screen = tester.view.physicalSize.width;
      for (final label in ['Quick', 'Menu']) {
        expect(tester.getRect(find.text(label)).right,
            lessThanOrEqualTo(screen),
            reason: '$label runs past the right edge at 360dp');
      }
    });

    testWidgets('every destination still renders alongside them',
        (tester) async {
      await _pumpBar(tester,
          width: 360, items: _items, withActions: true);
      // No destination was dropped to make room - the actions are pinned
      // beside the row, not carved out of it.
      for (final item in _items) {
        expect(find.text(item.label), findsOneWidget,
            reason: '${item.label} vanished from the bar');
      }
    });

    testWidgets('a four-item supervisor bar renders with no actions',
        (tester) async {
      // The regression this release also fixes: a supervisor session
      // matched none of kPrimaryNavNames and got an EMPTY bar, with no
      // drawer either, so it had no navigation at all.
      final supervisor = _items.take(4).toList();
      await _pumpBar(tester,
          width: 360, items: supervisor, withActions: false);
      for (final item in supervisor) {
        expect(find.text(item.label), findsOneWidget);
      }
      expect(find.text('Menu'), findsNothing);
    });
  });
}
