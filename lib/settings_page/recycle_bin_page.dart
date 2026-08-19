import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/backend/soft_delete.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Settings → Deleted Items (live-test fix brief #2, item 11.6).
///
/// Owner-only list of soft-deleted rows from the last 90 days with a
/// Restore action — "turns every accidental delete into a non-event".
///
/// Reads deliberately bypass `SupabaseTable.queryRows`: that path now
/// appends `deleted_at is null` for every soft-delete table (see
/// table.dart), which is exactly the opposite of what this screen needs.
/// It goes through SoftDeleteService.recycleBin instead.
class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  static String routeName = 'RecycleBinPage';
  static String routePath = '/deleted-items';

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

/// Table -> (label, field to show as the row's title).
///
/// customers/vendors/vendor_bills added 16 Aug 2026 — all three already
/// had working delete (DeleteAction wired into their detail pages) but
/// were missing here, so missing the 10s Undo snackbar left no way back
/// at all. See MEMORY.md / CLAUDE.md for the finding.
///
/// rate_cards/tasks/trips/vendor_payments added 17 Aug 2026 — found live,
/// not by reading: delete UI was wired into their own pages and the
/// columns were in kSoftDeleteTables, but this map was never updated
/// alongside them, so their deleted rows were unreachable here too —
/// the identical bug class as the entry above, caught during Item 11's
/// device-verification pass rather than repeating it a second time.
///
/// Fleet's titleFields corrected same pass: read `vehicle_no`, a column
/// `vehicles` has never had (the real column is `reg_no` — see
/// fleet_page_widget.dart's own `regNo` getter) — every deleted vehicle
/// rendered as "(untitled)" in this list. Pre-existing, not introduced
/// this session; also caught live, not by reading.
const Map<String, ({String label, List<String> titleFields})> _kBins = {
  'leads': (label: 'Leads', titleFields: ['customer', 'phone']),
  'quotations': (label: 'Quotations', titleFields: ['customer', 'total']),
  'orders': (label: 'Orders', titleFields: ['id', 'customer']),
  'payment_entries': (label: 'Payments', titleFields: ['order_id', 'amount']),
  'expenses': (label: 'Expenses', titleFields: ['category', 'amount']),
  'materials': (label: 'Materials', titleFields: ['name', 'quantity']),
  'vehicles': (label: 'Fleet', titleFields: ['reg_no', 'vehicle_type']),
  'customers': (label: 'Customers', titleFields: ['name', 'phone']),
  'vendors': (label: 'Vendors', titleFields: ['name', 'phone']),
  'vendor_bills': (label: 'Vendor Bills', titleFields: ['bill_no', 'total_amount']),
  'vendor_payments': (label: 'Vendor Payments', titleFields: ['mode', 'amount']),
  'rate_cards': (label: 'Rate Cards', titleFields: ['name', 'code']),
  'tasks': (label: 'Tasks', titleFields: ['title', 'task_type']),
  'trips': (label: 'Trips', titleFields: ['trip_no', 'vehicle_no']),
};

class _RecycleBinPageState extends State<RecycleBinPage> {
  final Map<String, List<Map<String, dynamic>>> _data = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _assertBinsMatchSoftDeleteTables();
    _load();
  }

  /// `_kBins` has drifted out of sync with `kSoftDeleteTables`
  /// (soft_delete.dart) three times now — a table gets its delete UI
  /// wired and added to `kSoftDeleteTables`, and this map is forgotten,
  /// so its deleted rows become unreachable here (or, for Fleet, showed
  /// up with the wrong title field). `_kBins` can't fully *derive* from
  /// `kSoftDeleteTables` — it carries display metadata (a label, which
  /// columns to show as a row's title) that has no other source and
  /// isn't inferable from a table name — so this can't be automatic.
  /// What it CAN be is loud: this fails hard, in debug builds, the
  /// moment this screen is opened after the two lists diverge, instead
  /// of staying a silent gap someone finds by accident. `assert()` is
  /// stripped in release builds by design — this is a development-time
  /// tripwire, not a runtime guard; it deliberately doesn't run for
  /// Arun's own release build, only for whoever's making the next
  /// change to either list.
  void _assertBinsMatchSoftDeleteTables() {
    assert(() {
      final binKeys = _kBins.keys.toSet();
      final missingFromBins = kSoftDeleteTables.difference(binKeys);
      final extraInBins = binKeys.difference(kSoftDeleteTables);
      if (missingFromBins.isNotEmpty || extraInBins.isNotEmpty) {
        throw StateError(
          'recycle_bin_page.dart\'s _kBins is out of sync with '
          'kSoftDeleteTables (soft_delete.dart) — this has broken 3 '
          'times, add the table to BOTH.\n'
          'In kSoftDeleteTables but missing from _kBins: $missingFromBins\n'
          'In _kBins but not in kSoftDeleteTables: $extraInBins',
        );
      }
      return true;
    }());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      for (final table in _kBins.keys) {
        try {
          _data[table] = await SoftDeleteService.recycleBin(table: table);
        } catch (_) {
          // One table failing (e.g. the migration not run) shouldn't hide
          // the rest of the bin.
          _data[table] = const [];
        }
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _total =>
      _data.values.fold(0, (sum, rows) => sum + rows.length);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (!SoftDeleteService.isOwner) {
      return Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          title: const Text('Deleted Items'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              'Only the owner can view or restore deleted records.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 14, color: theme.secondaryText),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: const Text('Deleted Items'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Records deleted in the last 90 days. Restoring puts a '
                    'record back exactly where it was.',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.4,
                        color: theme.secondaryText),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: GoogleFonts.inter(
                            fontSize: 12.5, color: theme.error)),
                  if (_total == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 44, color: theme.secondaryText),
                          const SizedBox(height: 12),
                          Text('Nothing deleted',
                              style: GoogleFonts.interTight(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: theme.primaryText)),
                          const SizedBox(height: 6),
                          Text('Deleted records will show up here.',
                              style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: theme.secondaryText)),
                        ],
                      ),
                    ),
                  for (final entry in _kBins.entries)
                    if ((_data[entry.key] ?? []).isNotEmpty)
                      _section(theme, entry.key, entry.value.label,
                          entry.value.titleFields),
                ],
              ),
            ),
    );
  }

  Widget _section(FlutterFlowTheme theme, String table, String label,
      List<String> titleFields) {
    final rows = _data[table]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label (${rows.length})',
              style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: theme.primary)),
          const SizedBox(height: 6),
          for (final r in rows) _row(theme, table, r, titleFields),
        ],
      ),
    );
  }

  Widget _row(FlutterFlowTheme theme, String table, Map<String, dynamic> r,
      List<String> titleFields) {
    final title = titleFields
        .map((f) => r[f])
        .where((v) => v != null && '$v'.trim().isNotEmpty)
        .map((v) => '$v')
        .join(' · ');
    final deletedAt = DateTime.tryParse('${r['deleted_at']}');
    final reason = '${r['delete_reason'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? '(untitled)' : title,
                    style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryText)),
                if (deletedAt != null)
                  Text(
                    'Deleted ${DateFormat('d MMM yyyy, h:mm a').format(deletedAt.toLocal())}',
                    style: GoogleFonts.inter(
                        fontSize: 11.5, color: theme.secondaryText),
                  ),
                if (reason.isNotEmpty)
                  Text('Reason: $reason',
                      style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: theme.secondaryText)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _restore(table, '${r['id']}'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(String table, String id) async {
    try {
      await SoftDeleteService.restore(table: table, id: id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restored')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not restore: $e')),
        );
      }
    }
  }
}
