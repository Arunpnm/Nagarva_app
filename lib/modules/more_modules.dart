import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/data_export.dart';
import '/backend/edge_function_errors.dart';
import '/backend/fy_numbering.dart';
import '/backend/save_file.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/components/record_module_page.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/index.dart';
import 'staff_document_upload.dart';

String _human(dynamic s) => '${s ?? ''}'
    .replaceAll('_', ' ')
    .trim()
    .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());

Future<List<RmMap>> _rows(dynamic q) async =>
    [for (final r in await q as List) Map<String, dynamic>.from(r as Map)];

/// Business accounts (handoff Sales): customers billed as a business —
/// a GSTIN or a non-individual type — and their contracts.
class BusinessAccountsPage extends StatelessWidget {
  const BusinessAccountsPage({super.key});

  static String routeName = 'BusinessAccountsPage';
  static String routePath = '/business-accounts';

  @override
  Widget build(BuildContext context) {
    return _WithRows(
      // Any customer can hold a contract; business ones are listed first.
      load: () => _rows(OrgScope.read(SupaFlow.client
              .from('customers')
              .select('id, name, company_name, gstin, customer_type'))
          .isFilter('deleted_at', null)
          .order('name', ascending: true)),
      builder: (customers) => _page(context, customers),
    );
  }

  Widget _page(BuildContext context, List<RmMap> customers) {
    bool isBusiness(RmMap c) =>
        '${c['gstin'] ?? ''}'.isNotEmpty ||
        (c['customer_type'] != null && c['customer_type'] != 'individual');
    final sorted = [
      ...customers.where(isBusiness),
      ...customers.where((c) => !isBusiness(c)),
    ];
    return RecordModulePage(
      title: 'Business accounts',
      subtitle: 'Companies you bill on credit',
      // Contracts could be listed but never added (BUG-026, 4 Nov 2026).
      // The number comes from the org's own contract series.
      add: RmAdd(
        title: 'New contract',
        table: 'contracts',
        saveLabel: 'Save contract',
        fields: [
          RmField('customer_id', 'Customer',
              kind: RmKind.choice,
              required: true,
              options: [for (final c in sorted) '${c['id']}'],
              optionLabels: [
                for (final c in sorted) '${c['company_name'] ?? c['name'] ?? ''}'
              ]),
          const RmField('title', 'Contract title', required: true),
          const RmField('contract_type', 'Type',
              kind: RmKind.choice,
              options: ['rate_contract', 'annual', 'project', 'other'],
              optionLabels: ['Rate contract', 'Annual', 'One project', 'Other']),
          const RmField('start_date', 'Starts', kind: RmKind.date, required: true),
          const RmField('end_date', 'Ends', kind: RmKind.date, required: true),
          const RmField('contract_value', 'Contract value ₹', kind: RmKind.number),
          const RmField('billing_cycle', 'Billing',
              kind: RmKind.choice,
              options: ['per_job', 'weekly', 'monthly', 'quarterly'],
              optionLabels: ['Per job', 'Weekly', 'Monthly', 'Quarterly']),
          const RmField('credit_days', 'Credit days', kind: RmKind.number),
          const RmField('notes', 'Notes'),
        ],
        prepare: (v) async {
          final f = DateTime.parse('${v['start_date']}');
          final t = DateTime.parse('${v['end_date']}');
          if (t.isBefore(f)) throw '"Ends" is before "Starts".';
          final out = <String, dynamic>{...v, 'status': 'active'};
          if (v['credit_days'] != null) {
            out['credit_days'] = rmNum(v['credit_days']).round();
          }
          final no = await allocateWithRollover(
              context,
              () async => await SupaFlow.client.rpc('next_doc_number', params: {
                    'p_org': AppSession.instance.currentOrgId,
                    'p_doc_type': 'contract',
                    'p_branch': null,
                    'p_fy': rmCurrentFy(),
                  }));
          if (no != null) out['contract_no'] = '$no';
          return out;
        },
      ),
      views: [
        RmView(
          label: 'Accounts',
          table: 'customers',
          orderBy: 'name',
          ascending: true,
          query: (q) => q
              .isFilter('deleted_at', null)
              .or('customer_type.neq.individual,gstin.not.is.null'),
          stats: (rows) => [
            RmStat('Accounts', '${rows.length}'),
            RmStat('With GSTIN',
                '${rows.where((r) => '${r['gstin'] ?? ''}'.isNotEmpty).length}'),
            RmStat('On credit',
                '${rows.where((r) => rmNum(r['credit_days']) > 0).length}'),
          ],
          search: (r) => [r['name'], r['company_name'], r['gstin'], r['phone']]
              .whereType<Object>()
              .join(' '),
          row: (context, r) => RmRow(
            icon: Icons.domain_rounded,
            tone: NgStatus.blue,
            title: '${r['company_name'] ?? r['name'] ?? ''}',
            subtitle: [
              if (r['company_name'] != null) '${r['name']}',
              if ('${r['gstin'] ?? ''}'.isNotEmpty) '${r['gstin']}',
              if (r['city'] != null) '${r['city']}',
            ].join(' · '),
            amount: r['credit_limit'] == null ? null : rmMoney(r['credit_limit']),
            status: rmNum(r['credit_days']) > 0
                ? '${rmNum(r['credit_days']).round()} days credit'
                : null,
            statusTone: NgStatus.amber,
            onTap: r['id'] == null
                ? null
                : () => context.pushNamed(
                      CustomerDetailPageWidget.routeName,
                      queryParameters: {
                        'customerId': serializeParam('${r['id']}', ParamType.String),
                      }.withoutNulls,
                    ),
          ),
          emptyText: 'No business customers yet. A customer with a GSTIN, '
              'or marked as a company in Customers, shows here.',
        ),
        RmView(
          label: 'Contracts',
          table: 'contracts',
          orderBy: 'start_date',
          query: (q) => q.isFilter('deleted_at', null),
          row: (context, r) => RmRow(
            icon: Icons.handshake_outlined,
            tone: NgStatus.accent,
            title: '${r['contract_no'] ?? ''} · ${r['title'] ?? ''}',
            subtitle: [
              '${rmDate(r['start_date'], 'd MMM yy')} – ${rmDate(r['end_date'], 'd MMM yy')}',
              if (r['billing_cycle'] != null) '${r['billing_cycle']}',
            ].join(' · '),
            amount: r['contract_value'] == null ? null : rmMoney(r['contract_value']),
            status: _human(r['status']),
          ),
          emptyText: 'No contracts recorded.',
        ),
      ],
    );
  }
}

