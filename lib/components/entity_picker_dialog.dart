import 'package:flutter/material.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Corrections session, B1 (7 Aug 2026) — generalized picker: one dialog,
/// configured per entity type, instead of a new bespoke picker for every
/// table a "link this to X" dropdown needs. Built specifically to close
/// Tasks & Activities' gap (entity_type dropdown offered lead/customer/
/// vendor with no way to actually pick one, so those rows always wrote a
/// blank entity_id — unjoinable, unfilterable). [OrderPickerDialog]
/// (Insurance & Claims, Trips) is deliberately left as its own separate,
/// typed component rather than folded into this one — its three call
/// sites read fields off the full `OrdersRow` (customerId, etc.), not just
/// an id, and rewriting those to a generic result was out of scope for
/// closing Tasks & Activities' specific gap.
class EntityPickerConfig {
  const EntityPickerConfig({
    required this.table,
    required this.titleColumns,
    required this.searchColumns,
    this.subtitleColumn,
    required this.label,
  });

  final String table;

  /// Joined with ' · ' to build each result's title — e.g. an order shows
  /// id and customer together, a lead/customer/vendor just shows its name.
  final List<String> titleColumns;

  final List<String> searchColumns;
  final String? subtitleColumn;

  /// Shown in the dialog title ("Pick <label>") and the trigger button.
  final String label;
}

/// order/lead/customer/vendor — the four entity types Tasks & Activities'
/// entity_type dropdown offers. Keyed by that same string so a caller can
/// go straight from the dropdown's value to a config.
const kEntityPickerConfigs = <String, EntityPickerConfig>{
  'order': EntityPickerConfig(
    table: 'orders',
    titleColumns: ['id', 'customer'],
    subtitleColumn: 'phone',
    searchColumns: ['id', 'customer', 'phone'],
    label: 'Order',
  ),
  'lead': EntityPickerConfig(
    table: 'leads',
    titleColumns: ['customer'],
    subtitleColumn: 'phone',
    searchColumns: ['customer', 'phone'],
    label: 'Lead',
  ),
  'customer': EntityPickerConfig(
    table: 'customers',
    titleColumns: ['name'],
    subtitleColumn: 'phone',
    searchColumns: ['name', 'phone'],
    label: 'Customer',
  ),
  'vendor': EntityPickerConfig(
    table: 'vendors',
    titleColumns: ['name'],
    subtitleColumn: 'phone',
    searchColumns: ['name', 'phone'],
    label: 'Vendor',
  ),
};

/// What the caller actually needs: the row's id (to stamp into entity_id)
/// and a label (to show on the trigger button) — Tasks & Activities never
/// reads anything else off the picked row, so there's no reason to hand
/// back a typed row per entity type here.
class EntityPickedResult {
  const EntityPickedResult({required this.id, required this.label});
  final String id;
  final String label;
}

class EntityPickerDialog extends StatefulWidget {
  const EntityPickerDialog({super.key, required this.config});

  final EntityPickerConfig config;

  /// Returns null if [entityType] isn't a known config (defensive — every
  /// call site today only ever passes a value from its own dropdown, which
  /// is always one of [kEntityPickerConfigs]'s keys).
  static Future<EntityPickedResult?> show(
    BuildContext context,
    String entityType,
  ) {
    final config = kEntityPickerConfigs[entityType];
    if (config == null) return Future.value(null);
    return showDialog<EntityPickedResult>(
      context: context,
      builder: (_) => EntityPickerDialog(config: config),
    );
  }

  @override
  State<EntityPickerDialog> createState() => _EntityPickerDialogState();
}

class _EntityPickerDialogState extends State<EntityPickerDialog> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final term = _searchCtrl.text.trim();
      var query = OrgScope.read(SupaFlow.client.from(widget.config.table).select());
      // Mirrors SupabaseTable._select()'s soft-delete filter (table.dart)
      // — this dialog queries the raw client directly (dynamic table name,
      // can't go through the typed XTable().queryRows() helper), so it has
      // to replicate that filter itself rather than silently losing it.
      if (kSoftDeleteTables.contains(widget.config.table)) {
        query = query.isFilter('deleted_at', null);
      }
      if (term.isNotEmpty) {
        query = query.or(widget.config.searchColumns
            .map((c) => '$c.ilike.%$term%')
            .join(','));
      }
      final rows = await query.order('created_at', ascending: false).limit(20);
      _results = List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      _results = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _title(Map<String, dynamic> row) => widget.config.titleColumns
      .map((c) => row[c]?.toString() ?? '')
      .where((s) => s.isNotEmpty)
      .join(' · ');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Pick ${widget.config.label}'),
      content: SizedBox(
        width: 380,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Search',
                suffixIcon:
                    IconButton(icon: const Icon(Icons.search), onPressed: _search),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final row = _results[i];
                        final id = row['id']?.toString();
                        return ListTile(
                          title: Text(_title(row)),
                          subtitle: widget.config.subtitleColumn == null
                              ? null
                              : Text(
                                  row[widget.config.subtitleColumn]?.toString() ??
                                      ''),
                          onTap: id == null
                              ? null
                              : () => Navigator.of(context).pop(
                                    EntityPickedResult(id: id, label: _title(row)),
                                  ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
      ],
    );
  }
}
