import 'package:flutter/material.dart';

import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/record_module_page.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/index.dart';

String _human(dynamic s) => '${s ?? ''}'
    .replaceAll('_', ' ')
    .trim()
    .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());

/// The org's vehicles, for the pickers below. Empty on failure: the form
/// then says there is nothing to choose rather than breaking.
Future<List<RmMap>> _vehicles() async {
  try {
    final rows = await OrgScope.read(
            SupaFlow.client.from('vehicles').select('id, reg_no, vehicle_type'))
        .isFilter('deleted_at', null)
        .order('reg_no');
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  } catch (_) {
    return const [];
  }
}

/// Wraps a module that needs the vehicle list before it can build its
/// add form and filters.
class _WithVehicles extends StatefulWidget {
  const _WithVehicles({required this.builder});
  final Widget Function(List<RmMap> vehicles) builder;

  @override
  State<_WithVehicles> createState() => _WithVehiclesState();
}

class _WithVehiclesState extends State<_WithVehicles> {
  List<RmMap>? _v;

  @override
  void initState() {
    super.initState();
    _vehicles().then((v) {
      if (mounted) setState(() => _v = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) {
      return Scaffold(
        backgroundColor: NgPalette.of(context).bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return widget.builder(v);
  }
}

/// Fuel & FASTag (handoff Transport): fills per vehicle from `fuel_fills`.
/// There is no toll / FASTag table yet, so only the fuel log is shown.
class FuelPage extends StatelessWidget {
  const FuelPage({super.key});

  static String routeName = 'FuelPage';
  static String routePath = '/fuel';

  @override
  Widget build(BuildContext context) {
    return _WithVehicles(builder: (vehicles) {
      final reg = {for (final v in vehicles) '${v['id']}': '${v['reg_no'] ?? ''}'};
      return RecordModulePage(
        title: 'Fuel & FASTag',
        subtitle: 'Fuel spend per vehicle',
        add: RmAdd(
          title: 'Add fuel',
          table: 'fuel_fills',
          saveLabel: 'Save fuel entry',
          fields: [
            RmField('vehicle_id', 'Vehicle',
                kind: RmKind.choice,
                required: true,
                options: [for (final v in vehicles) '${v['id']}'],
                optionLabels: [for (final v in vehicles) '${v['reg_no'] ?? ''}']),
            const RmField('fill_date', 'Date', kind: RmKind.date),
            const RmField('litres', 'Litres', kind: RmKind.number),
            const RmField('amount', 'Amount ₹', kind: RmKind.number, required: true),
            const RmField('odometer_km', 'Odometer km', kind: RmKind.number),
            const RmField('station_name', 'Pump'),
            const RmField('fuel_type', 'Fuel', kind: RmKind.choice,
                options: ['diesel', 'petrol', 'cng', 'other'],
                optionLabels: ['Diesel', 'Petrol', 'CNG', 'Other']),
            const RmField('payment_mode', 'Paid by', kind: RmKind.choice,
                options: ['cash', 'upi', 'card', 'fuel_card'],
                optionLabels: ['Cash', 'UPI', 'Card', 'Fuel card']),
            const RmField('is_full_tank', 'Tank filled full (for mileage)',
                kind: RmKind.toggle),
          ],
          prepare: (v) async {
            final amount = rmNum(v['amount']);
            if (amount <= 0) throw 'Enter the amount paid.';
            final litres = v['litres'] == null ? null : rmNum(v['litres']);
            final odo = v['odometer_km'];
            return {
              ...v,
              if (odo != null) 'odometer_km': (odo as num).round(),
              if (litres != null && litres > 0)
                'rate_per_litre':
                    double.parse((amount / litres).toStringAsFixed(2)),
            };
          },
        ),
        views: [
          RmView(
            label: 'Fuel log',
            table: 'fuel_fills',
            orderBy: 'fill_date',
            stats: (rows) {
              final m = rows.where((r) => rmThisMonth(r['fill_date'])).toList();
              final l = m.fold<double>(0, (s, r) => s + rmNum(r['litres']));
              final a = m.fold<double>(0, (s, r) => s + rmNum(r['amount']));
              return [
                RmStat('Litres this month', l.toStringAsFixed(0)),
                RmStat('Fuel this month', rmMoney(a)),
                RmStat('Avg ₹ / litre', l == 0 ? '—' : (a / l).toStringAsFixed(1)),
              ];
            },
            filters: [
              const RmFilter('All', _all),
              for (final v in vehicles)
                RmFilter('${v['reg_no'] ?? ''}',
                    (r) => '${r['vehicle_id']}' == '${v['id']}'),
            ],
            row: (context, r) => RmRow(
              icon: Icons.local_gas_station_outlined,
              tone: NgStatus.accent,
              title: [
                if (r['litres'] != null) '${rmNum(r['litres']).toStringAsFixed(0)} L',
                '${r['station_name'] ?? reg['${r['vehicle_id']}'] ?? ''}',
              ].where((x) => x.isNotEmpty).join(' · '),
              subtitle: [
                rmDate(r['fill_date']),
                reg['${r['vehicle_id']}'] ?? '',
                if (r['odometer_km'] != null) '${r['odometer_km']} km',
              ].where((x) => x.isNotEmpty).join(' · '),
              amount: rmMoney(r['amount']),
              status: r['is_full_tank'] == true ? 'Full tank' : null,
              statusTone: NgStatus.blue,
            ),
            emptyText: vehicles.isEmpty
                ? 'Add a vehicle in Fleet first, then log its fuel here.'
                : 'No fuel logged yet.',
          ),
        ],
      );
    });
  }

  static bool _all(RmMap _) => true;
}

/// Docs, tyres & battery (handoff Transport): document expiries from
/// `fleet_compliance_view`, and the service / tyre / battery log.
class VehicleDocsPage extends StatelessWidget {
  const VehicleDocsPage({super.key});

  static String routeName = 'VehicleDocsPage';
  static String routePath = '/vehicle-docs';

  @override
  Widget build(BuildContext context) {
    return _WithVehicles(builder: (vehicles) {
      final reg = {for (final v in vehicles) '${v['id']}': '${v['reg_no'] ?? ''}'};
      return RecordModulePage(
        title: 'Docs, tyres & battery',
        subtitle: 'Expiries and service history',
        add: RmAdd(
          title: 'Add a service record',
          table: 'vehicle_service_logs',
          fields: [
            RmField('vehicle_id', 'Vehicle',
                kind: RmKind.choice,
                required: true,
                options: [for (final v in vehicles) '${v['id']}'],
                optionLabels: [for (final v in vehicles) '${v['reg_no'] ?? ''}']),
            const RmField('service_type', 'What was done', kind: RmKind.choice,
                required: true,
                options: ['service', 'tyres', 'battery', 'repair', 'other'],
                optionLabels: ['Service', 'Tyres', 'Battery', 'Repair', 'Other']),
            const RmField('service_date', 'Date', kind: RmKind.date),
            const RmField('odometer_km', 'Odometer km', kind: RmKind.number),
            const RmField('garage_name', 'Garage'),
            const RmField('total_cost', 'Cost ₹', kind: RmKind.number),
            const RmField('notes', 'Notes'),
          ],
          prepare: (v) async => {
            ...v,
            if (v['odometer_km'] != null)
              'odometer_km': (v['odometer_km'] as num).round(),
          },
        ),
        views: [
          RmView(
            label: 'Documents',
            table: 'fleet_compliance_view',
            orderBy: 'days_remaining',
            ascending: true,
            stats: (rows) => [
              RmStat('Expired',
                  '${rows.where((r) => rmNum(r['days_remaining']) < 0).length}'),
              RmStat('Due in 30 days', '${rows.where((r) {
                final d = rmNum(r['days_remaining']);
                return d >= 0 && d <= 30;
              }).length}'),
              RmStat('Tracked', '${rows.length}'),
            ],
            row: (context, r) {
              final d = rmNum(r['days_remaining']).round();
              return RmRow(
                icon: Icons.description_outlined,
                tone: d < 0
                    ? NgStatus.red
                    : d <= 30
                        ? NgStatus.amber
                        : NgStatus.green,
                title: '${r['reg_no'] ?? ''} · ${_human(r['doc_type'])}',
                subtitle: 'Expires ${rmDate(r['expiry_date'], 'd MMM yyyy')}',
                status: d < 0 ? 'Expired' : '$d days',
                statusTone: d < 0
                    ? NgStatus.red
                    : d <= 30
                        ? NgStatus.amber
                        : NgStatus.green,
              );
            },
            emptyText: 'No expiry dates on any vehicle yet. Add them in '
                'Fleet to be warned before they lapse.',
          ),
          RmView(
            label: 'Service log',
            table: 'vehicle_service_logs',
            orderBy: 'service_date',
            row: (context, r) => RmRow(
              icon: switch ('${r['service_type']}') {
                'tyres' => Icons.tire_repair_outlined,
                'battery' => Icons.battery_charging_full_rounded,
                _ => Icons.build_outlined,
              },
              tone: NgStatus.blue,
              title:
                  '${reg['${r['vehicle_id']}'] ?? ''} · ${_human(r['service_type'])}',
              subtitle: [
                rmDate(r['service_date']),
                if (r['garage_name'] != null) '${r['garage_name']}',
                if (r['odometer_km'] != null) '${r['odometer_km']} km',
              ].join(' · '),
              amount: r['total_cost'] == null ? null : rmMoney(r['total_cost']),
            ),
            emptyText: 'No service records yet.',
          ),
        ],
      );
    });
  }
}

/// E-way bills (handoff Transport). Read-only: generating one needs the
/// NIC e-way bill API, which is not connected.
class EwayBillsPage extends StatelessWidget {
  const EwayBillsPage({super.key});

  static String routeName = 'EwayBillsPage';
  static String routePath = '/eway-bills';

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'E-way bills',
      subtitle: 'Goods moving above the e-way limit',
      views: [
        RmView(
          label: 'Bills',
          table: 'eway_bills',
          orderBy: 'ewb_date',
          note: 'Generating an e-way bill needs the NIC portal connection, '
              'which is not set up. Bills recorded against orders show here.',
          stats: (rows) {
            final now = DateTime.now();
            return [
              RmStat('Bills', '${rows.length}'),
              RmStat('Valid', '${rows.where((r) {
                final u = rmParseDate(r['valid_until']);
                return u != null && u.isAfter(now) && r['cancelled_at'] == null;
              }).length}'),
              RmStat('Cancelled',
                  '${rows.where((r) => r['cancelled_at'] != null).length}'),
            ];
          },
          search: (r) => [r['ewb_no'], r['order_id'], r['vehicle_no'], r['to_name']]
              .whereType<Object>()
              .join(' '),
          row: (context, r) => RmRow(
            icon: Icons.receipt_long_outlined,
            tone: NgStatus.blue,
            title: '${r['ewb_no'] ?? 'Draft'} · ${r['to_place'] ?? ''}',
            subtitle: [
              if (r['order_id'] != null) '${r['order_id']}',
              if (r['vehicle_no'] != null) '${r['vehicle_no']}',
              if (r['valid_until'] != null)
                'valid to ${rmDate(r['valid_until'], 'd MMM, h:mm a')}',
            ].join(' · '),
            amount: rmMoney(r['total_invoice_value']),
            status: r['cancelled_at'] != null ? 'Cancelled' : _human(r['status']),
            statusTone:
                r['cancelled_at'] != null ? NgStatus.red : NgStatus.neutral,
          ),
          emptyText: 'No e-way bills recorded.',
        ),
      ],
    );
  }
}