/// Part-load & routes (handoff Operations): trips carrying more than one
/// order, from `trips` and `trip_orders`.
class PartLoadPage extends StatelessWidget {
  const PartLoadPage({super.key});

  static String routeName = 'PartLoadPage';
  static String routePath = '/part-load';

  static Future<List<RmMap>> _load() async {
    final links = await _rows(OrgScope.read(
        SupaFlow.client.from('trip_orders').select('trip_id, order_id, cft_share')));
    final byTrip = <String, List<RmMap>>{};
    for (final l in links) {
      byTrip.putIfAbsent('${l['trip_id']}', () => []).add(l);
    }
    final trips = await _rows(OrgScope.read(SupaFlow.client.from('trips').select())
        .isFilter('deleted_at', null)
        .order('start_date', ascending: false)
        .limit(300));
    return [
      for (final t in trips)
        {
          ...t,
          '_orders': byTrip['${t['id']}'] ?? const <RmMap>[],
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    int n(RmMap r) => (r['_orders'] as List).length;
    return RecordModulePage(
      title: 'Part-load & routes',
      subtitle: 'Trips carrying more than one job',
      views: [
        RmView(
          label: 'Trips',
          load: _load,
          note: 'Orders are added to a trip from the trip itself, in Trips.',
          stats: (rows) => [
            RmStat('Part-load trips', '${rows.where((r) => n(r) > 1).length}'),
            RmStat('Orders on trips',
                '${rows.fold<int>(0, (s, r) => s + n(r))}'),
            RmStat('Trips', '${rows.length}'),
          ],
          filters: [
            RmFilter('Part-load', (r) => n(r) > 1),
            RmFilter('All trips', (r) => true),
          ],
          row: (context, r) {
            final orders = (r['_orders'] as List)
                .map((o) => '${(o as Map)['order_id']}')
                .toList();
            return RmRow(
              icon: Icons.route_rounded,
              tone: orders.length > 1 ? NgStatus.accent : NgStatus.neutral,
              title:
                  '${r['trip_no'] ?? 'Trip'} · ${r['from_loc'] ?? ''} → ${r['to_loc'] ?? ''}',
              subtitle: [
                rmDate(r['start_date']),
                if (r['vehicle_no'] != null) '${r['vehicle_no']}',
                if (orders.isNotEmpty) orders.join(', '),
              ].join(' · '),
              status: '${orders.length} ${orders.length == 1 ? 'order' : 'orders'}',
              statusTone: orders.length > 1 ? NgStatus.accent : NgStatus.neutral,
            );
          },
          emptyText: 'No trips with more than one order yet.',
        ),
      ],
    );
  }
}

/// Diesel advance (handoff Transport): cash floats handed to a driver or
/// supervisor for a job, from `job_expense_floats`. The amount is what
/// the vendor actually handed over — the field opens empty.
class DieselAdvancePage extends StatefulWidget {
  const DieselAdvancePage({super.key});

  static String routeName = 'DieselAdvancePage';
  static String routePath = '/diesel-advance';

  @override
  State<DieselAdvancePage> createState() => _DieselAdvancePageState();
}

class _DieselAdvancePageState extends State<DieselAdvancePage> {
  List<RmMap>? _staff;

  /// Bumped after a settle so the list reloads.
  int _rev = 0;

  /// BUG-050 (3 Nov 2026): advances could be given but never settled —
  /// the "Settled" filter could never fill and staff cash-out couldn't be
  /// reconciled. Owner taps an open advance, enters what was spent; the
  /// rest is what came back.
  Future<void> _settle(RmMap r, String who) async {
    final issued = rmNum(r['issued_amount']);
    final ctrl = TextEditingController(text: issued.toStringAsFixed(0));
    final spent = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final s = double.tryParse(ctrl.text.trim());
          final back = s == null ? null : issued - s;
          return AlertDialog(
            title: Text('Settle advance — $who'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Given: ${rmMoney(issued)}'),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Actually spent (₹)'),
                  onChanged: (_) => setD(() {}),
                ),
                const SizedBox(height: 8),
                if (back != null)
                  Text(back >= 0
                      ? 'Returned in cash: ${rmMoney(back)}'
                      : 'Spent ${rmMoney(-back)} more than given — pay it back to them'),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: s == null || s < 0
                      ? null
                      : () => Navigator.pop(ctx, s),
                  child: const Text('Settle')),
            ],
          );
        },
      ),
    );
    if (spent == null) return;
    try {
      await OrgScope.write(SupaFlow.client.from('job_expense_floats').update({
        'status': 'reconciled',
        'reconciled_amount': spent,
        'reconciled_at': DateTime.now().toUtc().toIso8601String(),
        'reconciled_by': SupaFlow.client.auth.currentUser?.id,
      })).eq('id', '${r['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Advance settled — spent ${rmMoney(spent)}, '
              'returned ${rmMoney(issued - spent)}.')));
      setState(() => _rev++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not settle. ${friendlyError(e)}')));
    }
  }

  @override
  void initState() {
    super.initState();
    _rows(OrgScope.read(SupaFlow.client.from('staff').select('id, name, role'))
            .eq('active', true)
            .order('name', ascending: true))
        .then((s) => mounted ? setState(() => _staff = s) : null)
        .catchError((_) => mounted ? setState(() => _staff = const []) : null);
  }

  @override
  Widget build(BuildContext context) {
    final staff = _staff;
    if (staff == null) {
      return Scaffold(
        backgroundColor: NgPalette.of(context).bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final names = {for (final s in staff) '${s['id']}': '${s['name'] ?? ''}'};
    bool open(RmMap r) => r['status'] != 'reconciled';
    final isOwner = AppSession.instance.currentStaffId == null;
    return RecordModulePage(
      key: ValueKey('diesel-$_rev'),
      title: 'Diesel advance',
      subtitle: 'Cash given for a job, and what came back',
      // job_expense_floats INSERT is owner-only in RLS (is_org_owner), so
      // the button mirrors it rather than offering a save Postgres
      // refuses — CLAUDE.md's exception to the canActive rule.
      add: AppSession.instance.currentStaffId != null ? null : RmAdd(
        title: 'Give an advance',
        table: 'job_expense_floats',
        fields: [
          RmField('staff_id', 'Given to',
              kind: RmKind.choice,
              required: true,
              options: [for (final s in staff) '${s['id']}'],
              optionLabels: [for (final s in staff) '${s['name'] ?? ''}']),
          const RmField('order_id', 'Order ID', mono: true),
          const RmField('issued_amount', 'Amount ₹',
              kind: RmKind.number, required: true),
          const RmField('notes', 'Note'),
        ],
        prepare: (v) async {
          if (rmNum(v['issued_amount']) <= 0) throw 'Enter the amount given.';
          return {
            ...v,
            'status': 'open',
            'issued_at': DateTime.now().toUtc().toIso8601String(),
          };
        },
      ),
      views: [
        RmView(
          label: 'Advances',
          table: 'job_expense_floats',
          orderBy: 'issued_at',
          stats: (rows) {
            final o = rows.where(open);
            return [
              RmStat('Open', '${o.length}'),
              RmStat('Out with staff',
                  rmMoney(o.fold<double>(0, (s, r) => s + rmNum(r['issued_amount'])))),
              RmStat('Settled', '${rows.length - o.length}'),
            ];
          },
          filters: [
            RmFilter('Open', open),
            RmFilter('Settled', (r) => !open(r)),
            RmFilter('All', (r) => true),
          ],
          row: (context, r) => RmRow(
            icon: Icons.currency_rupee_rounded,
            tone: open(r) ? NgStatus.amber : NgStatus.green,
            title: [
              names['${r['staff_id']}'] ?? 'Staff',
              if (r['order_id'] != null) '${r['order_id']}',
            ].join(' · '),
            subtitle: [
              rmDate(r['issued_at']),
              if (r['reconciled_amount'] != null)
                'spent ${rmMoney(r['reconciled_amount'])}',
              if ('${r['notes'] ?? ''}'.isNotEmpty) '${r['notes']}',
            ].join(' · '),
            amount: rmMoney(r['issued_amount']),
            status: open(r) ? 'Open · tap to settle' : 'Settled',
            statusTone: open(r) ? NgStatus.amber : NgStatus.green,
            onTap: open(r) && isOwner
                ? () => _settle(r, names['${r['staff_id']}'] ?? 'Staff')
                : null,
          ),
          emptyText: 'No advances given.',
        ),
      ],
    );
  }
}

/// Hired trucks (handoff Transport): trips run on a hired vehicle and the
/// vehicles you rent rather than own.
class HiredTrucksPage extends StatelessWidget {
  const HiredTrucksPage({super.key});

  static String routeName = 'HiredTrucksPage';
  static String routePath = '/hired-trucks';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Hired trucks',
      subtitle: 'Vehicles you hire for a job',
      views: [
        RmView(
          label: 'Hired trips',
          table: 'trips',
          orderBy: 'start_date',
          query: (q) => q.eq('is_hired', true).isFilter('deleted_at', null),
          note: 'A trip is marked hired, with its hire charge, in Trips.',
          stats: (rows) => [
            RmStat('Hired trips', '${rows.length}'),
            RmStat('This month',
                '${rows.where((r) => rmThisMonth(r['start_date'])).length}'),
            RmStat('Hire this month', rmMoney(rows
                .where((r) => rmThisMonth(r['start_date']))
                .fold<double>(0, (s, r) => s + rmNum(r['hire_amount'])))),
          ],
          row: (context, r) => RmRow(
            icon: Icons.local_shipping_outlined,
            tone: NgStatus.accent,
            title:
                '${r['vehicle_no'] ?? 'Hired vehicle'} · ${r['from_loc'] ?? ''} → ${r['to_loc'] ?? ''}',
            subtitle: [
              rmDate(r['start_date']),
              if (r['driver_name'] != null) '${r['driver_name']}',
              if (r['trip_no'] != null) '${r['trip_no']}',
            ].join(' · '),
            amount: r['hire_amount'] == null ? null : rmMoney(r['hire_amount']),
            status: _human(r['status']),
          ),
          emptyText: 'No hired trips yet.',
        ),
        RmView(
          label: 'Rented vehicles',
          table: 'vehicles',
          orderBy: 'reg_no',
          ascending: true,
          query: (q) => q.neq('owner_type', 'own').isFilter('deleted_at', null),
          row: (context, r) => RmRow(
            icon: Icons.directions_car_outlined,
            tone: NgStatus.blue,
            title: '${r['reg_no'] ?? ''} · ${r['vehicle_type'] ?? ''}',
            subtitle: [
              _human(r['owner_type']),
              if (r['agreement_end'] != null)
                'agreement to ${rmDate(r['agreement_end'], 'd MMM yyyy')}',
            ].join(' · '),
            amount: r['monthly_rent'] == null
                ? null
                : '${rmMoney(r['monthly_rent'])}/mo',
          ),
          emptyText: 'Every vehicle in Fleet is your own.',
        ),
      ],
    );
  }
}

