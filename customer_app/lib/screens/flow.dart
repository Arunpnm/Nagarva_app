import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../booking.dart';
import '../config.dart';
import '../theme.dart';
import 'common.dart';

/// The booking flow from the design (Nagarva Customer.dc.html): move type,
/// cities and floors, items, date and time, package, add-ons, review.
/// Prices come only from mkt_quote() on the server.

void _go(BuildContext context, Widget page) => Navigator.of(context).push(
    MaterialPageRoute(
        builder: (_) =>
            BookingScope(booking: BookingScope.read(context), child: page)));

// ---- 1. Move type ----------------------------------------------------------

class TypeScreen extends StatelessWidget {
  const TypeScreen({super.key});

  static const _scopes = {
    'intra': ('Within city', 'Pickup and drop in the same city. Most moves finish the same day.', ['home', 'office', 'few']),
    'inter': ('Intercity', 'Moving to another city or state, delivered door to door.', ['home', 'few', 'bike']),
  };
  static const _kinds = {
    'home': (Icons.home_outlined, 'Full house', 'Household goods, any size'),
    'office': (Icons.business_outlined, 'Office shifting', 'Desks, chairs, IT and records'),
    'few': (Icons.inventory_2_outlined, 'Up to 5 items', 'Fridge, sofa, a few cartons'),
    'bike': (Icons.two_wheeler_outlined, 'Bike only', 'Scooter or motorbike, packed and shipped'),
  };

