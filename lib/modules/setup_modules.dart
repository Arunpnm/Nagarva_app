import 'package:flutter/material.dart';

import '/components/record_module_page.dart';
import '/flutter_flow/ng_tokens.dart';

/// Activity log (handoff Setup › Activity log): `audit_log`, newest first.
/// Rows are written by the database's audit trigger; this screen only
/// reads them.
class ActivityLogPage extends StatelessWidget {
  const ActivityLogPage({super.key});

  static String routeName = 'ActivityLogPage';
  static String routePath = '/activity-log';

  static bool _within(RmMap r, Duration d) {
    final t = rmParseDate(r['created_at']);
    return t != null && DateTime.now().difference(t) <= d;
  }

  static String _human(String? s) => (s ?? '')
      .replaceAll('_', ' ')
      .trim()
      .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Activity log',
      subtitle: 'Who did what, and when',
      views: [
        RmView(
          label: 'All',
          table: 'audit_log',
          orderBy: 'created_at',
          note: 'Recorded by the database when a record changes. '
              'Read-only here. PINs and passwords are never recorded.',
          stats: (rows) => [
            RmStat('Entries', '${rows.length}'),
            RmStat('Today',
                '${rows.where((r) => _within(r, const Duration(days: 1))).length}'),
            RmStat('7 days',
                '${rows.where((r) => _within(r, const Duration(days: 7))).length}'),
          ],
          filters: [
            const RmFilter('All time', _all),
            RmFilter('Today', (r) => _within(r, const Duration(days: 1))),
            RmFilter('7 days', (r) => _within(r, const Duration(days: 7))),
            RmFilter('30 days', (r) => _within(r, const Duration(days: 30))),
          ],
          search: (r) => [
            r['entity_type'],
            r['entity_id'],
            r['action'],
            r['actor_name'],
            r['actor_role'],
            r['reason'],
          ].whereType<Object>().join(' '),
          row: (context, r) {
            final action = '${r['action'] ?? ''}'.toLowerCase();
            final (icon, tone) = switch (action) {
              'insert' || 'create' || 'created' =>
                (Icons.add_circle_outline_rounded, NgStatus.blue),
              'delete' || 'deleted' || 'soft_delete' =>
                (Icons.delete_outline_rounded, NgStatus.red),
              'restore' => (Icons.restore_rounded, NgStatus.green),
              _ => (Icons.edit_outlined, NgStatus.amber),
            };
            final changed = r['changed_fields'];
            final who = [r['actor_name'], r['actor_role']]
                .whereType<Object>()
                .where((x) => '$x'.isNotEmpty)
                .join(' · ');
            return RmRow(
              icon: icon,
              tone: tone,
              title: '${_human(r['action'])} · ${_human(r['entity_type'])}',
              subtitle: [
                if ('${r['entity_id'] ?? ''}'.isNotEmpty) '${r['entity_id']}',
                if (changed is List && changed.isNotEmpty)
                  changed.take(4).join(', '),
                who.isEmpty ? 'System' : who,
                rmDate(r['created_at'], 'd MMM, h:mm a'),
              ].join(' · '),
            );
          },
          emptyText: 'No activity recorded yet.',
        ),
      ],
    );
  }

  static bool _all(RmMap _) => true;
}

/// Services & sources (handoff Account › Services & sources): the
/// vendor's own lead sources and the commission each one takes. The
/// commission is the vendor's figure or blank — never a suggestion.
class LeadSourcesPage extends StatelessWidget {
  const LeadSourcesPage({super.key});

  static String routeName = 'LeadSourcesPage';
  static String routePath = '/services-sources';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Services & sources',
      subtitle: 'Where your jobs come from',
      add: RmAdd(
        title: 'Add a lead source',
        table: 'lead_sources',
        fields: const [
          RmField('name', 'Name', required: true),
          RmField('channel', 'Channel', kind: RmKind.choice, options: [
            'directory',
            'aggregator',
            'social',
            'referral',
            'website',
            'offline',
          ], optionLabels: [
            'Directory',
            'Aggregator',
            'Social',
            'Referral',
            'Website',
            'Offline',
          ]),
          RmField('is_paid', 'Takes a commission or fee',
              kind: RmKind.toggle),
          RmField('commission_pct', 'Commission % (leave blank if none)',
              kind: RmKind.number),
        ],
        prepare: (v) async {
          final pct = v['commission_pct'];
          if (pct is num && (pct < 0 || pct > 100)) {
            throw 'Commission must be between 0 and 100.';
          }
          final name = '${v['name']}';
          return {
            ...v,
            'code': name
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
                .replaceAll(RegExp(r'^_|_$'), ''),
            'active': true,
          };
        },
      ),
      views: [
        RmView(
          label: 'Sources',
          table: 'lead_sources',
          orderBy: 'sort_order',
          ascending: true,
          stats: (rows) => [
            RmStat('Sources', '${rows.length}'),
            RmStat('Paid', '${rows.where((r) => r['is_paid'] == true).length}'),
            RmStat('Active', '${rows.where((r) => r['active'] != false).length}'),
          ],
          row: (context, r) {
            final pct = r['commission_pct'];
            return RmRow(
              icon: Icons.tune_rounded,
              tone: r['active'] == false ? NgStatus.neutral : NgStatus.accent,
              title: '${r['name'] ?? ''}',
              subtitle: [
                if (r['channel'] != null) '${r['channel']}',
                '${r['code'] ?? ''}',
                if (r['active'] == false) 'inactive',
              ].join(' · '),
              amount: pct == null ? null : '${rmNum(pct).toStringAsFixed(rmNum(pct) % 1 == 0 ? 0 : 1)}%',
              status: r['is_paid'] == true
                  ? (pct == null ? 'Rate not set' : 'Paid')
                  : 'Free',
              statusTone: r['is_paid'] == true
                  ? (pct == null ? NgStatus.amber : NgStatus.blue)
                  : NgStatus.neutral,
            );
          },
          emptyText:
              'No lead sources yet. Add the directories and partners that '
              'send you jobs, so each order records where it came from.',
        ),
      ],
    );
  }
}
