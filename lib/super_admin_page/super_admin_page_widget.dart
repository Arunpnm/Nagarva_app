import '/components/ng_widgets.dart';
import '/app_session.dart';
import '/backend/edge_function_errors.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/ng_tokens.dart';
import 'package:flutter/material.dart';
import 'admin_login_page.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'admin_common.dart';
import 'admin_dashboard_tab.dart';
import 'audit_tab.dart';
import 'broadcasts_tab.dart';
import 'coupons_tab.dart';
import 'marketplace_tab.dart';
import 'payments_tab.dart';
import 'team_tab.dart';
import 'tickets_tab.dart';
import 'plans_tab.dart';
import 'signups_tab.dart';
import 'tenant_detail_page.dart';

/// Platform (SaaS-operator) admin view — all-tenant list, plan management,
/// per-org usage stats. Item 12 in NAGARVA_STATUS.md, built out into a real
/// console in the "super-admin console" pass.
///
/// Gated on the `platform_admins` table (RLS, `is_platform_admin()`) that
/// already exists live per `supabase/migrations/20260715_rls_v1.sql`.
/// Access denial is intentional, not a bug: the owner needs a row in that
/// table for whichever account should be able to reach this page.
///
/// Not in kOwnerManagerNavItems (nav_items.dart) — every owner/manager
/// session would see it there, defeating the point of gating it at all.
/// Since 16 Aug 2026, `navItemsForCurrentSession()` appends a "Platform
/// Admin" nav entry conditionally, only when `AppSession.isPlatformAdmin`
/// is already true — that was the fix for Android having no address bar
/// and therefore no way to reach `/super-admin` by typing it. Direct URL
/// still works too (unaffected, still how web access works day to day).
///
/// This file (and the other files in lib/super_admin_page/) is the ONE
/// documented exception to the OrgScope convention — every query here is
/// deliberately unscoped by org_id, authorized by RLS's
/// is_platform_admin() bypass rather than the client. Keep that exception
/// contained to this directory; nowhere else in the app should read
/// cross-tenant.
class SuperAdminPageWidget extends StatefulWidget {
  const SuperAdminPageWidget({super.key});

  static String routeName = 'SuperAdminPage';
  static String routePath = '/super-admin';

  @override
  State<SuperAdminPageWidget> createState() => _SuperAdminPageWidgetState();
}

class _SuperAdminPageWidgetState extends State<SuperAdminPageWidget> {
  bool _checking = true;
  bool _isAdmin = false;
  bool _loadingOrgs = false;
  List<OrganizationsRow> _orgs = [];
  List<SubscriptionPlansRow> _plans = [];
  // orgId -> {orders, leads, staff}
  final Map<String, Map<String, int>> _usage = {};

  /// The signed-in admin's role (platform_role()). Before
  /// 20261031_admin_panel.sql has run there are no roles and every admin
  /// is treated as super, as they were.
  String _role = 'super';
  String? _myName;
  String _section = 'dashboard';

  /// Each section and the admin roles it is offered to (null = every
  /// role; super sees all). The database enforces the same split; this
  /// only avoids offering what would be refused.
  static const _sections = <({String key, String label, IconData icon, Set<String>? roles})>[
    (key: 'dashboard', label: 'Dashboard', icon: Icons.space_dashboard_outlined, roles: null),
    (key: 'marketplace', label: 'Marketplace', icon: Icons.hub_outlined, roles: {'sales'}),
    (key: 'vendors', label: 'Vendors', icon: Icons.storefront_outlined, roles: {'sales', 'support'}),
    (key: 'signups', label: 'Approvals', icon: Icons.how_to_reg_outlined, roles: {'sales'}),
    (key: 'plans', label: 'Plans & pricing', icon: Icons.sell_outlined, roles: {'sales'}),
    (key: 'payments', label: 'Payments', icon: Icons.payments_outlined, roles: {'sales'}),
    (key: 'tickets', label: 'Support tickets', icon: Icons.support_agent_rounded, roles: {'support'}),
    (key: 'coupons', label: 'Coupons', icon: Icons.confirmation_number_outlined, roles: {'marketing', 'sales'}),
    (key: 'broadcasts', label: 'Broadcasts', icon: Icons.campaign_outlined, roles: {'marketing'}),
    (key: 'team', label: 'Admin team', icon: Icons.admin_panel_settings_outlined, roles: null),
    (key: 'audit', label: 'Audit log', icon: Icons.history_rounded, roles: null),
  ];

