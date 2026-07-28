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
const Map<String, ({String label, List<String> titleFields})> _kBins = {
  'leads': (label: 'Leads', titleFields: ['customer', 'phone']),
  'quotations': (label: 'Quotations', titleFields: ['customer', 'total']),
  'orders': (label: 'Orders', titleFields: ['id', 'customer']),
  'payment_entries': (label: 'Payments', titleFields: ['order_id', 'amount']),
  'expenses': (label: 'Expenses', titleFields: ['category', 'amount']),
  'materials': (label: 'Materials', titleFields: ['name', 'quantity']),
  'vehicles': (label: 'Fleet', titleFields: ['vehicle_no', 'model']),
};

class _RecycleBinPageState extends State<RecycleBinPage> {
  final Map<String, List<Map<String, dynamic>>> _data = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
