import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/record_module_page.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/index.dart';

String _human(dynamic s) => '${s ?? ''}'
    .replaceAll('_', ' ')
    .trim()
    .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());

void _openOrder(BuildContext context, dynamic id) {
  if (id == null || '$id'.isEmpty) return;
  context.pushNamed(
    OrderDetailPageWidget.routeName,
    queryParameters: {'orderId': serializeParam('$id', ParamType.String)}
        .withoutNulls,
  );
}

/// GST, TDS & exports (handoff Money): what the invoices already say,
/// laid out the way GSTR-1 wants it. Read-only — filing and the JSON
/// export are not built.
class GstPage extends StatelessWidget {
  const GstPage({super.key});

  static String routeName = 'GstPage';
  static String routePath = '/gst';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'GST, TDS & exports',
      subtitle: 'Your invoices, laid out for filing',
      views: [
        RmView(
          label: 'B2B',
          table: 'gstr1_b2b_view',
          orderBy: 'invoice_date',
          note: 'Built from the GST invoices you issued. Filing and the '
              'GSTR-1 JSON export are not built yet.',
          stats: (rows) {
            double sum(String k) =>
                rows.fold<double>(0, (s, r) => s + rmNum(r[k]));
            return [
              RmStat('Invoices', '${rows.length}'),
              RmStat('Taxable', rmMoney(sum('taxable_value'))),
              RmStat('Tax',
                  rmMoney(sum('igst') + sum('cgst') + sum('sgst'))),
            ];
          },
          search: (r) => [r['invoice_no'], r['customer_name'], r['customer_gstin']]
              .whereType<Object>()
              .join(' '),
          row: (context, r) => RmRow(
            icon: Icons.request_page_outlined,
            tone: NgStatus.blue,
            title: '${r['invoice_no'] ?? ''} · ${r['customer_name'] ?? ''}',
            subtitle: [
              '${r['customer_gstin'] ?? ''}',
              rmDate(r['invoice_date']),
              if (r['rate'] != null) '${rmNum(r['rate']).toStringAsFixed(0)}%',
            ].where((x) => x.isNotEmpty).join(' · '),
            amount: rmMoney(r['invoice_value']),
          ),
          emptyText: 'No B2B invoices yet. An invoice appears here once the '
              'customer has a GSTIN on the order.',
        ),
        RmView(
          label: 'B2C',
          table: 'gstr1_b2c_view',
          orderBy: 'period',
          row: (context, r) => RmRow(
            icon: Icons.receipt_outlined,
            tone: NgStatus.neutral,
            title:
                '${rmDate(r['period'], 'MMM yyyy')} · ${rmNum(r['rate']).toStringAsFixed(0)}%',
            subtitle:
                '${rmNum(r['invoice_count']).toStringAsFixed(0)} invoices · tax ${rmMoney(rmNum(r['igst']) + rmNum(r['cgst']) + rmNum(r['sgst']))}',
            amount: rmMoney(r['taxable_value']),
          ),
          emptyText: 'No B2C invoices yet.',
        ),
        RmView(
          label: 'TDS',
          table: 'tds_entries',
          orderBy: 'deducted_on',
          stats: (rows) => [
            RmStat('Entries', '${rows.length}'),
            RmStat(
                'Deducted',
                rmMoney(rows.fold<double>(
                    0, (s, r) => s + rmNum(r['tds_amount'])))),
            RmStat('Not deposited',
                '${rows.where((r) => r['deposited'] != true).length}'),
          ],
          row: (context, r) => RmRow(
            icon: Icons.account_balance_outlined,
            tone: NgStatus.amber,
            title: 'Section ${r['section'] ?? '—'} · ${r['fy'] ?? ''} ${r['quarter'] ?? ''}',
            subtitle: [
              rmDate(r['deducted_on']),
              if (r['challan_no'] != null) 'Challan ${r['challan_no']}',
            ].where((x) => x.isNotEmpty).join(' · '),
            amount: rmMoney(r['tds_amount']),
            status: r['deposited'] == true ? 'Deposited' : 'Pending',
            statusTone:
                r['deposited'] == true ? NgStatus.green : NgStatus.amber,
          ),
          emptyText: 'No TDS deducted on vendor bills yet.',
        ),
      ],
    );
  }
}

