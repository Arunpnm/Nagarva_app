// Sign in, details and My moves, with the network stood in for. The
// numbers are test data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagarva_customer/booking.dart';
import 'package:nagarva_customer/screens/account.dart';
import 'package:nagarva_customer/screens/common.dart';
import 'package:nagarva_customer/theme.dart';

Future<void> _show(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: customerTheme(), home: w));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sign in sends the code, then verifies', (t) async {
    final calls = <String>[];
    Account.sendOtp = (p) async => calls.add('send $p');
    Account.verifyOtp = (p, c) async => calls.add('verify $p $c');
    await _show(t, const SignInScreen());
    await t.tap(find.text('Send code'));
    await t.pump();
    expect(find.text('Enter your 10-digit mobile number.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('phone')), '9876543210');
    await t.tap(find.text('Send code'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('code')), '123456');
    await t.tap(find.text('Sign in').last);
    await t.pumpAndSettle();
    expect(calls, ['send 9876543210', 'verify 9876543210 123456']);
  });

  testWidgets('checkout sends the move and opens the payment page', (t) async {
    Map<String, dynamic>? sent;
    String? opened;
    Account.book = (b) async {
      sent = b;
      return {'booking_id': 'x', 'pay_url': 'https://rzp.io/test'};
    };
    Account.openUrl = (u) async {
      opened = u;
      return true;
    };
    Account.myMoves = () async => [];
    final b = Booking()
      ..fromCity = 'Chennai'
      ..date = DateTime(2030, 1, 5)
      ..slot = '8–10 am'
      ..lines.add(Line('fridge', 1));
    await _show(t, BookingScope(booking: b, child: CheckoutScreen(booking: b, advance: 1500)));
    expect(find.text('Pay ₹1,500'), findsOneWidget);
    await t.tap(find.text('Pay ₹1,500'));
    await t.pump();
    expect(find.text('Please enter your name.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('name')), 'Ravi');
    await t.enterText(find.byKey(const Key('from')), '12 Gandhi Street, Adyar 600020');
    await t.enterText(find.byKey(const Key('to')), '4 Lake View Road, Anna Nagar 600040');
    await t.tap(find.text('Pay ₹1,500'));
    await t.pumpAndSettle();
    expect(sent!['move_date'], '2030-01-05');
    expect(sent!['input']['from_city'], 'Chennai');
    expect(sent!.containsKey('total'), isFalse);
    expect(opened, 'https://rzp.io/test');
    expect(find.text('My moves'), findsOneWidget);
  });

  testWidgets('my moves shows each state', (t) async {
    Account.myMoves = () async => [
          {
            'status': 'awaiting_payment', 'pay_url': 'https://rzp.io/a',
            'from_city': 'Chennai', 'to_city': 'Bengaluru', 'move_date': '2030-01-05',
            'slot': '8–10 am', 'total': 18000, 'advance': 3000,
            'pickup_address': 'A', 'drop_address': 'B',
          },
          {
            'status': 'paid', 'job_no': 'NG-301105-1234', 'job_status': 'accepted',
            'from_city': 'Chennai', 'to_city': 'Chennai', 'move_date': '2030-01-06',
            'total': 6000, 'advance': 1000, 'pickup_address': 'C', 'drop_address': 'D',
            'vendor_name': 'Test Movers', 'vendor_phone': '9000000000', 'delivery_code': '4821',
          },
        ];
    await _show(t, const MyMovesScreen());
    expect(find.text('Waiting for payment'), findsOneWidget);
    expect(find.text('Pay ₹3,000'), findsOneWidget);
    expect(find.text('Mover assigned'), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);
    expect(find.text('Call mover'), findsOneWidget);
  });
}
