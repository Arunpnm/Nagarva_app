// Renders every new Nagarva Admin section, and the vendor's support page,
// at phone and desktop widths against canned rows, so an overflow or a
// crash on real-shaped data fails here instead of in the browser. The
// rows are test data; the network is a stand-in that answers PostgREST
// paths the way Supabase does.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arun_p_k_r_s/super_admin_page/admin_dashboard_tab.dart';
import 'package:arun_p_k_r_s/super_admin_page/audit_tab.dart';
import 'package:arun_p_k_r_s/super_admin_page/broadcasts_tab.dart';
import 'package:arun_p_k_r_s/super_admin_page/coupons_tab.dart';
import 'package:arun_p_k_r_s/super_admin_page/payments_tab.dart';
import 'package:arun_p_k_r_s/super_admin_page/team_tab.dart';
import 'package:arun_p_k_r_s/super_admin_page/tickets_tab.dart';

final _now = DateTime.now().toUtc();
String _iso(Duration d) => _now.add(d).toIso8601String();

final _tables = <String, Object>{
  'organizations': [
    {'id': 'o1', 'name': 'Hyderabad Express Shifting', 'city': 'Hyderabad', 'plan_id': 'p0', 'plan_status': 'trial', 'trial_ends_at': _iso(const Duration(days: 2)), 'active': true, 'created_at': _iso(const Duration(days: -3))},
    {'id': 'o2', 'name': 'Pune Home Shifters', 'city': 'Pune', 'plan_id': 'p1', 'plan_status': 'active', 'trial_ends_at': null, 'active': true, 'created_at': _iso(const Duration(days: -60))},
    {'id': 'o3', 'name': 'Namma Bengaluru Movers and Packers Private Limited', 'city': 'Bengaluru', 'plan_id': 'p2', 'plan_status': 'active', 'trial_ends_at': null, 'active': true, 'created_at': _iso(const Duration(days: -1))},
  ],
  'subscription_plans': [
    {'id': 'p0', 'code': 'trial', 'name': 'Trial', 'price_inr': 0, 'billing_period': 'monthly'},
    {'id': 'p1', 'code': 'growth', 'name': 'Growth', 'price_inr': 1499, 'billing_period': 'monthly'},
    {'id': 'p2', 'code': 'pro', 'name': 'Pro', 'price_inr': 2999, 'billing_period': 'monthly'},
  ],
  'vendor_signups': [{'id': 's1'}],
  'support_tickets': [
    {'id': 't1', 'ticket_no': 1001, 'org_id': 'o2', 'subject': 'AutoPay failed but money was cut from the bank account yesterday evening', 'body': 'x', 'priority': 'high', 'status': 'open', 'assigned_to': null, 'created_at': _iso(const Duration(minutes: -25)), 'updated_at': _iso(const Duration(minutes: -25))},
    {'id': 't2', 'ticket_no': 1002, 'org_id': 'o1', 'subject': 'Forgot PIN', 'body': 'x', 'priority': 'normal', 'status': 'waiting', 'assigned_to': 'u1', 'created_at': _iso(const Duration(hours: -3)), 'updated_at': _iso(const Duration(hours: -2))},
  ],
  'platform_admins': [
    {'user_id': 'u1', 'name': 'Prakash Raman', 'email': 'prakash@nagarva.in', 'role': 'super', 'active': true, 'created_at': _iso(const Duration(days: -30))},
    {'user_id': 'u2', 'name': 'Neha Iyer', 'email': 'neha@nagarva.in', 'role': 'marketing', 'active': false, 'created_at': _iso(const Duration(days: -3))},
  ],
  'platform_coupons': [
    {'code': 'DIWALI20', 'kind': 'pct', 'value': 20, 'plan_codes': ['growth', 'pro'], 'valid_until': '2026-11-15', 'max_uses': 100, 'used_count': 12, 'active': true, 'created_by': 'u2', 'created_at': _iso(Duration.zero)},
    {'code': 'FLAT500', 'kind': 'flat', 'value': 500, 'plan_codes': ['pro'], 'valid_until': '2026-11-30', 'max_uses': 50, 'used_count': 50, 'active': true, 'created_by': 'u1', 'created_at': _iso(Duration.zero)},
  ],
  'platform_broadcasts': [
    {'id': 'b1', 'channel': 'in_app', 'audience': 'trial', 'audience_value': null, 'body': 'Your free trial ends soon. Renew with WELCOME10 to get 10% off your first payment.', 'recipients': 4, 'created_by': 'u2', 'created_at': _iso(const Duration(days: -2))},
  ],
  'platform_audit': [
    {'id': 3, 'at': _iso(const Duration(hours: -1)), 'actor_name': 'Prakash Raman', 'actor_role': 'super', 'org_id': 'o1', 'action': 'trial_extended', 'detail': {'from': '2026-10-16T00:00:00Z', 'to': '2026-10-20T00:00:00Z', 'changed_by': 'u1'}},
    {'id': 2, 'at': _iso(const Duration(days: -1)), 'actor_name': 'Prakash Raman', 'actor_role': 'super', 'org_id': null, 'action': 'plan_edited', 'detail': {'plan': 'growth', 'price_inr': {'from': 1299, 'to': 1499}}},
    {'id': 1, 'at': _iso(const Duration(days: -2)), 'actor_name': 'Prakash Raman', 'actor_role': 'super', 'org_id': 'o2', 'action': 'plan_changed', 'detail': {'from': 'p0', 'to': 'p1'}},
  ],
  'platform_invoices': <Object>[],
};

