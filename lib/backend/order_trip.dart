import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// The trip an order travels on (3 Nov 2026 — one trip model).
///
/// Before this, the supervisor's odometer readings went to `vehicle_trips`
/// (one row per order) while the Trips screens, driver app and trip P&L
/// used `trips` + `trip_orders`. Arun chose `trips` as the single model;
/// `supabase/20261103_merge_vehicle_trips_into_trips.sql` copied the old
/// rows across. Everything that needs "this order's vehicle trip" goes
/// through here.
class OrderTrip {
  const OrderTrip({
    this.id,
    this.kmStart,
    this.kmEnd,
    this.vehicleNo,
    this.driverName,
  });

  final String? id;
  final double? kmStart;
  final double? kmEnd;
  final String? vehicleNo;
  final String? driverName;

  static double? _num(dynamic v) =>
      v == null ? null : double.tryParse('$v');

  /// The (latest) trip this order is on, or null.
  static Future<OrderTrip?> load(String orderId) async {
    final rows = await OrgScope.read(SupaFlow.client.from('trip_orders').select(
            'created_at,trips!inner(id,km_start,km_end,vehicle_no,driver_name,deleted_at)'))
        .eq('order_id', orderId)
        .isFilter('trips.deleted_at', null)
        .order('created_at', ascending: false)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    final t = rows.first['trips'];
    if (t is! Map) return null;
    return OrderTrip(
      id: '${t['id']}',
      kmStart: _num(t['km_start']),
      kmEnd: _num(t['km_end']),
      vehicleNo: t['vehicle_no'] as String?,
      driverName: t['driver_name'] as String?,
    );
  }

  /// Saves odometer readings on the order's trip, creating an own-vehicle trip
  /// (linked to the order) the first time. Returns the trip as stored.
  static Future<OrderTrip?> saveOdometer({
    required String orderId,
    String? existingTripId,
    double? kmStart,
    double? kmEnd,
    String? vehicleNo,
    String? driverName,
    String? fromLoc,
    String? toLoc,
  }) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final data = <String, dynamic>{
      if (kmStart != null) 'km_start': kmStart.round(),
      if (kmEnd != null) 'km_end': kmEnd.round(),
    };
    // total_km is a generated column (km_end - km_start) — never written.
    if (kmEnd != null && kmEnd > 0) {
      data['end_date'] = today;
      data['status'] = 'completed';
    }
    if (existingTripId != null) {
      await OrgScope.write(SupaFlow.client.from('trips').update(data))
          .eq('id', existingTripId);
    } else {
      final inserted = await SupaFlow.client
          .from('trips')
          .insert({
            ...OrgScope.stamp(),
            // trip_type is own | hired (Trips screen dropdown).
            'trip_type': 'own',
            // Named after the order, so the Trips list never shows
            // "(no trip no.)" for a supervisor-created trip.
            'trip_no': orderId,
            if ((fromLoc ?? '').trim().isNotEmpty) 'from_loc': fromLoc,
            if ((toLoc ?? '').trim().isNotEmpty) 'to_loc': toLoc,
            if ((vehicleNo ?? '').trim().isNotEmpty) 'vehicle_no': vehicleNo,
            if ((driverName ?? '').trim().isNotEmpty) 'driver_name': driverName,
            'start_date': today,
            'status': 'ongoing',
            ...data,
          })
          .select('id')
          .single();
      await SupaFlow.client.from('trip_orders').insert({
        ...OrgScope.stamp(),
        'trip_id': inserted['id'],
        'order_id': orderId,
      });
    }
    return load(orderId);
  }
}
