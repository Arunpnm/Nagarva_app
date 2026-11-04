import 'package:flutter/material.dart';

import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/record_module_page.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/backend/detail_navigation.dart';

/// Daily summary (handoff Operations): today in one list — moves on
/// today's date, money received, money spent and new leads.
class DailySummaryPage extends StatelessWidget {
  const DailySummaryPage({super.key});

  static String routeName = 'DailySummaryPage';
  static String routePath = '/daily-summary';

  static Future<List<RmMap>> _load() async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final start = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final out = <RmMap>[];
    final results = await Future.wait([
      OrgScope.read(SupaFlow.client
              .from('orders')
              .select('id, customer, from_city, to_city, status, amount, quote_total'))
          .eq('move_date', today),
      OrgScope.read(SupaFlow.client
              .from('payment_entries')
              .select('id, order_id, amount, mode, receipt_no'))
          .eq('received_at', today)
          .isFilter('deleted_at', null),
      OrgScope.read(SupaFlow.client
              .from('expenses')
              .select('id, order_id, amount, category, description, date, expense_date'))
          // Quick Expense writes the chosen day to `date`; expense_date
          // only holds its default. Either may say today; filtered below.
          .or('date.eq.$today,expense_date.eq.$today')
          .isFilter('deleted_at', null),
      OrgScope.read(SupaFlow.client
              .from('leads')
              .select('id, customer, from_city, to_city, source'))
          .gte('created_at', start),
    ]);
    for (final r in results[0] as List) {
      out.add({...Map<String, dynamic>.from(r as Map), '_k': 'move'});
    }
    for (final r in results[1] as List) {
      out.add({...Map<String, dynamic>.from(r as Map), '_k': 'in'});
    }
    for (final r in results[2] as List) {
      final day = '${r['date'] ?? r['expense_date'] ?? ''}';
      if (!day.startsWith(today)) continue;
      out.add({...Map<String, dynamic>.from(r as Map), '_k': 'out'});
    }
    for (final r in results[3] as List) {
      out.add({...Map<String, dynamic>.from(r as Map), '_k': 'lead'});
    }
    // Money spent today outside the expenses table — the same places the
    // P&L counts (lib/backend/money_book.dart). "Spent" used to miss trip
    // expenses, fuel and servicing entirely (BUG-049). Each read is
    // separate so one failing table never blanks the day.
    Future<List<dynamic>> extra(String table, String cols, String dateCol,
        [bool notFromExpense = false]) async {
      try {
        var q = OrgScope.read(SupaFlow.client.from(table).select(cols))
            .eq(dateCol, today);
        if (notFromExpense) q = q.isFilter('expense_id', null);
        return await q;
      } catch (_) {
        return const [];
      }
    }