/// Storage billing (handoff Assets): every storage job across orders,
/// from `storage_jobs`. Billing itself stays on each order's storage card.
class StorageBillingPage extends StatelessWidget {
  const StorageBillingPage({super.key});

  static String routeName = 'StorageBillingPage';
  static String routePath = '/storage-billing';

  static bool _inStore(RmMap r) => r['out_date'] == null;

  @override
  Widget build(BuildContext context) {
    return RecordModulePage(
      title: 'Storage billing',
      subtitle: 'Goods in your warehouses',
      views: [
        RmView(
          label: 'Jobs',
          table: 'storage_jobs',
          orderBy: 'in_date',
          query: (q) => q.isFilter('deleted_at', null),
          stats: (rows) {
            final s = rows.where(_inStore).toList();
            return [
              RmStat('In store', '${s.length}'),
              RmStat('CFT stored',
                  s.fold<double>(0, (a, r) => a + rmNum(r['total_cft'])).toStringAsFixed(0)),
              RmStat('Deposits',
                  rmMoney(s.fold<double>(0, (a, r) => a + rmNum(r['security_deposit'])))),
            ];
          },
          filters: [
            const RmFilter('In store', _inStore),
            RmFilter('Released', (r) => !_inStore(r)),
          ],
          row: (context, r) => RmRow(
            icon: Icons.inventory_2_outlined,
            tone: _inStore(r) ? NgStatus.blue : NgStatus.neutral,
            title: '${r['job_no'] ?? 'Storage'}${r['order_id'] != null ? ' · ${r['order_id']}' : ''}',
            subtitle: [
              'In ${rmDate(r['in_date'])}',
              if (r['out_date'] != null) 'out ${rmDate(r['out_date'])}'
              else if (r['expected_out_date'] != null)
                'due out ${rmDate(r['expected_out_date'])}',
              if (r['total_cft'] != null)
                '${rmNum(r['total_cft']).toStringAsFixed(0)} CFT',
            ].join(' · '),
            amount: r['rate'] == null
                ? null
                : '${rmMoney(r['rate'])}/${r['billing_mode'] == 'monthly' ? 'mo' : 'day'}',
            status: _inStore(r) ? 'In store' : 'Released',
            statusTone: _inStore(r) ? NgStatus.blue : NgStatus.neutral,
            onTap: r['order_id'] == null
                ? null
                : () => context.pushNamed(
                      OrderDetailPageWidget.routeName,
                      queryParameters: {
                        'orderId':
                            serializeParam('${r['order_id']}', ParamType.String),
                      }.withoutNulls,
                    ),
          ),
          emptyText: 'Nothing in storage. Storage is booked from an '
              "order's storage card.",
        ),
      ],
    );
  }
}