/// Staff documents (handoff People): files attached to staff records,
/// from `documents`, uploaded with + (private storage).
class StaffDocumentsPage extends StatelessWidget {
  const StaffDocumentsPage({super.key});

  static String routeName = 'StaffDocumentsPage';
  static String routePath = '/staff-documents';

  static Future<List<RmMap>> _load() async {
    final staff = await _rows(
        OrgScope.read(SupaFlow.client.from('staff').select('id, name')));
    final names = {for (final s in staff) '${s['id']}': '${s['name'] ?? ''}'};
    final docs = await _rows(OrgScope.read(SupaFlow.client.from('documents').select())
        .eq('entity_type', 'staff')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false));
    return [
      for (final d in docs) {...d, '_name': names['${d['entity_id']}'] ?? 'Staff'},
    ];
  }

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Staff documents',
      subtitle: 'ID, licence and joining papers',
      // Uploading was impossible anywhere in the app (BUG-026, 4 Nov 2026).
      add: const RmAdd(
        title: 'Upload staff document',
        custom: showStaffDocumentUpload,
      ),
      views: [
        RmView(
          label: 'Documents',
          load: _load,
          stats: (rows) => [
            RmStat('Documents', '${rows.length}'),
            RmStat('Staff covered',
                '${rows.map((r) => r['entity_id']).toSet().length}'),
            RmStat('Sensitive',
                '${rows.where((r) => r['is_sensitive'] == true).length}'),
          ],
          search: (r) => [r['_name'], r['doc_type'], r['file_name']]
              .whereType<Object>()
              .join(' '),
          row: (context, r) => RmRow(
            icon: r['is_sensitive'] == true
                ? Icons.lock_outline_rounded
                : Icons.badge_outlined,
            tone: NgStatus.blue,
            title: '${r['_name']} · ${_human(r['doc_type'])}',
            subtitle: [
              '${r['file_name'] ?? ''}',
              rmDate(r['created_at']),
            ].where((x) => x.isNotEmpty).join(' · '),
            onTap: () => openStaffDocument(context, r),
          ),
          emptyText: 'No staff documents yet. Tap + to upload one.',
        ),
      ],
    );
  }
}

