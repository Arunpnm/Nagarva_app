import 'package:flutter/material.dart';

import '/components/record_module_page.dart';
import '/flutter_flow/ng_tokens.dart';

String _human(dynamic s) => '${s ?? ''}'
    .replaceAll('_', ' ')
    .trim()
    .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());

/// Lead rules & lost report (handoff Sales): why deals were lost, from
/// `quote_outcomes` (written by `mark_lead_lost`), and how each lead
/// source converts, from `lead_source_performance_view`.
class LostReportPage extends StatelessWidget {
  const LostReportPage({super.key});

  static String routeName = 'LostReportPage';
  static String routePath = '/lost-report';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Lost report',
      subtitle: 'Why deals were lost, and which sources convert',
      views: [
        RmView(
          label: 'Lost deals',
          table: 'quote_outcomes',
          orderBy: 'recorded_at',
          query: (q) => q.eq('outcome', 'lost'),
          stats: (rows) {
            final gaps = rows
                .map((r) => r['price_gap_pct'])
                .whereType<num>()
                .toList();
            final reasons = <String, int>{};
            for (final r in rows) {
              final k = '${r['reason_code'] ?? 'other'}';
              reasons[k] = (reasons[k] ?? 0) + 1;
            }
            final top = reasons.entries.isEmpty
                ? '—'
                : _human((reasons.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value)))
                    .first
                    .key);
            return [
              RmStat('Lost', '${rows.length}'),
              RmStat('Top reason', top, mono: false),
              RmStat(
                  'Avg price gap',
                  gaps.isEmpty
                      ? '—'
                      : '${(gaps.reduce((a, b) => a + b) / gaps.length).toStringAsFixed(1)}%'),
            ];
          },
          search: (r) => [r['reason_code'], r['reason_note'], r['competitor_name']]
              .whereType<Object>()
              .join(' '),
          row: (context, r) => RmRow(
            icon: Icons.trending_down_rounded,
            tone: NgStatus.red,
            title: _human(r['reason_code']),
            subtitle: [
              if ('${r['competitor_name'] ?? ''}'.isNotEmpty)
                'Went to ${r['competitor_name']}',
              if ('${r['reason_note'] ?? ''}'.isNotEmpty) '${r['reason_note']}',
              rmDate(r['recorded_at']),
            ].join(' · '),
            amount: r['competitor_price'] == null
                ? null
                : rmMoney(r['competitor_price']),
            status: r['price_gap_pct'] == null
                ? null
                : '${rmNum(r['price_gap_pct']).toStringAsFixed(0)}% gap',
            statusTone: NgStatus.amber,
          ),
          emptyText: 'No lost deals recorded. Marking a lead lost with a '
              'reason fills this report.',
        ),
        RmView(
          label: 'Sources',
          table: 'lead_source_performance_view',
          orderBy: 'period',
          stats: (rows) {
            final leads = rows.fold<double>(0, (s, r) => s + rmNum(r['total_leads']));
            final won = rows.fold<double>(0, (s, r) => s + rmNum(r['converted_leads']));
            return [
              RmStat('Leads', leads.toStringAsFixed(0)),
              RmStat('Converted', won.toStringAsFixed(0)),
              RmStat('Rate',
                  leads == 0 ? '—' : '${(won / leads * 100).toStringAsFixed(0)}%'),
            ];
          },
          row: (context, r) => RmRow(
            icon: Icons.campaign_outlined,
            tone: NgStatus.blue,
            title: '${r['source_name'] ?? 'Unknown source'}',
            subtitle: [
              rmDate(r['period'], 'MMM yyyy'),
              '${rmNum(r['total_leads']).toStringAsFixed(0)} leads',
              '${rmNum(r['converted_leads']).toStringAsFixed(0)} won',
              '${rmNum(r['lost_leads']).toStringAsFixed(0)} lost',
            ].join(' · '),
            amount: r['conversion_pct'] == null
                ? null
                : '${rmNum(r['conversion_pct']).toStringAsFixed(0)}%',
          ),
          emptyText: 'No leads with a source yet.',
        ),
      ],
    );
  }
}

