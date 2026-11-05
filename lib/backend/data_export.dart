import 'dart:typed_data';

import '/app_session.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/backend/xlsx_writer.dart';

/// "Download all my data" (5 Nov 2026, Backup & export).
///
/// A vendor must always be able to take their data out — read-only after
/// a trial ends included (CLAUDE.md, Item 32b: "reads, always"). This
/// builds one Excel workbook with a sheet per record type, read with the
/// signed-in person's own rights (RLS), so it can only ever contain this
/// company's rows.
///
/// The table list is EXPLICIT, not "every table with org_id": security
/// and system tables (PIN attempts, device tokens, WhatsApp keys, platform
/// audit, check-in secrets) never go into a file that gets emailed around.
/// Inside the listed tables, [_kSecretColumns] are blanked.
class ExportTable {
  const ExportTable(this.table, this.sheet, this.group, {this.orderBy = 'id'});
  final String table;
  final String sheet;
  final String group;

  /// A unique column, so 1,000-row pages never overlap or skip.
  final String orderBy;
}

const kExportTables = <ExportTable>[
  // Sales
  ExportTable('leads', 'Leads', 'Sales'),
  ExportTable('follow_up_logs', 'Follow-ups', 'Sales'),
  ExportTable('customers', 'Customers', 'Sales'),
  ExportTable('customer_contacts', 'Customer contacts', 'Sales'),
  ExportTable('customer_addresses', 'Customer addresses', 'Sales'),
  ExportTable('customer_surveys', 'Surveys', 'Sales'),
  ExportTable('quotations', 'Quotations', 'Sales'),
  ExportTable('quote_versions', 'Quote versions', 'Sales'),
  ExportTable('quote_outcomes', 'Quote outcomes', 'Sales'),
  ExportTable('reviews', 'Reviews', 'Sales'),
  ExportTable('complaints', 'Complaints', 'Sales'),
  ExportTable('contracts', 'Contracts', 'Sales'),
  ExportTable('referrals', 'Referrals', 'Sales'),
  // Orders
  ExportTable('orders', 'Orders', 'Orders'),
  ExportTable('addons', 'Order extras', 'Orders'),
  ExportTable('order_staff', 'Order crew', 'Orders'),
  ExportTable('order_vendors', 'Order vendors', 'Orders'),
  ExportTable('order_status_history', 'Order status history', 'Orders'),
  ExportTable('pod_records', 'Proof of delivery', 'Orders'),
  ExportTable('document_signatures', 'Signatures', 'Orders'),
  ExportTable('lr_register', 'Lorry receipts', 'Orders'),
  ExportTable('eway_bills', 'E-way bills', 'Orders'),
  ExportTable('claims', 'Claims', 'Orders'),
  ExportTable('claim_items', 'Claim items', 'Orders'),
  ExportTable('insurance_policies', 'Insurance', 'Orders'),
  ExportTable('storage_jobs', 'Storage jobs', 'Orders'),
  ExportTable('storage_items', 'Storage items', 'Orders'),
  ExportTable('storage_billing_cycles', 'Storage billing', 'Orders'),
  // Money
  ExportTable('payment_entries', 'Payments received', 'Money'),
  ExportTable('receipts', 'Receipts', 'Money'),
  ExportTable('credit_notes', 'Credit notes', 'Money'),
  ExportTable('expenses', 'Expenses', 'Money'),
  ExportTable('expense_splits', 'Expense splits', 'Money'),
  ExportTable('vendor_bills', 'Vendor bills', 'Money'),
  ExportTable('vendor_payments', 'Vendor payments', 'Money'),
  ExportTable('tds_entries', 'TDS', 'Money'),
  ExportTable('bank_accounts', 'Bank accounts', 'Money'),
  ExportTable('account_transfers', 'Account transfers', 'Money'),
  ExportTable('journal_entries', 'Journal entries', 'Money'),
  ExportTable('journal_lines', 'Journal lines', 'Money'),
  ExportTable('ledger_entries', 'Ledger', 'Money'),
  ExportTable('transactions', 'Transactions', 'Money'),
  ExportTable('marketing_spend', 'Marketing spend', 'Money'),
  // People
  ExportTable('staff', 'Staff', 'People'),
  ExportTable('attendance', 'Attendance', 'People'),
  ExportTable('crew_checkins', 'Crew check-ins', 'People'),
  ExportTable('staff_advances', 'Staff advances', 'People'),
  ExportTable('staff_advance_entries', 'Advance entries', 'People'),
  ExportTable('staff_incentives', 'Overtime & incentives', 'People'),
  ExportTable('staff_leaves', 'Leaves', 'People'),
  ExportTable('salary_payments', 'Salary payments', 'People'),
  ExportTable('payroll_runs', 'Payroll runs', 'People'),
  ExportTable('payslips', 'Payslips', 'People'),
  // Fleet
  ExportTable('vehicles', 'Vehicles', 'Fleet'),
  ExportTable('trips', 'Trips', 'Fleet'),
  ExportTable('trip_orders', 'Trip orders', 'Fleet'),
  ExportTable('trip_expenses', 'Trip expenses', 'Fleet'),
  ExportTable('vehicle_trips', 'Field job trips', 'Fleet'),
  ExportTable('fuel_fills', 'Fuel', 'Fleet'),
  ExportTable('vehicle_service_logs', 'Vehicle service', 'Fleet'),
  // Stock & vendors
  ExportTable('vendors', 'Vendors', 'Stock'),
  ExportTable('materials', 'Materials', 'Stock'),
  ExportTable('stock_movements', 'Stock movements', 'Stock'),
  ExportTable('warehouses', 'Warehouses', 'Stock'),
  ExportTable('purchase_orders', 'Purchase orders', 'Stock'),
  ExportTable('purchase_order_items', 'PO items', 'Stock'),
  ExportTable('grn', 'Goods received', 'Stock'),
  // Setup
  ExportTable('branches', 'Branches', 'Setup'),
  ExportTable('lead_sources', 'Lead sources', 'Setup'),
  ExportTable('rate_cards', 'Rate cards', 'Setup'),
  ExportTable('rate_card_charges', 'Rate card charges', 'Setup'),
  ExportTable('rate_card_rules', 'Rate card slabs', 'Setup'),
  ExportTable('rate_card_floor_charges', 'Floor charges', 'Setup'),
  ExportTable('rate_card_multipliers', 'Multipliers', 'Setup'),
  ExportTable('number_series', 'Document numbers', 'Setup'),
  ExportTable('settings', 'Settings', 'Setup', orderBy: 'key'),
  ExportTable('tasks', 'Tasks', 'Setup'),
  ExportTable('reminders', 'Reminders', 'Setup'),
  ExportTable('documents', 'Documents', 'Setup'),
];