/// Labour contractors (handoff People): vendors of type `labour`. Adding
/// and paying them stays in Vendors, which already handles bills and TDS.
class LabourContractorsPage extends StatelessWidget {
  const LabourContractorsPage({super.key});

  static String routeName = 'LabourContractorsPage';
  static String routePath = '/labour-contractors';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Labour contractors',
      subtitle: 'Crews you hire through a contractor',
      views: [
        RmView(
          label: 'Contractors',
          table: 'vendors',
          orderBy: 'name',
          ascending: true,
          query: (q) => q.eq('vendor_type', 'labour').isFilter('deleted_at', null),
          note: 'Add a contractor, record their bills and pay them from '
              'Vendors, with the type set to Labour Contractor.',
          stats: (rows) => [
            RmStat('Contractors', '${rows.length}'),
            RmStat('Active', '${rows.where((r) => r['active'] != false).length}'),
            RmStat('TDS applies',
                '${rows.where((r) => r['tds_applicable'] == true).length}'),
          ],
          row: (context, r) => RmRow(
            icon: Icons.engineering_outlined,
            tone: NgStatus.accent,
            title: '${r['name'] ?? ''}',
            subtitle: [
              if (r['contact_person'] != null) '${r['contact_person']}',
              if (r['phone'] != null) '${r['phone']}',
              if (r['city'] != null) '${r['city']}',
            ].join(' · '),
            status: r['active'] == false ? 'Inactive' : null,
            onTap: r['id'] == null
                ? null
                : () => context.pushNamed(
                      VendorDetailPageWidget.routeName,
                      queryParameters: {
                        'vendorId': serializeParam('${r['id']}', ParamType.String),
                      }.withoutNulls,
                    ),
          ),
          emptyText: 'No labour contractors yet.',
        ),
      ],
    );
  }
}

