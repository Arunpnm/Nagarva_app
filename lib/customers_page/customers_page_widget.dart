import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/l10n/gen/app_localizations.dart';
import '/flutter_flow/ng_tokens.dart';
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
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  NgModuleHeader(
                    l.ngMenuCustomers,
                    subtitle: l.ngCustCount(_all.length),
                    actions: [
                      NgPrimaryButton(
                        compact: true,
                        height: 40,
                        icon: Icons.add_rounded,
                        label: l.ngCustNew,
                        onPressed: _newCustomer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  NgSearchField(
                    controller: _searchCtrl,
                    hint: l.ngCustSearch,
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 14),
                  if (_filtered.isEmpty)
                    NgCard(
                      child: Text(l.ngCustNone,
                          textAlign: TextAlign.center,
                          style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                    )
                  else
                    NgCardList(children: [
                      for (final cu in _filtered) _customerRow(cu),
                    ]),
                ],
              ),
            ),
    );
  }

  Widget _customerRow(Customer360ViewRow cu) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final due = cu.outstandingEstimate;
    return NgListRow(
      onTap: () => context.pushNamed(
        CustomerDetailPageWidget.routeName,
        queryParameters: {
          'customerId': serializeParam(cu.customerId, ParamType.String),
        },
      ),
      leading: NgAvatar(cu.name ?? '?'),
      title: cu.name ?? '—',
      subtitle: [
        if ((cu.phone ?? '').isNotEmpty) cu.phone!,
        if ((cu.companyName ?? '').isNotEmpty) cu.companyName!,
        l.ngOrdersN(cu.totalOrders),
      ].join(' · '),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(functions.inrFull(cu.lifetimeValue),
              style: NgFonts.geist(
                  fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text)),
          if (due > 0)
            Text(l.ngCustDue(functions.inrFull(due)),
                style: NgFonts.geist(
                    fontSize: 12, fontWeight: FontWeight.w500, color: c.red)),
        ],
      ),
    );
  }
}
