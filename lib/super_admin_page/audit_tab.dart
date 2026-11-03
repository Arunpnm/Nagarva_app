import 'package:flutter/material.dart';

import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import 'admin_common.dart';

import '/backend/edge_function_errors.dart';
/// Admin › Audit log: every admin action on vendors, plans, the team,
/// coupons, broadcasts and tickets. Read-only and written only by database
/// triggers; each row's hash covers the one before, and "Check" asks the
/// server whether the chain still holds.
class AuditTab extends StatefulWidget {
  const AuditTab({super.key});
  @override
  State<AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends AdminSectionState<AuditTab> {
  List<Map<String, dynamic>> _rows = const [];
  Map<String, String> _orgs = const {};
  Map<String, String> _plans = const {};
  String? _chain; // null = not checked

  @override
  Future<void> fetch() async {
    final r = await Future.wait([
      db.from('platform_audit').select().order('id', ascending: false).limit(300),
      db.from('organizations').select('id,name'),
      db.from('subscription_plans').select('id,name'),
    ]);
    _rows = List<Map<String, dynamic>>.from(r[0]);
    _orgs = {for (final o in r[1]) '${o['id']}': '${o['name']}'};
    _plans = {for (final p in r[2]) '${p['id']}': '${p['name']}'};
  }

  Future<void> _check() async {
    try {
      final bad = await db.rpc('platform_audit_verify');
      setState(() => _chain = bad == null
          ? 'Chain intact: no entry has been changed or removed.'
          : 'Entry #$bad does not match the chain. It was changed or an entry before it was removed.');
    } catch (e) {
      toast('Could not check: ${friendlyError(e)}');
    }
  }

  static const _titles = {
    'plan_changed': 'Plan changed',
    'suspended': 'Vendor suspended',
    'reactivated': 'Vendor reactivated',
    'trial_extended': 'Trial end changed',
    'plan_status_changed': 'Plan status changed',
    'owner_password_reset_requested': 'Owner password reset sent',
    'admin_added': 'Admin added',
    'admin_changed': 'Admin role or access changed',
    'plan_edited': 'Plans & pricing changed',
    'coupon_created': 'Coupon created',
    'coupon_paused': 'Coupon paused',
    'coupon_resumed': 'Coupon resumed',
    'broadcast_sent': 'Broadcast sent',
    'ticket_changed': 'Ticket updated',
  };

  /// "from → to" lines out of the detail jsonb, with ids turned into names.
  List<String> _lines(Map<String, dynamic> r) {
    final d = Map<String, dynamic>.from(r['detail'] as Map? ?? const {});
    String v(dynamic x) {
      final s = '${x ?? '—'}';
      return _plans[s] ?? (s.length > 18 && DateTime.tryParse(s) != null ? adminDate(s, time: true) : s);
    }

    final out = <String>[];
    if (d.containsKey('from') || d.containsKey('to')) {
      out.add('${v(d['from'])} → ${v(d['to'])}');
    }
    d.forEach((k, x) {
      if (x is Map && (x.containsKey('from') || x.containsKey('to'))) {
        if ('${x['from']}' != '${x['to']}') out.add('$k: ${v(x['from'])} → ${v(x['to'])}');
      } else if (!const {'from', 'to', 'changed_by', 'requested_by'}.contains(k)) {
        out.add('$k: ${x is List ? x.join(', ') : v(x)}');
      }
    });
    return out;
  }

  @override
  Widget build(BuildContext context) => body((c) => [
        const AdminHeading('Audit log', 'Admin actions'),
        NgCard(
          child: Row(children: [
            Icon(Icons.lock_outline_rounded, color: c.green, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  _chain ??
                      'Every admin action on vendors, plans, the team, coupons, broadcasts and tickets. Read-only, stored on the server, chained so changes can be detected. Vendors see actions taken on their own account.',
                  style: NgFonts.geist(fontSize: 12.5, color: c.text, height: 1.4)),
            ),
            TextButton(onPressed: _check, child: const Text('Check')),
          ]),
        ),
        const SizedBox(height: 12),
        if (_rows.isEmpty)
          const NgEmptyState(icon: Icons.history_rounded, title: 'Nothing logged yet')
        else
          NgCardList(children: [
            for (final r in _rows)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: '${r['actor_name'] ?? 'System'}',
                            style: NgFonts.geist(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text)),
                        if (r['actor_role'] != null)
                          TextSpan(
                              text: ' · ${kAdminRoles['${r['actor_role']}'] ?? r['actor_role']}',
                              style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                        if (r['org_id'] != null)
                          TextSpan(
                              text: ' · ${_orgs['${r['org_id']}'] ?? 'deleted vendor'}',
                              style: NgFonts.geist(fontSize: 12.5, color: c.acc)),
                      ])),
                    ),
                    Text(adminDate(r['at'], time: true),
                        style: NgFonts.mono(fontSize: 11.5, color: c.mute)),
                  ]),
                  const SizedBox(height: 3),
                  Text(_titles['${r['action']}'] ?? '${r['action']}'.replaceAll('_', ' '),
                      style: NgFonts.geist(fontSize: 14, color: c.text)),
                  for (final l in _lines(r))
                    Text(l, style: NgFonts.geist(fontSize: 12.5, color: c.soft, height: 1.4)),
                ]),
              ),
          ]),
      ]);
}