  @override
  void initState() {
    super.initState();
    _checkAdminAndLoad();
  }

  Future<void> _checkAdminAndLoad() async {
    final userId = AppSession.instance.authUserId;
    if (userId == null) {
      setState(() {
        _checking = false;
        _isAdmin = false;
      });
      return;
    }
    List<PlatformAdminsRow> rows = [];
    try {
      rows = await PlatformAdminsTable().queryRows(
        queryFn: (q) => q.eq('user_id', userId).limit(1),
      );
    } catch (_) {
      // Table missing / RLS denies entirely — treat as not-admin, not a crash.
    }
    if (rows.isNotEmpty) {
      try {
        final me = await SupaFlow.client
            .from('platform_admins')
            .select('name,email,role,active')
            .eq('user_id', userId)
            .single();
        _role = '${me['role'] ?? 'super'}';
        _myName = '${me['name'] ?? me['email'] ?? ''}';
        if (me['active'] == false) rows = [];
      } catch (_) {
        // No role column yet: the admin panel migration has not run.
        _role = 'super';
      }
    }
    if (!mounted) return;
    setState(() {
      _isAdmin = rows.isNotEmpty;
      _checking = false;
    });
    if (_isAdmin) await _loadOrgs();
  }

  /// Ends the admin session and returns to the admin sign-in.
  Future<void> _signOut() async {
    try {
      await SupaFlow.client.auth.signOut();
    } catch (_) {}
    AppSession.instance.clear();
    if (mounted) context.go(AdminLoginPage.routePath);
  }

  Future<void> _loadOrgs() async {
    setState(() => _loadingOrgs = true);
    try {
      // Deliberately unscoped by org_id — the one legitimate place in the
      // app that needs to see every tenant. RLS's is_platform_admin()
      // bypass is what actually authorizes this, not the client.
      final orgs = await OrganizationsTable().queryRows(queryFn: (q) => q);
      final plans = await SubscriptionPlansTable().queryRows(queryFn: (q) => q);
      _orgs = orgs;
      _plans = plans;
      for (final org in orgs) {
        final id = org.id;
        if (id == null) continue;
        final orders = await OrdersTable()
            .queryRows(queryFn: (q) => q.eq('org_id', id), limit: 1000);
        final leads = await LeadsTable()
            .queryRows(queryFn: (q) => q.eq('org_id', id), limit: 1000);
        final staff = await StaffTable()
            .queryRows(queryFn: (q) => q.eq('org_id', id), limit: 1000);
        _usage[id] = {
          'orders': orders.length,
          'leads': leads.length,
          'staff': staff.length,
        };
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load tenants: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingOrgs = false);
    }
  }

