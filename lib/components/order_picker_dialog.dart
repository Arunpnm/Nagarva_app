import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Shared searchable order picker (Session 4, Part C-8) — search by order
/// id / customer name / phone, org-scoped, most recent 20. Returns the
/// picked [OrdersRow] (not just an id) so the caller can also read
/// customerId/customer/phone off it without a second query.
class OrderPickerDialog extends StatefulWidget {
  const OrderPickerDialog({super.key});

  static Future<OrdersRow?> show(BuildContext context) => showDialog<OrdersRow>(
        context: context,
        builder: (_) => const OrderPickerDialog(),
      );

  @override
  State<OrderPickerDialog> createState() => _OrderPickerDialogState();
}

class _OrderPickerDialogState extends State<OrderPickerDialog> {
  final _searchCtrl = TextEditingController();
  List<OrdersRow> _results = [];
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
      _results = await OrdersTable().queryRows(
        queryFn: (q) {
          var query = OrgScope.read(q);
          if (term.isNotEmpty) query = query.or('id.ilike.%$term%,customer.ilike.%$term%,phone.ilike.%$term%');
          return query.order('created_at', ascending: false).limit(20);
        },
      );
    } catch (_) {
      _results = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick Order'),
      content: SizedBox(
        width: 380,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Search by order id / customer / phone',
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
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
                        final o = _results[i];
                        return ListTile(
                          title: Text('${o.id} · ${o.customer}'),
                          subtitle: Text(o.phone ?? ''),
                          onTap: () => Navigator.of(context).pop(o),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}