    final extras = await Future.wait([
      extra('trip_expenses', 'id, amount, expense_type, note', 'expense_date'),
      extra('fuel_fills', 'id, amount, order_id, litres', 'fill_date', true),
      extra('vehicle_service_logs', 'id, total_cost, service_type',
          'service_date'),
    ]);
    for (final r in extras[0]) {
      out.add({
        'id': r['id'],
        'amount': r['amount'],
        'category': 'Trip · ${r['expense_type'] ?? 'expense'}',
        'description': r['note'] ?? '',
        '_k': 'out',
      });
    }
    for (final r in extras[1]) {
      out.add({
        'id': r['id'],
        'amount': r['amount'],
        'category': 'Fuel',
        'description': r['litres'] == null ? '' : '${r['litres']} L',
        'order_id': r['order_id'],
        '_k': 'out',
      });
    }
    for (final r in extras[2]) {
      out.add({
        'id': r['id'],
        'amount': r['total_cost'],
        'category': 'Vehicle service',
        'description': r['service_type'] ?? '',
        '_k': 'out',
      });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // A Porter advance is money Porter holds, not cash the vendor
    // received today, so it is listed but not counted as Collected
    // (BUG-049).
    double sum(List<RmMap> rows, String k) => rows
        .where((r) => r['_k'] == k && '${r['mode'] ?? ''}' != 'porter')
        .fold<double>(0, (s, r) => s + rmNum(r['amount']));
    return RecordModulePage(
      title: 'Daily summary',
      subtitle: DateFormat('EEEE, d MMM').format(DateTime.now()),
      views: [
        RmView(
          label: 'Today',
          load: _load,
          stats: (rows) => [
            RmStat('Moves', '${rows.where((r) => r['_k'] == 'move').length}'),
            RmStat('Collected', rmMoney(sum(rows, 'in'))),
            RmStat('Spent', rmMoney(sum(rows, 'out'))),
          ],
          filters: [
            RmFilter('All', (r) => true),
            RmFilter('Moves', (r) => r['_k'] == 'move'),
            RmFilter('Money', (r) => r['_k'] == 'in' || r['_k'] == 'out'),
            RmFilter('New leads', (r) => r['_k'] == 'lead'),
          ],
          row: (context, r) {
            void open() {
              final oid = r['_k'] == 'move' ? r['id'] : r['order_id'];
              if (oid == null) return;
              openOrderJourneyById(context, '$oid');
            }

            return switch (r['_k']) {
              'move' => RmRow(
                  icon: Icons.local_shipping_outlined,
                  tone: NgStatus.blue,
                  title: '${r['customer'] ?? ''} · ${r['id']}',
                  subtitle: '${r['from_city'] ?? ''} → ${r['to_city'] ?? ''}',
                  status: '${r['status'] ?? ''}',
                  onTap: open,
                ),
              'in' => RmRow(
                  icon: Icons.south_west_rounded,
                  tone: NgStatus.green,
                  title: '${r['mode'] == 'porter' ? 'Porter advance (not cash)' : 'Received'} · ${r['order_id'] ?? ''}',
                  subtitle: [
                    '${r['mode'] ?? ''}'.toUpperCase(),
                    if (r['receipt_no'] != null) '${r['receipt_no']}',
                  ].join(' · '),
                  amount: '+ ${rmMoney(r['amount'])}',
                  amountColor: NgPalette.of(context).green,
                  onTap: open,
                ),
              'out' => RmRow(
                  icon: Icons.north_east_rounded,
                  tone: NgStatus.red,
                  title: '${r['category'] ?? 'Expense'}',
                  subtitle: [
                    '${r['description'] ?? ''}',
                    if (r['order_id'] != null) '${r['order_id']}',
                  ].where((x) => x.isNotEmpty).join(' · '),
                  amount: '− ${rmMoney(r['amount'])}',
                  amountColor: NgPalette.of(context).red,
                  onTap: open,
                ),
              _ => RmRow(
                  icon: Icons.person_add_alt_outlined,
                  tone: NgStatus.accent,
                  title: 'New lead · ${r['customer'] ?? ''}',
                  subtitle: [
                    '${r['from_city'] ?? ''} → ${r['to_city'] ?? ''}',
                    if (r['source'] != null) '${r['source']}',
                  ].join(' · '),
                ),
            };
          },
          emptyText: 'Nothing recorded today yet.',
        ),
      ],
    );
  }
}

/// Payslips, PF & ESI (handoff People): payroll runs and the payslips in
/// them. Read-only — generating a payroll run is not built yet; staff are
/// paid from Salary today.
class PayslipsPage extends StatelessWidget {
  const PayslipsPage({super.key});

  static String routeName = 'PayslipsPage';
  static String routePath = '/payslips';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Payslips, PF & ESI',
      subtitle: 'Monthly payroll and statutory deductions',
      views: [
        RmView(
          label: 'Payroll runs',
          table: 'payroll_runs',
          orderBy: 'run_at',
          note: 'Generating a payroll run with PF and ESI is not built yet. '
              'Day-to-day wages are paid from Salary.',
          stats: (rows) => [
            RmStat('Runs', '${rows.length}'),
            RmStat('Net paid', rmMoney(rows.fold<double>(
                0, (s, r) => s + rmNum(r['total_net'])))),
            RmStat('PF + ESI', rmMoney(rows.fold<double>(
                0,
                (s, r) =>
                    s + rmNum(r['total_pf_employer']) + rmNum(r['total_esi_employer'])))),
          ],
          row: (context, r) => RmRow(
            icon: Icons.request_quote_outlined,
            tone: NgStatus.blue,
            title:
                '${DateFormat('MMMM').format(DateTime(2000, rmNum(r['period_month']).round().clamp(1, 12)))} ${r['period_year'] ?? ''}',
            subtitle: [
              '${r['staff_count'] ?? 0} staff',
              if (r['branch'] != null) '${r['branch']}',
            ].join(' · '),
            amount: rmMoney(r['total_net']),
            status: '${r['status'] ?? ''}',
          ),
          emptyText: 'No payroll runs yet.',
        ),
        RmView(
          label: 'Payslips',
          table: 'payslips',
          orderBy: 'created_at',
          row: (context, r) => RmRow(
            icon: Icons.badge_outlined,
            tone: NgStatus.neutral,
            title: '${r['payslip_no'] ?? 'Payslip'}',
            subtitle:
                'Present ${rmNum(r['days_present']).toStringAsFixed(1)} of ${r['days_in_month'] ?? '—'} days · PF ${rmMoney(r['pf_employee'])} · ESI ${rmMoney(r['esi_employee'])}',
            amount: rmMoney(r['net_pay']),
            status: r['paid'] == true ? 'Paid' : 'Unpaid',
            statusTone: r['paid'] == true ? NgStatus.green : NgStatus.amber,
          ),
          emptyText: 'No payslips yet.',
        ),
      ],
    );
  }
}
