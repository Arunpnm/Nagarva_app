// Nagarva CI sanity tests.
// These verify the test toolchain works without booting the full app
// (full app boot requires SharedPreferences/Supabase init, which needs
// a proper integration test setup — coming later).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nagarva sanity checks', () {
    test('trial period math is 14 days', () {
      final now = DateTime(2026, 7, 15);
      final trialEnds = now.add(const Duration(days: 14));
      expect(trialEnds, DateTime(2026, 7, 29));
    });

    testWidgets('basic widget tree renders', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Nagarva')),
          ),
        ),
      );
      expect(find.text('Nagarva'), findsOneWidget);
    });
  });
}
