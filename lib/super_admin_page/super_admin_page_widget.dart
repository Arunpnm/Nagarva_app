import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'plans_tab.dart';
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
    if (!mounted) return;
    setState(() {
      _isAdmin = rows.isNotEmpty;
      _checking = false;
    });
    if (_isAdmin) await _loadOrgs();
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not change plan: $e')));
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
    final theme = FlutterFlowTheme.of(context);

    if (_checking) {
      return Scaffold(
        backgroundColor: theme.primaryBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          title: const Text('Platform Admin'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 40, color: theme.secondaryText),
                const SizedBox(height: 12),
                Text(
                  'This account is not a platform administrator.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: theme.secondaryText),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final planNameById = {for (final p in _plans) p.id!: p.name};

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          title: Text('Platform Admin — ${_orgs.length} tenants'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tenants'),
              Tab(text: 'Plans'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _loadingOrgs
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
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.secondaryBackground,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        org.name,
                                        style: GoogleFonts.interTight(
                                            color: theme.primaryText,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    if (!org.active)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: theme.error.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text('suspended',
                                            style: GoogleFonts.inter(
                                                color: theme.error,
                                                fontSize: 11)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${org.slug} · plan: ${planNameById[org.planId] ?? '—'} '
                                  '(${org.planStatus ?? '—'})',
                                  style: GoogleFonts.inter(
                                      color: theme.secondaryText,
                                      fontSize: 12.5),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${usage['orders'] ?? 0} orders · ${usage['leads'] ?? 0} leads · ${usage['staff'] ?? 0} staff',
                                  style: GoogleFonts.inter(
                                      color: theme.primaryText, fontSize: 12.5),
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
                  ),
            const PlansTab(),
          ],
        ),
      ),
    );
  }
}