  @override
  Widget build(BuildContext context) {
    final b = BookingScope.of(context);
    final scope = _scopes[b.scope]!;
    if (!scope.$3.contains(b.kind)) b.kind = scope.$3.first;
    return FlowFrame(
      step: 0,
      title: 'What are you moving?',
      content: [
        Row(children: [
          for (final e in _scopes.entries) ...[
            Expanded(
              child: CCard(
                selected: b.scope == e.key,
                onTap: () {
                  b.scope = e.key;
                  b.changed();
                },
                child: Text(e.value.$1,
                    textAlign: TextAlign.center,
                    style: geist(14.5,
                        weight: FontWeight.w600,
                        color: b.scope == e.key ? Colors.white : C.ink)),
              ),
            ),
            if (e.key == 'intra') const SizedBox(width: 10),
          ],
        ]),
        const SizedBox(height: 8),
        Text(scope.$2, style: geist(13, color: C.secondary)),
        const SizedBox(height: 14),
        for (final k in scope.$3) ...[
          CCard(
            selected: b.kind == k,
            onTap: () {
              b.kind = k;
              b.changed();
            },
            child: Row(children: [
              Icon(_kinds[k]!.$1,
                  color: b.kind == k ? C.orange : C.blueText, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_kinds[k]!.$2,
                      style: geist(15.5,
                          weight: FontWeight.w600,
                          color: b.kind == k ? Colors.white : C.ink)),
                  Text(_kinds[k]!.$3,
                      style: geist(13,
                          color: b.kind == k ? Colors.white70 : C.secondary)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ],
      action: CButton(
          label: 'Continue', onPressed: () => _go(context, const CitiesScreen())),
    );
  }
}

// ---- 2. Cities and floors --------------------------------------------------

class CitiesScreen extends StatefulWidget {
  const CitiesScreen({super.key});
  @override
  State<CitiesScreen> createState() => _CitiesScreenState();
}

class _CitiesScreenState extends State<CitiesScreen> {
  List<String>? _cities;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.cities().then((c) {
      if (mounted) setState(() => _cities = c);
    }).catchError((_) {
      if (mounted) setState(() => _error = 'Could not load cities. Check your connection.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = BookingScope.of(context);
    final inter = b.scope == 'inter';
    final cities = _cities ?? const [];
    Widget cityField(String label, String? value, ValueChanged<String?> on) =>
        DropdownButtonFormField<String>(
          initialValue: cities.contains(value) ? value : null,
          decoration: InputDecoration(
              labelText: label,
              filled: true,
              fillColor: C.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          items: [for (final c in cities) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: on,
        );
    Widget floors(String label, int floor, bool lift, ValueChanged<int> onF,
            ValueChanged<bool> onL) =>
        CCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: geist(14, weight: FontWeight.w600)),
            Row(children: [
              Expanded(child: Text('Floor', style: geist(13.5, color: C.secondary))),
              QtyStepper(value: floor, onChanged: onF, max: 40),
            ]),
            Row(children: [
              Expanded(child: Text('Lift available', style: geist(13.5, color: C.secondary))),
              Switch(value: lift, onChanged: onL),
            ]),
          ]),
        );
    final ready = b.fromCity != null && (!inter || (b.toCity != null && b.toCity != b.fromCity));
    return FlowFrame(
      step: 1,
      title: inter ? 'From where to where?' : 'Which city?',
      content: [
        if (_error != null) Text(_error!, style: geist(13, color: C.red)),
        if (_cities == null && _error == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          cityField(inter ? 'Pickup city' : 'City', b.fromCity, (v) {
            b.fromCity = v;
            b.changed();
          }),
          if (inter) ...[
            const SizedBox(height: 10),
            cityField('Drop city', b.toCity, (v) {
              b.toCity = v;
              b.changed();
            }),
          ],
          if (b.kind != 'bike') ...[
            const SizedBox(height: 16),
            floors('Pickup', b.pickupFloor, b.pickupLift, (v) {
              b.pickupFloor = v;
              b.changed();
            }, (v) {
              b.pickupLift = v;
              b.changed();
            }),
            const SizedBox(height: 10),
            floors('Drop', b.dropFloor, b.dropLift, (v) {
              b.dropFloor = v;
              b.changed();
            }, (v) {
              b.dropLift = v;
              b.changed();
            }),
          ],
        ],
      ],
      action: CButton(
          label: 'Continue',
          onPressed: ready ? () => _go(context, const ItemsScreen()) : null),
    );
  }
}

// ---- 3. Items --------------------------------------------------------------

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});
  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  static const _catNames = {
    'bed': 'Bedroom', 'liv': 'Living', 'din': 'Dining & kitchen',
    'app': 'Appliances', 'ele': 'Electronics', 'off': 'Office',
    'veh': 'Vehicles', 'oth': 'Others',
  };
  static const _catsFor = {
    'home': ['bed', 'liv', 'din', 'app', 'ele', 'oth', 'veh'],
    'office': ['off', 'ele', 'app', 'oth'],
    'bike': ['veh'],
    'few': ['bed', 'liv', 'din', 'app', 'ele', 'oth'],
  };
  List<CatalogueItem>? _items;
  String? _cat;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.catalogue().then((i) {
      if (mounted) setState(() => _items = i);
    }).catchError((_) {
      if (mounted) setState(() => _error = 'Could not load items. Check your connection.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = BookingScope.of(context);
    final cats = _catsFor[b.kind]!;
    final cat = _cat ?? cats.first;
    final all = _items ?? const <CatalogueItem>[];
    final byKey = {for (final i in all) i.key: i};
    final shown = all.where((i) => i.cat == cat && (b.kind != 'bike' || i.key == 'bike'));
    final count = b.lines.fold<int>(0, (s, l) => s + l.qty);
    final cft = b.lines.fold<double>(
        0, (s, l) => s + l.qty * (byKey[l.key]?.variants[l.variant].cft ?? 0));
    final over = b.kind == 'few' && count > 5;
    return FlowFrame(
      step: 2,
      title: 'Add your items',
      subtitle: 'Pick each item and its size. We price by volume (CFT).',
      content: [
        if (_error != null) Text(_error!, style: geist(13, color: C.red)),
        if (_items == null && _error == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_catNames[c]!),
                    selected: c == cat,
                    onSelected: (_) => setState(() => _cat = c),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          for (final it in shown) ...[
            _itemCard(b, it),
            const SizedBox(height: 8),
          ],
        ],
      ],
      action: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
              child: Text('$count items · ${cft.round()} CFT',
                  style: geist(13.5, weight: FontWeight.w600))),
          if (over)
            Text('Up to 5 items', style: geist(12.5, color: C.red)),
        ]),
        const SizedBox(height: 8),
        CButton(
            label: 'Continue',
            onPressed: count == 0 || over
                ? null
                : () => _go(context, const DateScreen())),
      ]),
    );
  }

  Widget _itemCard(Booking b, CatalogueItem it) {
    final mine = b.lines.where((l) => l.key == it.key).toList();
    return CCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(it.name, style: geist(14.5, weight: FontWeight.w600))),
          TextButton.icon(
            onPressed: () {
              b.lines.add(Line(it.key, 0));
              b.changed();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ]),
        for (final l in mine)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: l.variant,
                    items: [
                      for (var i = 0; i < it.variants.length; i++)
                        DropdownMenuItem(
                            value: i,
                            child: Text(it.cat == 'veh'
                                ? it.variants[i].name
                                : '${it.variants[i].name} · ${it.variants[i].cft.round()} CFT')),
                    ],
                    onChanged: (v) {
                      l.variant = v ?? 0;
                      b.changed();
                    },
                  ),
                ),
                QtyStepper(
                  value: l.qty,
                  onChanged: (v) {
                    if (v == 0) {
                      b.lines.remove(l);
                    } else {
                      l.qty = v;
                    }
                    b.changed();
                  },
                ),
              ]),
              Wrap(spacing: 6, children: [
                for (final s in it.services)
                  FilterChip(
                    label: Text(s.label),
                    selected: l.services.contains(s.code),
                    onSelected: (on) {
                      on ? l.services.add(s.code) : l.services.remove(s.code);
                      b.changed();
                    },
                  ),
              ]),
            ]),
          ),
      ]),
    );
  }
}