/// Credit notes & refunds (handoff Money). The number comes from the
/// org's own `credit_note` series via `next_doc_number`, never a local
/// counter.
class CreditNotesPage extends StatelessWidget {
  const CreditNotesPage({super.key});

  static String routeName = 'CreditNotesPage';
  static String routePath = '/credit-notes';

  static bool _refund(RmMap r) => r['note_type'] == 'refund';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Credit notes & refunds',
      subtitle: 'Reduce an invoice or refund a customer',
      add: RmAdd(
        title: 'New credit note',
        table: 'credit_notes',
        fields: const [
          RmField('note_type', 'Type', kind: RmKind.choice, required: true,
              options: ['credit', 'refund'],
              optionLabels: ['Reduce the invoice', 'Refund the customer']),
          RmField('order_id', 'Order ID', mono: true),
          RmField('original_invoice_no', 'Invoice no.', mono: true),
          RmField('reason', 'Reason', required: true),
          RmField('total_amount', 'Amount ₹', kind: RmKind.number, required: true),
          RmField('note_date', 'Date', kind: RmKind.date),
        ],
        prepare: (v) async {
          if (rmNum(v['total_amount']) <= 0) throw 'Enter an amount above zero.';
          final no = await SupaFlow.client.rpc('next_doc_number', params: {
            'p_org': AppSession.instance.currentOrgId,
            'p_doc_type': 'credit_note',
            'p_branch': null,
            'p_fy': rmCurrentFy(),
          });
          return {...v, 'note_no': no};
        },
      ),
      views: [
        RmView(
          label: 'Notes',
          table: 'credit_notes',
          orderBy: 'note_date',
          stats: (rows) => [
            RmStat('Issued', '${rows.length}'),
            RmStat(
                'Refunded',
                rmMoney(rows.where(_refund).fold<double>(
                    0, (s, r) => s + rmNum(r['total_amount'])))),
            RmStat(
                'Adjusted',
                rmMoney(rows.where((r) => !_refund(r)).fold<double>(
                    0, (s, r) => s + rmNum(r['total_amount'])))),
          ],
          search: (r) => [r['note_no'], r['order_id'], r['reason']]
              .whereType<Object>()
              .join(' '),
          row: (context, r) => RmRow(
            icon: Icons.assignment_return_outlined,
            tone: NgStatus.amber,
            title: '${r['note_no'] ?? 'Unnumbered'} · ${r['reason'] ?? ''}',
            subtitle: [
              if (r['order_id'] != null) '${r['order_id']}',
              if (r['original_invoice_no'] != null)
                'on ${r['original_invoice_no']}',
              rmDate(r['note_date']),
            ].join(' · '),
            amount: '− ${rmMoney(r['total_amount'])}',
            status: _refund(r) ? 'Refunded' : 'Adjusted',
            statusTone: _refund(r) ? NgStatus.red : NgStatus.amber,
            onTap: () => _openOrder(context, r['order_id']),
          ),
          emptyText: 'No credit notes issued.',
        ),
      ],
    );
  }
}

/// Bank & UPI match (handoff Money): imported statements and how many
/// lines matched a payment. Import itself is not built yet.
class BankMatchPage extends StatelessWidget {
  const BankMatchPage({super.key});