/// Backup & offline (handoff Setup). "Download all my data" builds one
/// Excel workbook in the app (5 Nov 2026, lib/backend/data_export.dart);
/// the lists below show what has been exported or backed up.
class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  static String routeName = 'BackupPage';
  static String routePath = '/backup';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Backup & offline',
      subtitle: 'Copies of your data',
      header: (context, reload) => _ExportAllCard(onDone: reload),
      views: [
        RmView(
          label: 'Backups',
          table: 'backup_registry',
          orderBy: 'created_at',
          note: 'Automatic scheduled backups are not built yet. Use '
              '"Download all my data" above for a full copy any time.',
          row: (context, r) => RmRow(
            icon: Icons.cloud_done_outlined,
            tone: r['status'] == 'completed' ? NgStatus.green : NgStatus.amber,
            title: '${_human(r['backup_type'])} · ${_human(r['scope'])}',
            subtitle: [
              rmDate(r['created_at'], 'd MMM yyyy, h:mm a'),
              if (r['file_size_bytes'] != null)
                '${(rmNum(r['file_size_bytes']) / 1048576).toStringAsFixed(1)} MB',
            ].join(' · '),
            status: _human(r['status']),
          ),
          emptyText: 'No backups yet.',
        ),
        RmView(
          label: 'Exports',
          table: 'export_jobs',
          orderBy: 'created_at',
          row: (context, r) => RmRow(
            icon: Icons.file_download_outlined,
            tone: NgStatus.blue,
            title: '${_human(r['module'])} · ${'${r['format'] ?? ''}'.toUpperCase()}',
            subtitle: [
              rmDate(r['created_at'], 'd MMM yyyy'),
              if (r['row_count'] != null) '${r['row_count']} rows',
            ].join(' · '),
            status: _human(r['status']),
          ),
          emptyText: 'No exports yet.',
        ),
      ],
    );
  }
}

