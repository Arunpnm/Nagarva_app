import 'package:flutter/material.dart';
import '/flutter_flow/ng_tokens.dart';

import '/backend/detail_navigation.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// Global search (header magnifier).
///
/// 3 Nov 2026 (Arun: "search should not be only customer data, it should
/// fetch from all, even staff"): one box now searches orders (customer,
/// phone, order no.), leads, customers, staff, vendors and vehicles, and a
/// tap opens that record (journey / detail) instead of just the list.
/// Every query goes through OrgScope + RLS, so each person only finds what
/// they are already allowed to see.
class GlobalSearchDelegate extends SearchDelegate<void> {
  GlobalSearchDelegate()
      : super(searchFieldLabel: 'Search name, phone, order no, vehicle…');

  /// SearchDelegate overrides the app bar to a light surface by default;
  /// this keeps it on the app theme (Item 9).
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
    final q = query.trim();
    if (q.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Search everything: customers, orders, leads, staff, vendors '
            'and vehicles — by name, phone, order no. or vehicle no.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return FutureBuilder<_Results>(
      future: _search(q),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
              child: Text('Could not search right now. Please try again.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final r = snapshot.data!;
        if (r.isEmpty) {
          return Center(child: Text('Nothing found for "$q"'));
        }
        final ng = NgPalette.of(context);
        void go(VoidCallback open) {
          close(context, null);
          open();
        }

        return ListView(
          children: [
            if (r.orders.isNotEmpty) ...[
              _header(ng, 'ORDERS (${r.orders.length})'),
              for (final o in r.orders)
                _tile(
                  icon: Icons.local_shipping_outlined,
                  title: o.customer,
                  subtitle:
                      '${o.id ?? ''} · ${o.phone ?? ''} · ${o.fromCity ?? '?'} → ${o.toCity ?? '?'}',
                  trailing: o.status ?? '',
                  onTap: () => go(() => openOrderJourney(context, o)),
                ),
            ],
            if (r.leads.isNotEmpty) ...[
              _header(ng, 'LEADS (${r.leads.length})'),
              for (final l in r.leads)
                _tile(
                  icon: Icons.person_search_outlined,
                  title: l.customer,
                  subtitle:
                      '${l.phone ?? ''} · ${l.fromCity ?? '?'} → ${l.toCity ?? '?'}',
                  trailing: l.status ?? '',
                  onTap: () => go(() => openLeadJourney(context, l)),
                ),
            ],
            if (r.customers.isNotEmpty) ...[
              _header(ng, 'CUSTOMERS (${r.customers.length})'),
              for (final c in r.customers)
                _tile(
                  icon: Icons.people_outline,
                  title: c.name,
                  subtitle: [c.phone, c.companyName, c.city]
                      .where((s) => (s ?? '').isNotEmpty)
                      .join(' · '),
                  onTap: () => go(() => context.pushNamed(
                        CustomerDetailPageWidget.routeName,
                        queryParameters: {
                          'customerId':
                              serializeParam(c.id, ParamType.String),
                        }.withoutNulls,
                      )),
                ),
            ],
            if (r.staff.isNotEmpty) ...[
              _header(ng, 'STAFF (${r.staff.length})'),
              for (final s in r.staff)
                _tile(
                  icon: Icons.badge_outlined,
                  title: s.name,
                  subtitle: [s.role, s.phone]
                      .where((x) => (x ?? '').isNotEmpty)
                      .join(' · '),
                  onTap: () => go(
                      () => context.pushNamed(UsersPageWidget.routeName)),
                ),
            ],
            if (r.vendors.isNotEmpty) ...[
              _header(ng, 'VENDORS (${r.vendors.length})'),
              for (final v in r.vendors)
                _tile(
                  icon: Icons.storefront_outlined,
                  title: v.name,
                  subtitle: [v.contactPerson, v.phone, v.city]
                      .where((x) => (x ?? '').isNotEmpty)
                      .join(' · '),
                  onTap: () => go(() => context.pushNamed(
                        VendorDetailPageWidget.routeName,
                        queryParameters: {
                          'vendorId': serializeParam(v.id, ParamType.String),
                        }.withoutNulls,
                      )),
                ),
            ],
            if (r.vehicles.isNotEmpty) ...[
              _header(ng, 'VEHICLES (${r.vehicles.length})'),
              for (final v in r.vehicles)
                _tile(
                  icon: Icons.directions_car_outlined,
                  title: v.regNo,
                  subtitle: v.type ?? '',
                  onTap: () => go(
                      () => context.pushNamed(FleetPageWidget.routeName)),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    String trailing = '',
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle:
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing.isEmpty ? null : Text(trailing),
        onTap: onTap,
      );

  Widget _header(NgPalette ng, String text) => Container(
        width: double.infinity,
        color: ng.w08,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: ng.mute)),
      );

  Future<_Results> _search(String raw) async {
    // Characters that would break a PostgREST `or=(...)` filter.
    final q = raw.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final byPhone = digits.length >= 4;
    String nameOr(String nameCol, {List<String> extra = const []}) => [
          '$nameCol.ilike.%$q%',
          for (final c in extra) '$c.ilike.%$q%',
          if (byPhone) 'phone.ilike.%$digits%',
        ].join(',');

    Future<List<T>> safe<T>(Future<List<T>> f) async {
      try {
        return await f;
      } catch (_) {
        return <T>[]; // one table failing must not blank the whole search
      }
    }

    final results = await Future.wait([
      safe(OrdersTable().queryRows(
        queryFn: (x) => OrgScope.read(x)
            .or(nameOr('customer', extra: ['id']))
            .order('created_at', ascending: false)
            .limit(6),
      )),
      safe(LeadsTable().queryRows(
        queryFn: (x) => OrgScope.read(x)
            .or(nameOr('customer'))
            .order('created_at', ascending: false)
            .limit(5),
      )),
      safe(CustomersTable().queryRows(
        queryFn: (x) => OrgScope.read(x)
            .or(nameOr('name', extra: ['company_name']))
            .limit(5),
      )),
      safe(StaffTable().queryRows(
        queryFn: (x) => OrgScope.read(x)
            .or(nameOr('name', extra: ['role']))
            .limit(5),
      )),
      safe(VendorsTable().queryRows(
        queryFn: (x) => OrgScope.read(x)
            .or(nameOr('name', extra: ['contact_person']))
            .limit(5),
      )),
      safe(VehiclesTable().queryRows(
        queryFn: (x) => OrgScope.read(x)
            .ilike('reg_no', '%${q.replaceAll(' ', '')}%')
            .limit(5),
      )),
    ]);
    return _Results(
      orders: results[0].cast<OrdersRow>(),
      leads: results[1].cast<LeadsRow>(),
      customers: results[2].cast<CustomersRow>(),
      staff: results[3].cast<StaffRow>(),
      vendors: results[4].cast<VendorsRow>(),
      vehicles: results[5].cast<VehiclesRow>(),
    );
  }
}

class _Results {
  _Results({
    required this.orders,
    required this.leads,
    required this.customers,
    required this.staff,
    required this.vendors,
    required this.vehicles,
  });
  final List<OrdersRow> orders;
  final List<LeadsRow> leads;
  final List<CustomersRow> customers;
  final List<StaffRow> staff;
  final List<VendorsRow> vendors;
  final List<VehiclesRow> vehicles;

  bool get isEmpty =>
      orders.isEmpty &&
      leads.isEmpty &&
      customers.isEmpty &&
      staff.isEmpty &&
      vendors.isEmpty &&
      vehicles.isEmpty;
}
