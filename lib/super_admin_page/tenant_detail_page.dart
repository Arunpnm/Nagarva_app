import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Step 2 (super-admin console): tenant detail view. Pushed from the
/// tenant list in super_admin_page_widget.dart — same platform-admin gate
/// as the parent page (this page is never reached without already having
/// passed that check).
class TenantDetailPage extends StatefulWidget {
  const TenantDetailPage({
    super.key,
    required this.org,
    required this.plans,
  });

  final OrganizationsRow org;
  final List<SubscriptionPlansRow> plans;

  @override
  State<TenantDetailPage> createState() => _TenantDetailPageState();
}

class _TenantDetailPageState extends State<TenantDetailPage> {
  late OrganizationsRow _org;
  bool _loading = true;
  bool _togglingActive = false;
  String? _ownerEmail;
  bool _ownerEmailUnavailable = false;
  int _orders = 0;
  int _leads = 0;
  int _staff = 0;
  int _invoices = 0;

  @override
  void initState() {
    super.initState();
    _org = widget.org;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final id = _org.id;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        OrdersTable().queryRows(queryFn: (q) => q.eq('org_id', id), limit: 2000),
        LeadsTable().queryRows(queryFn: (q) => q.eq('org_id', id), limit: 2000),
        StaffTable().queryRows(queryFn: (q) => q.eq('org_id', id), limit: 2000),
      ]);
      final orders = (results[0] as List).cast<OrdersRow>();
      _orders = orders.length;
      _leads = (results[1] as List).length;
      _staff = (results[2] as List).length;
      _invoices = orders.where((o) => (o.invoiceNo ?? '').isNotEmpty).length;
    } catch (_) {
      // Usage counts are best-effort — don't block the rest of the page.
    }
    // Owner email needs supabase/20260727_super_admin_owner_email.sql,
    // which has NOT been run yet as of this pass — call it defensively and
    // just show "—" if the RPC doesn't exist rather than erroring the page.
    try {
      final res = await SupaFlow.client
          .rpc('get_org_owner_email', params: {'p_org_id': id});
      _ownerEmail = res as String?;
    } catch (_) {
      _ownerEmailUnavailable = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleActive() async {
    final goingActive = !_org.active;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(goingActive ? 'Reactivate tenant?' : 'Suspend tenant?'),
        content: Text(goingActive
            ? '${_org.name} will regain access immediately.'
            : '${_org.name} will be locked out immediately — every session '
                '(vendor and staff) hits the same lock screen used for an '
                'expired trial.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: goingActive
                ? null
                : FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(goingActive ? 'Reactivate' : 'Suspend'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _togglingActive = true);
    try {
      await OrganizationsTable().update(
        data: {'active': goingActive},
        matchingRows: (q) => q.eq('id', _org.id!),
      );
      setState(() => _org.active = goingActive);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(goingActive
                ? '${_org.name} reactivated.'
                : '${_org.name} suspended.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _togglingActive = false);
    }
  }

  Widget _row(FlutterFlowTheme theme, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style:
                      GoogleFonts.inter(color: theme.secondaryText, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: GoogleFonts.inter(
                      color: theme.primaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final planName = widget.plans
        .firstWhere((p) => p.id == _org.planId,
            orElse: () => widget.plans.isNotEmpty
                ? widget.plans.first
                : SubscriptionPlansRow(const {}))
        .name;

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text(_org.name),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_org.active)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.block, color: theme.error, size: 18),
                        const SizedBox(width: 8),
                        Text('This tenant is suspended',
                            style: GoogleFonts.inter(
                                color: theme.error,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(theme, 'Slug', _org.slug),
                      _row(theme, 'GSTIN', _org.gstin ?? '—'),
                      _row(
                          theme,
                          'Created',
                          _org.createdAt != null
                              ? '${_org.createdAt!.toLocal()}'.split('.').first
                              : '—'),
                      _row(theme, 'Plan', planName ?? '—'),
                      _row(theme, 'Plan status', _org.planStatus ?? '—'),
                      _row(
                          theme,
                          'Trial ends',
                          _org.trialEndsAt != null
                              ? '${_org.trialEndsAt!.toLocal()}'
                                  .split('.')
                                  .first
                              : '—'),
                      _row(
                          theme,
                          'Owner email',
                          _ownerEmailUnavailable
                              ? '— (needs 20260727_super_admin_owner_email.sql)'
                              : (_ownerEmail ?? '—')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Usage',
                          style: GoogleFonts.interTight(
                              color: theme.primaryText,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _row(theme, 'Orders', '$_orders'),
                      _row(theme, 'Leads', '$_leads'),
                      _row(theme, 'Staff', '$_staff'),
                      _row(theme, 'Invoices', '$_invoices'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _togglingActive ? null : _toggleActive,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _org.active ? Colors.red : theme.success,
                      side: BorderSide(
                          color: _org.active ? Colors.red : theme.success),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: Icon(_org.active ? Icons.block : Icons.check_circle),
                    label: Text(_org.active ? 'Suspend Tenant' : 'Reactivate Tenant'),
                  ),
                ),
              ],
            ),
    );
  }
}