  Future<void> _changePlan(OrganizationsRow org) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Change plan — ${org.name}'),
        children: _plans
            .map((p) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(p.id),
                  child: Text('${p.name ?? p.id}'
                      '${p.id == org.planId ? '  (current)' : ''}'),
                ))
            .toList(),
      ),
    );
    if (chosen == null || chosen == org.planId) return;
    try {
      // RLS remediation Tier B: organizations.plan_id is no longer
      // app-writable at all (column GRANT revoked) — routed through
      // admin-update-org, which re-checks platform_admins membership
      // under the service role and logs a billing_events row. See
      // supabase/functions/admin-update-org/index.ts.
      final res = await SupaFlow.client.functions.invoke(
        'admin-update-org',
        body: {'org_id': org.id, 'plan_id': chosen},
      );
      final body = res.data;
      if (body is! Map || body['ok'] != true) {
        throw Exception(
          (body is Map ? body['error'] as String? : null) ??
              'Could not change plan.',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${org.name}\'s plan updated.')));
      }
      await _loadOrgs();
    } catch (e) {
      // `invoke` throws on any admin-update-org non-2xx response (17 Aug
      // 2026 finding) — was showing a raw exception string.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(extractFunctionErrorMessage(e,
                fallback: 'Could not change plan.'))));
      }
    }
  }

  Future<void> _openTenant(OrganizationsRow org) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TenantDetailPage(org: org, plans: _plans),
    ));
    // The detail page can flip active/plan — refresh the list on return
    // rather than trying to sync two copies of the same row in memory.
    _loadOrgs();
  }

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);

    if (_checking) {
      return Scaffold(
        backgroundColor: ng.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: ng.bg,
        appBar: NgSimpleBar(title: 'Platform Admin'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 40, color: ng.mute),
                const SizedBox(height: 12),
                Text(
                  'This account is not a platform administrator.',
                  textAlign: TextAlign.center,
                  style: NgFonts.geist(color: ng.mute),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final planNameById = {for (final p in _plans) p.id!: p.name};
    final sections = [
      for (final x in _sections)
        if (x.roles == null || _role == 'super' || x.roles!.contains(_role)) x
    ];
    final current = sections.firstWhere((x) => x.key == _section,
        orElse: () => sections.first);
    Widget view(String key) => switch (key) {
          'dashboard' => AdminDashboardTab(onOpen: (k) => setState(() => _section = k)),
          'vendors' => _tenantsView(ng, planNameById),
          'signups' => SignupsTab(onChanged: _loadOrgs),
          'plans' => const PlansTab(),
          'marketplace' => const MarketplaceTab(),
          'payments' => const PaymentsTab(),
          'tickets' => const TicketsTab(),
          'coupons' => const CouponsTab(),
          'broadcasts' => const BroadcastsTab(),
          'team' => TeamTab(myRole: _role),
          _ => const AuditTab(),
        };
    final signOut = IconButton(
      tooltip: 'Sign out',
      icon: Icon(Icons.logout_rounded, color: ng.soft),
      onPressed: _signOut,
    );
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final content = KeyedSubtree(key: ValueKey(current.key), child: view(current.key));
      if (!wide) {
        return Scaffold(
          backgroundColor: ng.bg,
          appBar: NgSimpleBar(title: 'Nagarva Admin', actions: [signOut]),
          body: Column(children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final x in sections)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: NgChip(
                          label: x.label,
                          selected: x.key == current.key,
                          onTap: () => setState(() => _section = x.key)),
                    ),
                ],
              ),
            ),
            Expanded(child: content),
          ]),
        );
      }
      return Scaffold(
        backgroundColor: ng.bg,
        body: Row(children: [
          Container(
            width: 232,
            decoration: BoxDecoration(
                color: ng.s1, border: Border(right: BorderSide(color: ng.w08))),
            child: SafeArea(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Text('Nagarva Admin',
                      style: NgFonts.geist(
                          fontSize: 16, fontWeight: FontWeight.w600, color: ng.text)),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      for (final x in sections)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Material(
                            color: x.key == current.key ? ng.sel : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: ListTile(
                              dense: true,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              leading: Icon(x.icon, size: 19, color: ng.soft),
                              title: Text(x.label,
                                  style: NgFonts.geist(fontSize: 14, color: ng.text)),
                              onTap: () => setState(() => _section = x.key),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_myName ?? 'Admin',
                            overflow: TextOverflow.ellipsis,
                            style: NgFonts.geist(
                                fontSize: 13.5, fontWeight: FontWeight.w600, color: ng.text)),
                        Text(kAdminRoles[_role] ?? 'Admin',
                            style: NgFonts.geist(fontSize: 12, color: ng.mute)),
                      ]),
                    ),
                    signOut,
                  ]),
                ),
              ]),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180), child: content),
            ),
          ),
        ]),
      );
    });
  }

  Widget _tenantsView(NgPalette ng, Map<String, String?> planNameById) {
    return _loadingOrgs
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadOrgs,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orgs.length,
                      itemBuilder: (context, i) {
                        final org = _orgs[i];
                        final usage = _usage[org.id] ?? const {};
                        return InkWell(
                          onTap: () => _openTenant(org),
                          borderRadius: BorderRadius.circular(12),
                          child: NgCard(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        org.name,
                                        style: NgFonts.geist(
                                            color: ng.text,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (!org.active)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: ng.red.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text('suspended',
                                            style: NgFonts.geist(
                                                color: ng.red,
                                                fontSize: 11)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${org.slug} · plan: ${planNameById[org.planId] ?? '—'} '
                                  '(${org.planStatus ?? '—'})',
                                  style: NgFonts.geist(
                                      color: ng.mute,
                                      fontSize: 12.5),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${usage['orders'] ?? 0} orders · ${usage['leads'] ?? 0} leads · ${usage['staff'] ?? 0} staff',
                                  style: NgFonts.geist(
                                      color: ng.text, fontSize: 12.5),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => _changePlan(org),
                                    child: const Text('Change plan'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
  }
}
