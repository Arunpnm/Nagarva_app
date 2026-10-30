import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One item the customer picked: catalogue key, size variant, quantity and
/// any services (dismantle, uninstall...).
class Line {
  Line(this.key, this.variant, {this.qty = 1, Set<String>? services})
      : services = services ?? {};
  final String key;
  int variant;
  int qty;
  final Set<String> services;

  Map<String, dynamic> toJson() => {
        'key': key,
        'variant': variant,
        'qty': qty,
        'services': services.toList(),
      };
}

class CatalogueItem {
  CatalogueItem(Map<String, dynamic> r)
      : key = r['key'] as String,
        cat = r['cat'] as String,
        name = r['name'] as String,
        variants = [
          for (final v in r['variants'] as List)
            (name: '${v['name']}', cft: (v['cft'] as num).toDouble())
        ],
        services = [
          for (final s in r['services'] as List)
            (code: '${s['code']}', label: '${s['label']}')
        ];
  final String key;
  final String cat;
  final String name;
  final List<({String name, double cft})> variants;
  final List<({String code, String label})> services;
}

/// The move being priced. The price itself always comes from the server
/// (mkt_quote), never from this class: the app shows what Nagarva's own
/// rates say, and a later booking re-runs the same function.
class Booking extends ChangeNotifier {
  String scope = 'intra'; // intra | inter
  String kind = 'home'; // home | office | few | bike
  String? fromCity;
  String? toCity;
  final List<Line> lines = [];
  int pickupFloor = 0;
  bool pickupLift = false;
  int dropFloor = 0;
  bool dropLift = false;
  DateTime? date;
  String? slot;
  String package = 'standard';
  bool cover = false;
  bool unpack = false;
  int storageMonths = 0;

  void changed() => notifyListeners();

  Map<String, dynamic> quoteInput({String? pkg}) => {
        'from_city': fromCity,
        'to_city': scope == 'intra' ? fromCity : toCity,
        'package': pkg ?? package,
        'lines': [for (final l in lines) l.toJson()],
        'pickup_floor': pickupFloor,
        'pickup_lift': pickupLift,
        'drop_floor': dropFloor,
        'drop_lift': dropLift,
        'addons': {
          'cover': cover,
          'unpack': unpack,
          'storage_months': storageMonths,
        },
      };
}

/// Reads what the public app may read and asks for prices. The calls are
/// fields so tests can stand in for the network.
class Api {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<List<String>> Function() cities = _cities;
  static Future<List<CatalogueItem>> Function() catalogue = _catalogue;
  static Future<Map<String, dynamic>> Function(Map<String, dynamic>) quote =
      _quote;
  static Future<Map<String, dynamic>?> Function(String city) cityPrices =
      _cityPrices;

  static Future<Map<String, dynamic>?> _cityPrices(String city) =>
      _db.from('mkt_city_prices').select().eq('city', city).maybeSingle();

  static Future<List<String>> _cities() async {
    final rows =
        await _db.from('mkt_cities').select('city').eq('active', true).order('city');
    return [for (final r in rows) '${r['city']}'];
  }

  static Future<List<CatalogueItem>> _catalogue() async {
    final rows =
        await _db.from('mkt_catalogue').select().eq('active', true).order('sort');
    return [for (final r in rows) CatalogueItem(r)];
  }

  /// The server's quote: {ok:true, total, ...} or {ok:false, reason, detail}.
  static Future<Map<String, dynamic>> _quote(Map<String, dynamic> input) async {
    final r = await _db.rpc('mkt_quote', params: {'p': input});
    return Map<String, dynamic>.from(r as Map);
  }
}

/// A refusal from mkt_quote in words a customer can act on.
String quoteProblem(Map<String, dynamic> q) => switch (q['reason']) {
      'no_price' =>
        'We are not taking bookings for this yet (${q['detail']}). Please check back soon.',
      'city_not_served' => 'We do not serve this city yet.',
      'no_items' => 'Add at least one item.',
      _ => 'Something in this move cannot be priced (${q['detail'] ?? q['reason']}).',
    };