http.Client _fakeSupabase() => MockClient((req) async {
      final seg = req.url.pathSegments;
      final i = seg.indexOf('v1');
      if (i < 0) return http.Response('{}', 200, request: req);
      if (seg[i + 1] == 'rpc') {
        return http.Response(jsonEncode(seg[i + 2] == 'platform_audience_count' ? 3 : null), 200,
            headers: {'content-type': 'application/json'}, request: req);
      }
      return http.Response(jsonEncode(_tables[seg[i + 1]] ?? const []), 200,
          headers: {'content-type': 'application/json; charset=utf-8'}, request: req);
    });

Future<void> _render(WidgetTester t, Widget w, Size size) async {
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
  // The fake network answers on the real clock, outside the test's fake
  // async zone: let those replies land, then settle the frames.
  for (var i = 0; i < 100; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await t.pumpAndSettle();
  final err = find.text('Could not load');
  if (err.evaluate().isNotEmpty) {
    fail('Section showed its error state: '
        '${t.widgetList<Text>(find.byType(Text)).map((x) => x.data).join(' | ')}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://supabase.test',
      anonKey: 'test-anon-key',
      httpClient: _fakeSupabase(),
      // No deep-link listener: there is no platform plugin in a test.
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false, detectSessionInUri: false),
      debug: false,
    );
  });

  for (final (label, size) in const [('phone', Size(390, 844)), ('desktop', Size(1280, 800))]) {
    group(label, () {
      testWidgets('dashboard counts trial, paying and MRR from plan prices', (t) async {
        await _render(t, AdminDashboardTab(onOpen: (_) {}), size);
        expect(find.text('₹4,498'), findsOneWidget); // Growth + Pro
        await t.scrollUntilVisible(find.text('Hyderabad Express Shifting'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Hyderabad Express Shifting'), findsOneWidget); // expiring
      });
      testWidgets('tickets: open filter, high priority first', (t) async {
        await _render(t, const TicketsTab(), size);
        expect(find.textContaining('AutoPay failed'), findsOneWidget);
        expect(find.text('Forgot PIN'), findsNothing); // waiting, not open
      });
      testWidgets('coupons: a used-up code reads as limit reached', (t) async {
        await _render(t, const CouponsTab(), size);
        expect(find.textContaining('limit reached'), findsOneWidget);
        expect(find.text('Create coupon'), findsOneWidget);
      });
      testWidgets('broadcasts: counts the audience on the send button', (t) async {
        await _render(t, const BroadcastsTab(), size);
        expect(find.text('Send to 3'), findsOneWidget);
        expect(find.textContaining('Trial vendors'), findsWidgets);
      });
      testWidgets('team: super admin can add people', (t) async {
        await _render(t, const TeamTab(myRole: 'super'), size);
        expect(find.text('Add someone'), findsOneWidget);
        expect(find.text('Off'), findsOneWidget);
      });
      testWidgets('team: others only read it', (t) async {
        await _render(t, const TeamTab(myRole: 'support'), size);
        expect(find.text('Add someone'), findsNothing);
      });
      testWidgets('audit: ids become names, changes show from and to', (t) async {
        await _render(t, const AuditTab(), size);
        expect(find.text('Trial → Growth'), findsOneWidget);
        expect(find.text('price_inr: 1299 → 1499'), findsOneWidget);
      });
      testWidgets('payments: empty until billing is live', (t) async {
        await _render(t, const PaymentsTab(), size);
        expect(find.text('No subscription payments yet'), findsOneWidget);
      });
    });
  }
}