// ---- 4. Date and time ------------------------------------------------------

class DateScreen extends StatelessWidget {
  const DateScreen({super.key});

  static const _slots = [
    ('Early', '6–8 am'), ('Morning', '8–10 am'), ('Late morning', '10–12'),
    ('Noon', '12–2 pm'), ('Afternoon', '2–4 pm'), ('Evening', '4–6 pm'),
  ];

  @override
  Widget build(BuildContext context) {
    final b = BookingScope.of(context);
    final now = DateTime.now();
    final days = [for (var i = 1; i <= 21; i++) DateTime(now.year, now.month, now.day + i)];
    return FlowFrame(
      step: 3,
      title: 'When should we come?',
      content: [
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final d = days[i];
              final on = b.date != null && DateUtils.isSameDay(b.date, d);
              return SizedBox(
                width: 62,
                child: CCard(
                  selected: on,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onTap: () {
                    b.date = d;
                    b.changed();
                  },
                  child: Column(children: [
                    Text(DateFormat('EEE').format(d),
                        style: geist(12, color: on ? Colors.white70 : C.secondary)),
                    Text('${d.day}',
                        style: geist(18,
                            weight: FontWeight.w600,
                            color: on ? Colors.white : C.ink)),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        Text('Pickup time', style: geist(14, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (name, time) in _slots)
            ChoiceChip(
              label: Text('$name · $time'),
              selected: b.slot == time,
              onSelected: (_) {
                b.slot = time;
                b.changed();
              },
            ),
        ]),
      ],
      action: CButton(
          label: 'Continue',
          onPressed: b.date != null && b.slot != null
              ? () => _go(context, const PackageScreen())
              : null),
    );
  }
}

// ---- 5. Package ------------------------------------------------------------

class PackageScreen extends StatelessWidget {
  const PackageScreen({super.key});

  static const _pkgs = [
    ('economy', 'Economy', 'Shared truck, basic packing', ['Single-layer packing', 'Shared vehicle, may take 1–2 days longer', 'Loading and unloading']),
    ('standard', 'Standard', 'Most booked', ['Multi-layer packing with bubble wrap', 'Dedicated vehicle', 'Dismantle & assembly included']),
    ('premium', 'Premium', 'Gold-rated movers only', ['Everything in Standard', 'Waterproof wrap and wooden crating for TV / glass', 'Unpacking & arranging included', 'Crew supervisor on site']),
  ];

  @override
  Widget build(BuildContext context) {
    final b = BookingScope.of(context);
    return FlowFrame(
      step: 4,
      title: 'Choose a package',
      subtitle: 'You see the full price on the review screen.',
      content: [
        for (final (k, name, tag, inc) in _pkgs) ...[
          CCard(
            selected: b.package == k,
            onTap: () {
              b.package = k;
              b.changed();
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: geist(17,
                      weight: FontWeight.w600,
                      color: b.package == k ? Colors.white : C.ink)),
              Text(tag,
                  style: geist(13,
                      color: b.package == k ? C.orange : C.secondary)),
              const SizedBox(height: 8),
              for (final x in inc)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_rounded,
                        size: 16, color: b.package == k ? C.orange : C.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(x,
                          style: geist(13,
                              color: b.package == k ? Colors.white : C.ink)),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ],
      action: CButton(
          label: 'Continue', onPressed: () => _go(context, const AddonsScreen())),
    );
  }
}

// ---- 6. Add-ons ------------------------------------------------------------

class AddonsScreen extends StatefulWidget {
  const AddonsScreen({super.key});
  @override
  State<AddonsScreen> createState() => _AddonsScreenState();
}

class _AddonsScreenState extends State<AddonsScreen> {
  Map<String, dynamic>? _prices;

  @override
  void initState() {
    super.initState();
    final city = BookingScope.read(context).fromCity;
    Api.cityPrices(city ?? '').then((p) {
      if (mounted) setState(() => _prices = p ?? {});
    }).catchError((_) {
      if (mounted) setState(() => _prices = {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = BookingScope.of(context);
    final p = _prices ?? const {};
    String price(String k, {String suffix = ''}) =>
        p[k] == null ? 'Not offered yet' : '${money(p[k] as num)}$suffix';
    Widget addon(IconData icon, String title, String sub, String priceText,
            bool on, ValueChanged<bool>? onChanged) =>
        CCard(
          child: Row(children: [
            Icon(icon, color: C.blueText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: geist(14.5, weight: FontWeight.w600)),
                Text(sub, style: geist(12.5, color: C.secondary)),
                const SizedBox(height: 2),
                Text(priceText, style: mono(13, color: C.blueText)),
              ]),
            ),
            Switch(value: on, onChanged: onChanged),
          ]),
        );
    final premium = b.package == 'premium';
    return FlowFrame(
      step: 5,
      title: 'Anything else?',
      content: [
        addon(Icons.verified_user_outlined, 'Damage cover',
            'Cover for transit damage', price('damage_cover'), b.cover,
            p['damage_cover'] == null ? null : (v) {
              b.cover = v;
              b.changed();
            }),
        const SizedBox(height: 10),
        addon(Icons.inventory_2_outlined, 'Unpacking & arranging',
            'Crew unpacks and places items',
            premium ? 'Included in Premium' : price('unpacking'),
            premium || b.unpack,
            premium || p['unpacking'] == null ? null : (v) {
              b.unpack = v;
              b.changed();
            }),
        const SizedBox(height: 10),
        CCard(
          child: Row(children: [
            const Icon(Icons.warehouse_outlined, color: C.blueText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Storage', style: geist(14.5, weight: FontWeight.w600)),
                Text('Secure warehouse, months', style: geist(12.5, color: C.secondary)),
                Text(price('storage_month', suffix: ' per month'),
                    style: mono(13, color: C.blueText)),
              ]),
            ),
            QtyStepper(
              value: b.storageMonths,
              max: p['storage_month'] == null ? 0 : 12,
              onChanged: (v) {
                b.storageMonths = v;
                b.changed();
              },
            ),
          ]),
        ),
      ],
      action: CButton(
          label: 'Review price',
          onPressed: () => _go(context, const ReviewScreen())),
    );
  }
}

// ---- 7. Review -------------------------------------------------------------

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  Map<String, dynamic>? _q;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.quote(BookingScope.read(context).quoteInput()).then((q) {
      if (mounted) setState(() => _q = q);
    }).catchError((_) {
      if (mounted) setState(() => _error = 'Could not get a price. Check your connection.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = BookingScope.of(context);
    final q = _q;
    Widget row(String k, num? v, {bool bold = false}) => (v == null || v == 0) && !bold
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                  child: Text(k,
                      style: geist(13.5,
                          color: bold ? Colors.white : Colors.white70,
                          weight: bold ? FontWeight.w600 : FontWeight.w400))),
              Text(money(v ?? 0),
                  style: mono(bold ? 18 : 13.5, color: Colors.white)),
            ]),
          );
    final ok = q != null && q['ok'] == true;
    return FlowFrame(
      step: 5,
      title: 'Review and pay',
      subtitle: [
        b.scope == 'inter' ? '${b.fromCity} → ${b.toCity}' : b.fromCity,
        if (b.date != null) DateFormat('EEE d MMM').format(b.date!),
        b.slot,
        '${b.package[0].toUpperCase()}${b.package.substring(1)}',
      ].whereType<String>().join(' · '),
      content: [
        if (_error != null) Text(_error!, style: geist(13.5, color: C.red)),
        if (q == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (q != null && !ok)
          CCard(child: Text(quoteProblem(q), style: geist(14, color: C.red))),
        if (ok)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: C.blue, borderRadius: BorderRadius.circular(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${(q['cft'] as num).round()} CFT · ${q['km']} km',
                  style: geist(12.5, color: Colors.white70)),
              const SizedBox(height: 8),
              row('Moving', q['move'] as num?),
              row('Floors without lift', q['floors'] as num?),
              row('Vehicles', q['vehicles'] as num?),
              row('Item services', q['services'] as num?),
              row('Add-ons', q['addons'] as num?),
              row('GST 18%', q['gst'] as num?),
              const Divider(color: Colors.white24),
              row('Total', q['total'] as num?, bold: true),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Text('Pay now to Nagarva',
                            style: geist(13.5, color: C.orange, weight: FontWeight.w600))),
                    Text(money(q['advance'] as num), style: mono(15, color: C.orange)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                        child: Text('Pay mover after delivery',
                            style: geist(13.5, color: Colors.white70))),
                    Text(money((q['total'] as num) - (q['advance'] as num)),
                        style: mono(15, color: Colors.white)),
                  ]),
                ]),
              ),
            ]),
          ),
        if (ok) ...[
          const SizedBox(height: 14),
          Text(
              'Cancellation: full refund more than 72 hours before the move, half the advance between 72 and 24 hours, none within 24 hours.',
              style: geist(12.5, height: 1.4, color: C.secondary)),
        ],
      ],
      action: CButton(
        label: kBookingLive ? 'Pay ${ok ? money(q['advance'] as num) : ''}' : 'Online payment opens soon',
        onPressed: null,
      ),
    );
  }
}
