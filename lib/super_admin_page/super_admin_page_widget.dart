import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Platform (SaaS-operator) admin view — all-tenant list, plan override,
/// per-org usage stats. Item 12 in NAGARVA_STATUS.md.
///
/// Gated on the `platform_admins` table (RLS, `is_platform_admin()`) that
/// already exists live per `supabase/migrations/20260715_rls_v1.sql` —
/// that migration's own "KNOWN GAPS" note flags `platform_admins` seeding
/// as not done, so by default NO account passes this gate yet. Access
/// denial is intentional, not a bug: the owner needs to insert one row
/// (`insert into platform_admins (user_id) values ('<auth-uid>')`) for
/// whichever account should be able to reach this page.
///
/// Not linked from the bottom nav / drawer on purpose — reachable only by
/// direct URL (`/super-admin`) for whoever actually is a platform admin, so
/// regular vendor/staff sessions never see it as an option.
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load tenants: $e')));
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
      await OrganizationsTable().update(
        data: {'plan_id': chosen},
        matchingRows: (q) => q.eq('id', org.id!),
      );
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

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text('Platform Admin — ${_orgs.length} tenants'),
      ),
      body: _loadingOrgs
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadOrgs,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _orgs.length,
                itemBuilder: (context, i) {
                  final org = _orgs[i];
                  final usage = _usage[org.id] ?? const {};
                  return Container(
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
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('inactive',
                                    style: GoogleFonts.inter(
                                        color: theme.error, fontSize: 11)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${org.slug} · plan: ${planNameById[org.planId] ?? '—'} '
                          '(${org.planStatus ?? '—'})',
                          style: GoogleFonts.inter(
                              color: theme.secondaryText, fontSize: 12.5),
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
                  );
                },
              ),
            ),
    );
  }
}