/// "Download all my data": one Excel file, a sheet per record type.
class _ExportAllCard extends StatefulWidget {
  const _ExportAllCard({required this.onDone});
  final Future<void> Function() onDone;

  @override
  State<_ExportAllCard> createState() => _ExportAllCardState();
}

class _ExportAllCardState extends State<_ExportAllCard> {
  bool _busy = false;
  int _done = 0;
  int _total = kExportTables.length;
  String? _result;
  bool _failed = false;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _done = 0;
      _result = null;
      _failed = false;
    });
    try {
      final r = await exportAllData(
        onProgress: (d, t) {
          if (mounted) {
            setState(() {
              _done = d;
              _total = t;
            });
          }
        },
      );
      final where = await saveExcelFile(r.fileName, r.bytes);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = where == null
            ? 'The file was not saved.'
            : 'Saved ${r.fileName}.xlsx · ${r.totalRows} rows'
                '${r.skipped.isEmpty ? '' : ' · ${r.skipped.length} lists not readable with this login'}';
        _failed = where == null;
      });
      await widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _result = 'Could not build the export. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return NgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.download_rounded, color: c.acc),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Download all my data',
                  style: NgFonts.geist(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
              'One Excel file with a sheet for orders, leads, customers, '
              'payments, expenses, staff, fleet and settings. Opens in Excel '
              'or Google Sheets. PINs and link codes are left out.',
              style: NgFonts.geist(fontSize: 12.5, height: 1.4, color: c.mute)),
          const SizedBox(height: 12),
          if (_busy) ...[
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            const SizedBox(height: 6),
            Text('Reading $_done of $_total lists…',
                style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          ] else
            NgPrimaryButton(
              label: 'Download Excel',
              icon: Icons.file_download_outlined,
              onPressed: _run,
            ),
          if (_result != null) ...[
            const SizedBox(height: 8),
            Text(_result!,
                style: NgFonts.geist(
                    fontSize: 13, color: _failed ? c.red : c.green)),
          ],
        ],
      ),
    );
  }
}

/// Shared staff loader for the two People modules below.
/// Loads rows once, then builds (a form's choice list, say).
class _WithRows extends StatefulWidget {
  const _WithRows({required this.load, required this.builder});
  final Future<List<RmMap>> Function() load;
  final Widget Function(List<RmMap> rows) builder;

