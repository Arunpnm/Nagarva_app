// Renders every screen of the booking flow at phone size with the real
// catalogue and a sample quote, so a layout overflow or a crash fails
// here instead of on a customer's phone. The quote numbers are test data.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagarva_customer/booking.dart';
import 'package:nagarva_customer/screens/common.dart';
import 'package:nagarva_customer/screens/flow.dart';
import 'package:nagarva_customer/theme.dart';

import 'catalogue_fixture.dart';

Booking _booking() => Booking()
  ..fromCity = 'Chennai'
  ..date = DateTime.now().add(const Duration(days: 3))
  ..slot = '8–10 am'
  ..lines.addAll([Line('fridge', 1), Line('cot', 1, services: {'dis'})]);

Future<void> _render(WidgetTester t, Widget screen, Booking b) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
      theme: customerTheme(), home: BookingScope(booking: b, child: screen)));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    Api.cities = () async => ['Bengaluru', 'Chennai', 'Coimbatore'];
    Api.catalogue = () async => [
          for (final r in jsonDecode(kCatalogueFixture) as List)
            CatalogueItem(Map<String, dynamic>.from(r))
        ];
    Api.addonPrices = (_) async => {
          'ok': true, 'cft': 90, 'slab': '1 RK / Studio',
          'damage_cover': 1499, 'unpacking': 1800, 'storage_month': null,
        };
    Api.quote = (_) async => {
          'ok': true, 'km': 15, 'local': true, 'cft': 90, 'move': 2999,
          'floors': 500, 'vehicles': 0, 'services': 0, 'addons': 1499,
          'subtotal': 4998, 'gst': 899.64, 'total': 5897.64, 'advance': 999,
        };
  });

  testWidgets('type', (t) async {
    await _render(t, const TypeScreen(), _booking());
    expect(find.text('Full house'), findsOneWidget);
  });
  testWidgets('cities, intercity', (t) async {
    await _render(t, const CitiesScreen(), _booking()..scope = 'inter');
    expect(find.text('Drop city'), findsOneWidget);
  });
  testWidgets('items, with lines and services', (t) async {
    await _render(t, const ItemsScreen(), _booking());
    expect(find.text('Cot / bed'), findsOneWidget);
    expect(find.text('Dismantle & assemble'), findsWidgets);
  });
  testWidgets('date', (t) async {
    await _render(t, const DateScreen(), _booking());
    expect(find.text('Pickup time'), findsOneWidget);
  });
  testWidgets('package', (t) async {
    await _render(t, const PackageScreen(), _booking());
    expect(find.text('Premium'), findsOneWidget);
  });
  testWidgets('add-ons: an unset price is not offered', (t) async {
    await _render(t, const AddonsScreen(), _booking());
    expect(find.text('Not offered yet'), findsOneWidget);
    expect(find.text('Priced for your move size: 1 RK / Studio'), findsOneWidget);
  });
  testWidgets('review shows the server total and the advance', (t) async {
    await _render(t, const ReviewScreen(), _booking());
    expect(find.text('₹5,898'), findsOneWidget);
    expect(find.text('₹999'), findsOneWidget);
    expect(find.text('Continue to pay ₹999'), findsOneWidget);
  });
  testWidgets('review shows a refusal in words', (t) async {
    Api.quote = (_) async =>
        {'ok': false, 'reason': 'no_price', 'detail': 'rates Chennai standard'};
    await _render(t, const ReviewScreen(), _booking());
    expect(find.textContaining('not taking bookings'), findsOneWidget);
  });
}