  static String routeName = 'BankMatchPage';
  static String routePath = '/bank-match';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Bank & UPI match',
      subtitle: 'Match statement lines to payments',
      views: [
        RmView(
          label: 'Lines',
          table: 'bank_statement_lines',
          orderBy: 'txn_date',
          note: 'Importing a bank statement is not built yet. Once '
              'statements are imported, their lines show here with '
              'whether each matched a payment.',
          stats: (rows) => [
            RmStat('Lines', '${rows.length}'),
            RmStat('Matched',
                '${rows.where((r) => r['match_status'] == 'matched').length}'),
            RmStat('Unmatched',
                '${rows.where((r) => r['match_status'] != 'matched').length}'),
          ],
          filters: [
            const RmFilter('All', _all),
            RmFilter('Unmatched', (r) => r['match_status'] != 'matched'),
            RmFilter('Matched', (r) => r['match_status'] == 'matched'),
          ],
          search: (r) => [r['description'], r['reference']]
              .whereType<Object>()
              .join(' '),
          row: (context, r) {
            final credit = rmNum(r['credit']);
            return RmRow(
              icon: credit > 0
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              tone: credit > 0 ? NgStatus.green : NgStatus.red,
              title: '${r['description'] ?? ''}',
              subtitle: [rmDate(r['txn_date']), '${r['reference'] ?? ''}']
                  .where((x) => x.isNotEmpty)
                  .join(' · '),
              amount: credit > 0
                  ? '+ ${rmMoney(credit)}'
                  : '− ${rmMoney(r['debit'])}',
              status: _human(r['match_status'] ?? 'unmatched'),
              statusTone: r['match_status'] == 'matched'
                  ? NgStatus.green
                  : NgStatus.amber,
            );
          },
          emptyText: 'No statement lines yet.',
        ),
        RmView(
          label: 'Statements',
          table: 'bank_statements',
          orderBy: 'statement_to',
          row: (context, r) => RmRow(
            icon: Icons.account_balance_outlined,
            tone: NgStatus.blue,
            title: '${r['file_name'] ?? 'Statement'}',
            subtitle:
                '${rmDate(r['statement_from'])} – ${rmDate(r['statement_to'])} · ${r['matched_count'] ?? 0}/${r['line_count'] ?? 0} matched',
            amount: rmMoney(r['closing_balance']),
          ),
          emptyText: 'No statements imported.',
        ),
      ],
    );
  }

  static bool _all(RmMap _) => true;
}

/// Cash book (handoff Money): cash in from payments recorded as cash,
/// cash out from expenses paid in cash.
///
/// Expenses only learned how they were paid with
/// `supabase/20261021_expenses_payment_mode.sql`. Before that migration
/// runs the expense read fails, and the screen says so instead of
/// counting every expense as cash.
class CashBookPage extends StatelessWidget {
  const CashBookPage({super.key});

  static String routeName = 'CashBookPage';
  static String routePath = '/cash-book';

  static Future<List<RmMap>> _load() async {
    final out = <RmMap>[];
    final pays = await OrgScope.read(SupaFlow.client
            .from('payment_entries')
            .select('id, order_id, amount, received_at, note, receipt_no'))
        .eq('mode', 'cash')
        .isFilter('deleted_at', null)
        .order('received_at', ascending: false)
        .limit(500);
    for (final p in pays as List) {
      out.add({...Map<String, dynamic>.from(p as Map), '_in': true,
        '_date': p['received_at']});
    }
    try {
      final exps = await OrgScope.read(SupaFlow.client
              .from('expenses')
              .select('id, order_id, amount, date, expense_date, category, description'))
          .eq('payment_mode', 'cash')
          .isFilter('deleted_at', null)
          .order('expense_date', ascending: false)
          .limit(500);
      for (final e in exps as List) {
        out.add({...Map<String, dynamic>.from(e as Map), '_in': false,
          // Quick Expense writes the chosen day to `date`; expense_date
        // only ever holds its default, so `date` wins when set.
        '_date': e['date'] ?? e['expense_date']});
      }
    } catch (_) {
      out.add({'_missing': true});
    }
    out.sort((a, b) => '${b['_date'] ?? ''}'.compareTo('${a['_date'] ?? ''}'));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    double sum(List<RmMap> rows, bool inflow) => rows
        .where((r) => r['_in'] == inflow && rmThisMonth(r['_date']))
        .fold<double>(0, (s, r) => s + rmNum(r['amount']));
    return RecordModulePage(
      title: 'Cash book',
      subtitle: 'Cash in and out',
      views: [
        RmView(
          label: 'This month',
          load: _load,
          stats: (rows) {
            final i = sum(rows, true), o = sum(rows, false);
            return [
              RmStat('Cash in', rmMoney(i)),
              RmStat('Cash out', rmMoney(o)),
              RmStat('Net', rmMoney(i - o)),
            ];
          },
          filters: [
            RmFilter('All', (r) => r['_missing'] != true),
            RmFilter('In', (r) => r['_in'] == true),
            RmFilter('Out', (r) => r['_in'] == false),
          ],
          row: (context, r) {
            if (r['_missing'] == true) {
              return const RmRow(
                icon: Icons.info_outline_rounded,
                title: 'Cash spent is not shown yet',
                subtitle: 'Expenses do not record how they were paid until '
                    'the payment-mode migration runs.',
              );
            }
            final inflow = r['_in'] == true;
            return RmRow(
              icon: inflow
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              tone: inflow ? NgStatus.green : NgStatus.red,
              title: inflow
                  ? 'Received${r['order_id'] != null ? ' · ${r['order_id']}' : ''}'
                  : '${r['category'] ?? 'Expense'}${'${r['description'] ?? ''}'.isNotEmpty ? ' · ${r['description']}' : ''}',
              subtitle: [
                rmDate(r['_date']),
                if (inflow && r['receipt_no'] != null) '${r['receipt_no']}',
              ].join(' · '),
              amount: '${inflow ? '+' : '−'} ${rmMoney(r['amount'])}',
              amountColor: inflow
                  ? NgPalette.of(context).green
                  : NgPalette.of(context).red,
              onTap: () => _openOrder(context, r['order_id']),
            );
          },
          emptyText: 'No cash recorded yet.',
        ),
      ],
    );
  }
}