  @override
  State<_WithRows> createState() => _WithRowsState();
}

class _WithRowsState extends State<_WithRows> {
  List<RmMap>? _r;

  @override
  void initState() {
    super.initState();
    widget
        .load()
        .then((r) => mounted ? setState(() => _r = r) : null)
        .catchError((_) => mounted ? setState(() => _r = const []) : null);
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) {
      return Scaffold(
        backgroundColor: NgPalette.of(context).bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return widget.builder(r);
  }
}

class _WithStaff extends StatefulWidget {
  const _WithStaff({required this.builder});
  final Widget Function(List<RmMap> staff) builder;

  @override
  State<_WithStaff> createState() => _WithStaffState();
}

class _WithStaffState extends State<_WithStaff> {
  List<RmMap>? _s;

  @override
  void initState() {
    super.initState();
    _rows(OrgScope.read(SupaFlow.client.from('staff').select('id, name, role'))
            .eq('active', true)
            .order('name', ascending: true))
        .then((s) => mounted ? setState(() => _s = s) : null)
        .catchError((_) => mounted ? setState(() => _s = const []) : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return Scaffold(
        backgroundColor: NgPalette.of(context).bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return widget.builder(s);
  }
}

/// The screen a migration-backed module shows before its tables exist.
Widget _awaitingMigration(String title, String subtitle) => RecordModulePage(
      title: title,
      subtitle: subtitle,
      views: [
        RmView(
          label: title,
          load: () async => const [],
          // Needs supabase/20261021_staff_leave_and_incentives.sql.
          note: 'This section is not switched on yet. It will open once '
              'Nagarva enables it for your company.',
          row: (context, r) => const RmRow(title: ''),
          emptyText: 'Nothing to show yet.',
        ),
      ],
    );

/// Leave (handoff People): who was off, when, and why.
class LeavePage extends StatelessWidget {
  const LeavePage({super.key});

  static String routeName = 'LeavePage';
  static String routePath = '/leave';

  @override
  Widget build(BuildContext context) {
    if (!kStaffLeaveIncentivesLive) {
      return _awaitingMigration('Leave', 'Who is off, and when');
    }
    return _WithStaff(builder: (staff) {
      final names = {for (final s in staff) '${s['id']}': '${s['name'] ?? ''}'};
      bool current(RmMap r) {
        final f = rmParseDate(r['from_date']), t = rmParseDate(r['to_date']);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        return f != null && t != null && !f.isAfter(today) && !t.isBefore(today);
      }

      return RecordModulePage(
        title: 'Leave',
        subtitle: 'Who is off, and when',
        add: RmAdd(
          title: 'Record leave',
          table: 'staff_leaves',
          fields: [
            RmField('staff_id', 'Who',
                kind: RmKind.choice,
                required: true,
                options: [for (final s in staff) '${s['id']}'],
                optionLabels: [for (final s in staff) '${s['name'] ?? ''}']),
            const RmField('leave_type', 'Type', kind: RmKind.choice,
                required: true,
                options: ['casual', 'sick', 'paid', 'unpaid', 'other'],
                optionLabels: ['Casual', 'Sick', 'Paid', 'Unpaid', 'Other']),
            const RmField('from_date', 'From', kind: RmKind.date, required: true),
            const RmField('to_date', 'To', kind: RmKind.date, required: true),
            const RmField('reason', 'Reason'),
          ],
          prepare: (v) async {
            final f = DateTime.parse('${v['from_date']}');
            final t = DateTime.parse('${v['to_date']}');
            if (t.isBefore(f)) throw '"To" is before "From".';
            return {...v, 'days': t.difference(f).inDays + 1};
          },
        ),
        views: [
          RmView(
            label: 'Leave',
            table: 'staff_leaves',
            orderBy: 'from_date',
            stats: (rows) => [
              RmStat('Off today', '${rows.where(current).length}'),
              RmStat('Days this month', rows
                  .where((r) => rmThisMonth(r['from_date']))
                  .fold<double>(0, (s, r) => s + rmNum(r['days']))
                  .toStringAsFixed(0)),
              RmStat('Records', '${rows.length}'),
            ],
            filters: [
              const RmFilter('All', _all),
              RmFilter('Off today', current),
            ],
            row: (context, r) => RmRow(
              icon: Icons.event_busy_outlined,
              tone: current(r) ? NgStatus.amber : NgStatus.neutral,
              title: '${names['${r['staff_id']}'] ?? 'Staff'} · ${_human(r['leave_type'])}',
              subtitle: [
                '${rmDate(r['from_date'])} – ${rmDate(r['to_date'])}',
                if ('${r['reason'] ?? ''}'.isNotEmpty) '${r['reason']}',
              ].join(' · '),
              amount: '${rmNum(r['days']).toStringAsFixed(rmNum(r['days']) % 1 == 0 ? 0 : 1)} d',
              status: _human(r['status']),
            ),
            emptyText: 'No leave recorded.',
          ),
        ],
      );
    });
  }

  static bool _all(RmMap _) => true;
}

/// Overtime & incentives (handoff People): extra earned on top of wages.
/// The amount is the vendor's own figure; nothing is suggested.
class IncentivesPage extends StatelessWidget {
  const IncentivesPage({super.key});

  static String routeName = 'IncentivesPage';
  static String routePath = '/incentives';

  @override
  Widget build(BuildContext context) {
    if (!kStaffLeaveIncentivesLive) {
      return _awaitingMigration('Overtime & incentives', 'Extra earned on top of wages');
    }
    return _WithStaff(builder: (staff) {
      final names = {for (final s in staff) '${s['id']}': '${s['name'] ?? ''}'};
      return RecordModulePage(
        title: 'Overtime & incentives',
        subtitle: 'Extra earned on top of wages',
        add: RmAdd(
          title: 'Add overtime or incentive',
          table: 'staff_incentives',
          fields: [
            RmField('staff_id', 'Who',
                kind: RmKind.choice,
                required: true,
                options: [for (final s in staff) '${s['id']}'],
                optionLabels: [for (final s in staff) '${s['name'] ?? ''}']),
            const RmField('kind', 'Type', kind: RmKind.choice, required: true,
                options: ['overtime', 'incentive', 'bonus'],
                optionLabels: ['Overtime', 'Incentive', 'Bonus']),
            const RmField('entry_date', 'Date', kind: RmKind.date),
            const RmField('order_id', 'Order ID', mono: true),
            const RmField('hours', 'Hours (overtime)', kind: RmKind.number),
            const RmField('amount', 'Amount ₹', kind: RmKind.number, required: true),
            const RmField('note', 'Note'),
          ],
          prepare: (v) async {
            if (rmNum(v['amount']) <= 0) throw 'Enter the amount earned.';
            return v;
          },
        ),
        views: [
          RmView(
            label: 'Entries',
            table: 'staff_incentives',
            orderBy: 'entry_date',
            stats: (rows) {
              final m = rows.where((r) => rmThisMonth(r['entry_date']));
              return [
                RmStat('This month',
                    rmMoney(m.fold<double>(0, (s, r) => s + rmNum(r['amount'])))),
                RmStat('Unpaid', rmMoney(rows
                    .where((r) => r['paid'] != true)
                    .fold<double>(0, (s, r) => s + rmNum(r['amount'])))),
                RmStat('OT hours', m
                    .fold<double>(0, (s, r) => s + rmNum(r['hours']))
                    .toStringAsFixed(0)),
              ];
            },
            filters: [
              RmFilter('Unpaid', (r) => r['paid'] != true),
              RmFilter('All', (r) => true),
            ],
            row: (context, r) => RmRow(
              icon: Icons.emoji_events_outlined,
              tone: NgStatus.accent,
              title: '${names['${r['staff_id']}'] ?? 'Staff'} · ${_human(r['kind'])}',
              subtitle: [
                rmDate(r['entry_date']),
                if (r['hours'] != null) '${rmNum(r['hours']).toStringAsFixed(1)} h',
                if (r['order_id'] != null) '${r['order_id']}',
                if ('${r['note'] ?? ''}'.isNotEmpty) '${r['note']}',
              ].join(' · '),
              amount: rmMoney(r['amount']),
              status: r['paid'] == true ? 'Paid' : 'Unpaid',
              statusTone: r['paid'] == true ? NgStatus.green : NgStatus.amber,
            ),
            emptyText: 'Nothing recorded yet.',
          ),
        ],
      );
    });
  }
}