/// Coupons & referrals (handoff Sales): referral rewards owed and paid,
/// and the vendor's discount rules. A reward amount is whatever the
/// vendor types; it is never pre-filled.
class ReferralsPage extends StatelessWidget {
  const ReferralsPage({super.key});

  static String routeName = 'ReferralsPage';
  static String routePath = '/coupons-referrals';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Coupons & referrals',
      subtitle: 'Who sent you a customer, and what they are owed',
      add: const RmAdd(
        title: 'Record a referral',
        table: 'referrals',
        fields: [
          RmField('referrer_name', 'Referred by', required: true),
          RmField('referrer_phone', 'Their phone', mono: true),
          RmField('order_id', 'Order ID (if booked)', mono: true),
          RmField('reward_type', 'Reward', kind: RmKind.choice, options: [
            'cash',
            'discount',
            'none',
          ], optionLabels: [
            'Cash',
            'Discount',
            'None',
          ]),
          RmField('reward_amount', 'Reward amount ₹', kind: RmKind.number),
          RmField('note', 'Note'),
        ],
      ),
      views: [
        RmView(
          label: 'Referrals',
          table: 'referrals',
          orderBy: 'created_at',
          stats: (rows) {
            final owed = rows
                .where((r) => r['status'] != 'paid')
                .fold<double>(0, (s, r) => s + rmNum(r['reward_amount']));
            final paid = rows
                .where((r) => r['status'] == 'paid')
                .fold<double>(0, (s, r) => s + rmNum(r['reward_amount']));
            return [
              RmStat('Referrals', '${rows.length}'),
              RmStat('Owed', rmMoney(owed)),
              RmStat('Paid', rmMoney(paid)),
            ];
          },
          filters: [
            const RmFilter('All', _all),
            RmFilter('Pending', (r) => r['status'] != 'paid'),
            RmFilter('Paid', (r) => r['status'] == 'paid'),
          ],
          search: (r) => [r['referrer_name'], r['referrer_phone'], r['order_id']]
              .whereType<Object>()
              .join(' '),
          row: (context, r) => RmRow(
            icon: Icons.sell_outlined,
            tone: NgStatus.accent,
            title: '${r['referrer_name'] ?? 'Unknown'}',
            subtitle: [
              if (r['order_id'] != null) '${r['order_id']}',
              _human(r['reward_type']),
              rmDate(r['created_at']),
            ].join(' · '),
            amount: rmMoney(r['reward_amount']),
            status: _human(r['status']),
            statusTone:
                r['status'] == 'paid' ? NgStatus.green : NgStatus.amber,
          ),
          emptyText: 'No referrals recorded yet.',
        ),
        RmView(
          label: 'Discount rules',
          table: 'discount_policies',
          orderBy: 'created_at',
          row: (context, r) => RmRow(
            icon: Icons.percent_rounded,
            tone: NgStatus.blue,
            title: '${r['name'] ?? ''}',
            subtitle: [
              if (r['role'] != null) 'For ${r['role']}',
              if (r['approver_role'] != null) 'approved by ${r['approver_role']}',
              if (r['floor_margin_pct'] != null)
                'floor margin ${rmNum(r['floor_margin_pct']).toStringAsFixed(0)}%',
            ].join(' · '),
            amount: r['max_discount_pct'] == null
                ? null
                : 'max ${rmNum(r['max_discount_pct']).toStringAsFixed(0)}%',
            status: r['active'] == false ? 'Off' : 'On',
            statusTone:
                r['active'] == false ? NgStatus.neutral : NgStatus.green,
          ),
          emptyText: 'No discount rules set.',
        ),
      ],
    );
  }

  static bool _all(RmMap _) => true;
}
