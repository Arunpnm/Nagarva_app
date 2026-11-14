import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/super_admin_page/nagarva_job_form.dart';

void main() {
  testWidgets('job form lays out with cities and items', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(
      home: NagarvaJobForm(
        rules: [
          {'city': '*', 'commission_pct': 12, 'advance_pct': 10, 'advance_min': 999}
        ],
        vendors: [],
        orgNames: {},
        debugCities: [
          {'city': 'Chennai', 'lat': 13.08, 'lng': 80.27},
          {'city': 'Bengaluru', 'lat': 12.97, 'lng': 77.59},
        ],
        debugCatalogue: [
          {'key': 'sofa', 'cat': 'liv', 'name': 'Sofa', 'variants': [
            {'name': '3 seater', 'cft': 25}, {'name': '2 seater', 'cft': 18}
          ], 'services': [{'code': 'dismantle', 'label': 'Dismantle'}]},
          {'key': 'bed', 'cat': 'bed', 'name': 'Bed', 'variants': [
            {'name': 'King', 'cft': 40}
          ], 'services': []},
        ],
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('New Nagarva job'), findsOneWidget);
    await t.ensureVisible(find.text('Living'));
    await t.drag(find.byType(ListView).first, const Offset(0, -150));
    await t.pumpAndSettle();
    await t.tap(find.text('Living'));
    await t.pumpAndSettle();
    final plus = find.descendant(
        of: find.ancestor(of: find.text('Sofa'), matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.add_rounded));
    await t.ensureVisible(plus);
    await t.pumpAndSettle();
    await t.tap(plus, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.textContaining('Sofa'), findsWidgets);
    await t.scrollUntilVisible(find.text('Get price'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Get price'), findsOneWidget);
  });
}
