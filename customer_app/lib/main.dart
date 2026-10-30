import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'booking.dart';
import 'config.dart';
import 'screens/common.dart';
import 'screens/flow.dart';
import 'theme.dart';

/// Nagarva customer app: book a move directly with Nagarva (design handoff,
/// Nagarva Customer.dc.html). Nagarva prices the move from its own rates
/// and broadcasts it to vendors through the marketplace.
///
/// As of 30 Oct 2026 this is the quote flow only: move type to a priced
/// review. Login, booking, tracking, claims and the account tabs come once
/// online payment is chosen (kBookingLive).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  runApp(const CustomerApp());
}

class CustomerApp extends StatefulWidget {
  const CustomerApp({super.key});
  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  final _booking = Booking();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Nagarva',
        debugShowCheckedModeBanner: false,
        theme: customerTheme(),
        home: BookingScope(booking: _booking, child: const TypeScreen()),
      );
}
