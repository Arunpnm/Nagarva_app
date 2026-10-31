import 'package:flutter/material.dart';

import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import 'admin_common.dart';

/// Admin › Dashboard: the state of the vendor base today, counted from
/// organizations, plans and tickets. MRR here is what paying vendors' plans
/// are priced at per month, not money received: until online billing is
/// live there is no payment record to count, and the card says so.
class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({super.key, required this.onOpen});

  /// Opens another section by its key ('tickets', 'vendors', ...).
  final ValueChanged<String> onOpen;
  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends AdminSectionState<AdminDashboardTab> {
  List<Map<String, dynamic>> _orgs = const [];
  Map<String, Map<String, dynamic>> _plans = const {};
  List<Map<String, dynamic>>? _openTickets; // null: tickets not set up
  int _signups = 0;

  @override
  Future<void> fetch() async {
    final r = await Future.wait([
      db.from('organizations').select('id,name,city,plan_id,plan_status,trial_ends_at,active,created_at'),
      db.from('subscription_plans').select('id,code,name,price_inr,billing_period'),
    ]);
    _orgs = List<Map<String, dynamic>>.from(r[0]);
    _plans = {for (final p in r[1]) '${p['id']}': Map<String, dynamic>.from(p)};
    try {
      _openTickets = List<Map<String, dynamic>>.from(
          await db.from('support_tickets').select('id,priority').eq('status', 'open'));
    } catch (_) {
      _openTickets = null;
    }
    try {
      final s = await db.from('vendor_signups').select('id').eq('status', 'pending');
      _signups = (s as List).length;
    } catch (_) {
      _signups = 0;
    }
  }

  num _monthly(Map<String, dynamic>? p) {
    final price = p?['price_inr'] as num? ?? 0;
    return p?['billing_period'] == 'annual' || p?['billing_period'] == 'yearly' ? price / 12 : price;
  }

  @override
  Widget build(BuildContext context) => body((c) {
        final now = DateTime.now();
        final live = _orgs.where((o) => o['active'] != false).toList();
        final paying = live
            .where((o) => o['plan_status'] == 'active' && _monthly(_plans['${o['plan_id']}']) > 0)
            .toList();
        final trial = live.where((o) => o['plan_status'] == 'trial').toList();
        DateTime? ends(Map o) => DateTime.tryParse('${o['trial_ends_at'] ?? ''}')?.toLocal();
        final expiring = live.where((o) {
          final e = ends(o);
          return (o['plan_status'] == 'trial' || o['plan_status'] == 'grace') &&
              e != null &&
              !e.isBefore(now) &&
              e.difference(now).inDays < 7;
        }).toList()
          ..sort((a, b) => ends(a)!.compareTo(ends(b)!));
        final mrr = paying.fold<num>(0, (s, o) => s + _monthly(_plans['${o['plan_id']}']));
        final newThisMonth = _orgs.where((o) {
          final d = DateTime.tryParse('${o['created_at']}')?.toLocal();
          return d != null && d.year == now.year && d.month == now.month;
        }).length;
        final mix = <String, int>{};
        for (final o in paying) {
          final n = '${_plans['${o['plan_id']}']?['name'] ?? 'Other'}';
          mix[n] = (mix[n] ?? 0) + 1;
        }
        Widget tile(IconData icon, String label, String value, String sub,
                {String? open, Color? tone}) =>
            SizedBox(
              width: 180,
              child: NgCard(
                onTap: open == null ? null : () => widget.onOpen(open),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 16, color: tone ?? c.acc),
                    const SizedBox(width: 6),
                    Expanded(child: Text(label, style: NgFonts.geist(fontSize: 12.5, color: c.soft))),
                  ]),
                  const SizedBox(height: 6),
                  Text(value,
                      style: NgFonts.geist(fontSize: 24, fontWeight: FontWeight.w600, color: tone ?? c.text)),
                  Text(sub, style: NgFonts.geist(fontSize: 11.5, color: c.mute)),
                ]),
              ),
            );
        final high = _openTickets?.where((t) => t['priority'] == 'high').length ?? 0;
        return [
          AdminHeading('Dashboard', 'All vendors · today ${DateFormat('d MMM yyyy').format(now)}'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            tile(Icons.storefront_outlined, 'Active vendors', '${paying.length}', 'paying now',
                open: 'vendors'),
            tile(Icons.hourglass_bottom_rounded, 'On trial', '${trial.length}', 'free trial',
                open: 'vendors'),
            tile(Icons.event_busy_outlined, 'Expiring in 7 days', '${expiring.length}', 'trial or grace',
                tone: expiring.isEmpty ? null : c.amber),
            tile(Icons.trending_up_rounded, 'MRR', adminMoney.format(mrr), 'from plan prices, not payments'),
            tile(Icons.person_add_alt_rounded, 'New this month', '$newThisMonth', 'vendors joined'),
            tile(Icons.how_to_reg_outlined, 'Waiting approval', '$_signups', 'new vendor signups',
                open: 'signups', tone: _signups == 0 ? null : c.amber),
            tile(Icons.support_agent_rounded, 'Open tickets',
                _openTickets == null ? '—' : '${_openTickets!.length}',
                _openTickets == null ? 'not set up' : '$high high priority',
                open: 'tickets', tone: high == 0 ? null : c.red),
          ]),
          const SizedBox(height: 16),
          NgSectionHeader('Expiring in the next 7 days', trailing: '${expiring.length} vendors'),
          const SizedBox(height: 8),
          if (expiring.isEmpty)
            Text('No trial or grace period ends this week.',
                style: NgFonts.geist(fontSize: 13, color: c.faint))
          else
            NgCardList(children: [
              for (final o in expiring)
                NgListRow(
                  title: '${o['name']}',
                  subtitle: [
                    if ('${o['city'] ?? ''}'.isNotEmpty) '${o['city']}',
                    '${_plans['${o['plan_id']}']?['name'] ?? '—'}',
                  ].join(' · '),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    NgPill(o['plan_status'] == 'grace' ? 'Grace' : 'Trial',
                        status: o['plan_status'] == 'grace' ? NgStatus.amber : NgStatus.blue),
                    const SizedBox(width: 8),
                    Text(() {
                      final d = ends(o)!.difference(now).inDays;
                      return d == 0 ? 'today' : '$d day${d == 1 ? '' : 's'} left';
                    }(), style: NgFonts.geist(fontSize: 12.5, color: c.amber)),
                  ]),
                ),
            ]),
          const SizedBox(height: 16),
          const NgSectionHeader('Plan mix · paying vendors'),
          const SizedBox(height: 8),
          if (mix.isEmpty)
            Text('No paying vendors yet. Vendors move from trial to a paid plan once online billing is live.',
                style: NgFonts.geist(fontSize: 13, color: c.faint, height: 1.4))
          else
            NgCard(
              child: Column(children: [
                for (final e in mix.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 90, child: Text(e.key, style: NgFonts.geist(fontSize: 13, color: c.text))),
                      Expanded(child: NgProgressBar(value: e.value / paying.length)),
                      const SizedBox(width: 10),
                      Text('${e.value}', style: NgFonts.mono(fontSize: 13, color: c.text)),
                    ]),
                  ),
              ]),
            ),
        ];
      });
}