/// Never written to the file, in any listed table. Exact names — a
/// pattern like /pin/ would also blank `pincode`.
const _kSecretColumns = <String>{
  'pin',
  'pin_hash',
  'failed_pin_attempts',
  'pin_locked_until',
  'pin_lock_level',
  'token',
  'sign_token',
  'quotation_token',
  'tracking_token',
  'job_otp',
  'arrival_code',
  'secret',
  'code_hash',
  'code_hint',
};

/// Signature images are kept in the app; the file says so instead of
/// carrying a base64 blob nobody can read in a spreadsheet.
const _kImageColumns = <String>{'signature_data'};

class DataExportResult {
  DataExportResult(this.bytes, this.fileName, this.rowCounts, this.skipped);
  final Uint8List bytes;
  final String fileName;

  /// Sheet name -> rows written.
  final Map<String, int> rowCounts;

  /// Tables this login could not read (permission), by sheet name.
  final List<String> skipped;

  int get totalRows => rowCounts.values.fold(0, (s, n) => s + n);
}

/// Reads every listed table for the current company and builds the
/// workbook. [onProgress] gets (done, total) after each table.
Future<DataExportResult> exportAllData(
    {void Function(int done, int total)? onProgress}) async {
  final orgId = OrgScope.currentOrgId;
  if (orgId == null) {
    throw StateError('No company is open.');
  }
  final counts = <String, int>{};
  final skipped = <String>[];
  final sheets = <XlsxSheet>[];
  var done = 0;

  // Six lists at a time (5 Nov 2026): one after another took ~80 s for
  // 79 lists on a test company — a minute of "is it stuck?". Sheets are
  // still added in kExportTables order.
  const parallel = 6;
  final results = List<List<Map<String, dynamic>>?>.filled(
      kExportTables.length, null);
  for (var i = 0; i < kExportTables.length; i += parallel) {
    final batch = [
      for (var j = i; j < i + parallel && j < kExportTables.length; j++) j
    ];
    await Future.wait(batch.map((j) async {
      final t = kExportTables[j];
      try {
        results[j] = await _readAll(t.table, t.orderBy);
      } catch (_) {
        // No permission for this login, or the table is not in this
        // database yet. The About sheet lists it so nothing is silently
        // missing.
        results[j] = null;
      }
      done++;
      onProgress?.call(done, kExportTables.length);
    }));
  }
  for (var j = 0; j < kExportTables.length; j++) {
    final t = kExportTables[j];
    final rows = results[j];
    if (rows == null) {
      skipped.add(t.sheet);
      continue;
    }
    counts[t.sheet] = rows.length;
    if (rows.isNotEmpty) sheets.add(XlsxSheet(t.sheet, _toGrid(rows)));
  }

  final now = DateTime.now();
  final company = AppSession.instance.currentOrgName ?? '';
  final about = <List<Object?>>[
    ['Data export', company],
    ['Exported on', _stamp(now)],
    ['Exported by', AppSession.instance.currentStaffName ?? 'Owner'],
    ['Rows in total', counts.values.fold<int>(0, (s, n) => s + n)],
    [
      'Not included',
      'PINs, link tokens, arrival codes and check-in secrets are left out on purpose. Signature images stay in the app.'
    ],
    [],
    ['Group', 'Sheet', 'Rows'],
    for (final t in kExportTables)
      if (counts.containsKey(t.sheet))
        [t.group, t.sheet, counts[t.sheet]]
      else
        [t.group, t.sheet, 'Could not read with this login'],
  ];

  final bytes = buildXlsx([XlsxSheet('About', about), ...sheets]);
  final safeCompany = company
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final fileName =
      '${safeCompany.isEmpty ? 'Company' : safeCompany}_data_${_fileDate(now)}';

  // Record it in Exports (best effort: the file is the point).
  try {
    await SupaFlow.client.from('export_jobs').insert({
      ...OrgScope.stamp(),
      'export_type': 'full',
      'module': 'all',
      'format': 'xlsx',
      'status': 'completed',
      'row_count': counts.values.fold<int>(0, (s, n) => s + n),
      'filters': {'sheets': counts, if (skipped.isNotEmpty) 'skipped': skipped},
      'requested_by': SupaFlow.client.auth.currentUser?.id,
      'completed_at': now.toUtc().toIso8601String(),
    });
  } catch (_) {}

  return DataExportResult(bytes, fileName, counts, skipped);
}

