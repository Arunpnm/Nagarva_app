import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// Global customer search (parity brief follow-up — restoring a gap from
/// the reference app: the header "Mobile / Name..." search that finds a
/// customer across orders and leads by name or phone). Ported from
/// reference/APC Web App JSX/App.jsx's globalSearch (~line 14383) using
/// Flutter's built-in SearchDelegate rather than the reference app's
/// absolutely-positioned dropdown, which doesn't translate directly.
///
/// Matches the reference app's own navigation behaviour: tapping a result
/// goes to that list page (Orders/Leads), not the specific record's detail
/// page — this mirrors globalSearch's own `navTo("orders")` / `navTo(
/// "leads")` rather than adding a deeper link the reference app doesn't
/// have either.
class GlobalSearchDelegate extends SearchDelegate<void> {
  GlobalSearchDelegate() : super(searchFieldLabel: 'Mobile / Name...');

  /// Item 9 (theme not applied to the search bar).
  ///
  /// SearchDelegate does NOT simply inherit the ambient theme: its default
  /// `appBarTheme` deliberately overrides the app bar to a white/grey
  /// surface with `InputBorder.none` so the search field looks "plain",
  /// which is why the search bar stayed light while the rest of the app
  /// went dark. Overriding it is the only way to make the search surface
  /// follow the theme — restyling the widgets inside it can't reach the
  /// app bar SearchDelegate builds itself.
  @override
  ThemeData appBarTheme(BuildContext context) {
    final ff = FlutterFlowTheme.of(context);
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: ff.primaryBackground,
        foregroundColor: ff.primaryText,
        iconTheme: IconThemeData(color: ff.primaryText),
        elevation: 0,
      ),
      scaffoldBackgroundColor: ff.primaryBackground,
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: ff.secondaryText),
        border: InputBorder.none,
      ),
      textTheme: base.textTheme.copyWith(
        // The query text itself, which otherwise renders near-black.
        titleLarge: base.textTheme.titleLarge?.copyWith(color: ff.primaryText),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ff.primary,
        selectionColor: ff.primary.withValues(alpha: 0.3),
        selectionHandleColor: ff.primary,
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Search orders and leads by customer name or phone.'),
        ),
      );
    }
    return FutureBuilder<({List<OrdersRow> orders, List<LeadsRow> leads})>(
      future: _search(query.trim()),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snapshot.data!.orders;
        final leads = snapshot.data!.leads;
        if (orders.isEmpty && leads.isEmpty) {
          return Center(child: Text('No customer found for "$query"'));
        }
        final theme = FlutterFlowTheme.of(context);
        return ListView(
          children: [
            if (orders.isNotEmpty) ...[
              _sectionHeader(theme, 'ORDERS (${orders.length})'),
              for (final o in orders)
                ListTile(
                  title: Text(o.customer),
                  subtitle: Text(
                      '${o.phone ?? ''} · ${o.fromCity ?? '?'} → ${o.toCity ?? '?'} · ${o.status ?? ''}'),
                  trailing: Text('₹${(o.amount ?? 0).toStringAsFixed(0)}'),
                  onTap: () {
                    close(context, null);
                    context.pushNamed(OrdersPageWidget.routeName);
                  },
                ),
            ],
            if (leads.isNotEmpty) ...[
              _sectionHeader(theme, 'LEADS (${leads.length})'),
              for (final l in leads)
                ListTile(
                  title: Text(l.customer),
                  subtitle: Text(
                      '${l.phone ?? ''} · ${l.fromCity ?? '?'} → ${l.toCity ?? '?'}'),
                  trailing: Text(l.status ?? ''),
                  onTap: () {
                    close(context, null);
                    context.pushNamed(LeadsPageWidget.routeName);
                  },
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(FlutterFlowTheme theme, String text) => Container(
        width: double.infinity,
        color: theme.alternate,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: theme.secondaryText)),
      );

  Future<({List<OrdersRow> orders, List<LeadsRow> leads})> _search(
      String q) async {
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final results = await Future.wait([
      OrdersTable().queryRows(
        queryFn: (query) => OrgScope.read(query)
            .or(digits.length >= 4
                ? 'customer.ilike.%$q%,phone.ilike.%$digits%'
                : 'customer.ilike.%$q%')
            .limit(6),
      ),
      LeadsTable().queryRows(
        queryFn: (query) => OrgScope.read(query)
            .or(digits.length >= 4
                ? 'customer.ilike.%$q%,phone.ilike.%$digits%'
                : 'customer.ilike.%$q%')
            .limit(4),
      ),
    ]);
    return (
      orders: results[0].cast<OrdersRow>(),
      leads: results[1].cast<LeadsRow>(),
    );
  }
}
