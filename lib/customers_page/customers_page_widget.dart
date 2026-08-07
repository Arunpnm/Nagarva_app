import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'customer_detail_page_widget.dart';

/// Customers (Session 4, Part C-7). Live schema confirmed directly against
/// the DB: customers + customer_addresses + customer_contacts +
/// customer_360_view. The list reads from customer_360_view so it can show
/// lifetime value / order count without an N+1 query per row; the detail
/// page reads the base `customers` row for editing.
class CustomersPageWidget extends StatefulWidget {
  const CustomersPageWidget({super.key});

  static String routeName = 'CustomersPage';
  static String routePath = '/customers';

  @override
  State<CustomersPageWidget> createState() => _CustomersPageWidgetState();
}

class _CustomersPageWidgetState extends State<CustomersPageWidget>
    with RefreshOnPopMixin<CustomersPageWidget> {
  bool _loading = true;
  List<Customer360ViewRow> _all = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _all = await Customer360ViewTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load customers: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Customer360ViewRow> get _filtered {
    if (_search.trim().isEmpty) return _all;
    final term = _search.trim().toLowerCase();
    return _all
        .where((c) =>
            (c.name ?? '').toLowerCase().contains(term) ||
            (c.phone ?? '').toLowerCase().contains(term) ||
            (c.companyName ?? '').toLowerCase().contains(term))
        .toList();
  }

  Future<void> _newCustomer() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('New Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true),
            TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: nameCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Create')),
        ],
      ),
    );
    if (created != true || nameCtrl.text.trim().isEmpty) return;
    try {
      final inserted = await CustomersTable().insert({
        ...OrgScope.stamp(),
        'name': nameCtrl.text.trim(),
        if (phoneCtrl.text.trim().isNotEmpty) 'phone': phoneCtrl.text.trim(),
      });
      await _load();
      if (mounted && inserted.id != null) {
        context.pushNamed(
          CustomerDetailPageWidget.routeName,
          queryParameters: {
            'customerId': serializeParam(inserted.id, ParamType.String),
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create customer: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text('Customers',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newCustomer,
        icon: const Icon(Icons.add),
        label: const Text('New Customer'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search Name / Phone / Company',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 10),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('No customers found.',
                          style: GoogleFonts.inter(color: theme.secondaryText)),
                    )
                  else
                    for (final c in _filtered) _customerRow(theme, c),
                ],
              ),
            ),
    );
  }

  Widget _customerRow(FlutterFlowTheme theme, Customer360ViewRow c) {
    return InkWell(
      onTap: () => context.pushNamed(
        CustomerDetailPageWidget.routeName,
        queryParameters: {
          'customerId': serializeParam(c.customerId, ParamType.String),
        },
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name ?? '—',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    [
                      if ((c.phone ?? '').isNotEmpty) c.phone,
                      if ((c.companyName ?? '').isNotEmpty) c.companyName,
                      '${c.totalOrders} orders',
                    ].whereType<String>().join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            Text('₹${c.lifetimeValue.toStringAsFixed(0)}',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