/// All rows of [table] for this company, 1,000 at a time (PostgREST's
/// page size), ordered by a unique column so pages never overlap or skip.
Future<List<Map<String, dynamic>>> _readAll(String table, String orderBy) async {
  const page = 1000;
  final out = <Map<String, dynamic>>[];
  for (var from = 0;; from += page) {
    final List rows = await OrgScope.read(SupaFlow.client.from(table).select())
        .order(orderBy, ascending: true)
        .range(from, from + page - 1);
    for (final r in rows) {
      out.add(Map<String, dynamic>.from(r as Map));
    }
    if (rows.length < page) break;
  }
  return out;
}

/// Header row = every column seen (first-seen order, org_id dropped);
/// secrets removed.
List<List<Object?>> _toGrid(List<Map<String, dynamic>> rows) {
  final cols = <String>[];
  final seen = <String>{};
  for (final r in rows) {
    for (final k in r.keys) {
      if (k == 'org_id' || _kSecretColumns.contains(k)) continue;
      if (seen.add(k)) cols.add(k);
    }
  }
  return [
    cols,
    for (final r in rows)
      [
        for (final c in cols)
          if (_kImageColumns.contains(c) && r[c] != null &&
              '${r[c]}'.isNotEmpty)
            '(signature saved in the app)'
          else
            r[c],
      ],
  ];
}

String _two(int n) => n.toString().padLeft(2, '0');
String _fileDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _stamp(DateTime d) =>
    '${_two(d.day)}-${_two(d.month)}-${d.year} ${_two(d.hour)}:${_two(d.minute)}';