/// Approvals (handoff Money): what is waiting on the owner — discount
/// approvals on quotes, and jobs the crew finished that still need
/// closing. Deciding happens where each item lives; this is the queue.
class ApprovalsPage extends StatelessWidget {
  const ApprovalsPage({super.key});

  static String routeName = 'ApprovalsPage';
  static String routePath = '/approvals';

  static Future<List<RmMap>> _load() async {
    final out = <RmMap>[];
    final qa = await OrgScope.read(
            SupaFlow.client.from('quote_approvals').select())
        .order('requested_at', ascending: false)
        .limit(200);
    for (final q in qa as List) {
      out.add({...Map<String, dynamic>.from(q as Map), '_kind': 'discount'});
    }
    final jobs = await OrgScope.read(SupaFlow.client
            .from('orders')
            .select('id, customer, from_city, to_city, job_end_time, status'))
        .eq('supervisor_status', 'completed_pending')
        .not('status', 'in', '(closed,cancelled)')
        .limit(200);
    for (final j in jobs as List) {
      out.add({...Map<String, dynamic>.from(j as Map), '_kind': 'job'});
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    bool pending(RmMap r) =>
        r['_kind'] == 'job' || (r['status'] ?? 'pending') == 'pending';
    return RecordModulePage(
      title: 'Approvals',
      subtitle: 'Waiting on you',
      views: [
        RmView(
          label: 'Queue',
          load: _load,
          stats: (rows) => [
            RmStat('Waiting', '${rows.where(pending).length}'),
            RmStat('Discounts',
                '${rows.where((r) => r['_kind'] == 'discount' && pending(r)).length}'),
            RmStat('Jobs to close',
                '${rows.where((r) => r['_kind'] == 'job').length}'),
          ],
          filters: [
            RmFilter('Waiting', pending),
            RmFilter('Discounts', (r) => r['_kind'] == 'discount'),
            RmFilter('Jobs', (r) => r['_kind'] == 'job'),
          ],
          row: (context, r) {
            if (r['_kind'] == 'job') {
              return RmRow(
                icon: Icons.task_alt_rounded,
                tone: NgStatus.green,
                title: 'Job done · ${r['id']}',
                subtitle: [
                  '${r['customer'] ?? ''}',
                  '${r['from_city'] ?? ''} → ${r['to_city'] ?? ''}',
                  if (r['job_end_time'] != null)
                    rmDate(r['job_end_time'], 'd MMM, h:mm a'),
                ].join(' · '),
                status: 'Close order',
                statusTone: NgStatus.amber,
                onTap: () => _openOrder(context, r['id']),
              );
            }
            final st = '${r['status'] ?? 'pending'}';
            return RmRow(
              icon: Icons.percent_rounded,
              tone: NgStatus.accent,
              title:
                  'Discount ${rmNum(r['discount_pct']).toStringAsFixed(0)}% · quote ${r['quote_id'] ?? ''}',
              subtitle: [
                if (r['requested_by'] != null) 'by ${r['requested_by']}',
                if ('${r['reason'] ?? ''}'.isNotEmpty) '${r['reason']}',
                rmDate(r['requested_at']),
              ].join(' · '),
              amount: rmMoney(r['proposed_amount']),
              status: _human(st),
              statusTone: switch (st) {
                'approved' => NgStatus.green,
                'rejected' => NgStatus.red,
                _ => NgStatus.amber,
              },
            );
          },
          emptyText: 'Nothing is waiting on you.',
        ),
      ],
    );
  }
}
