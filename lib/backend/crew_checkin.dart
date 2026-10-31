import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';

/// Crew check-in (supabase/20261031_crew_checkin.sql). Every write is a
/// server function that checks who is calling; this file only carries the
/// calls and turns refusals into sentences.
///
/// * The supervisor's phone shows [code] as a QR; it changes every 30 s.
/// * A crew member scans it: [scan].
/// * The supervisor checks in with GPS and a selfie: [supervisorCheckIn].
/// * The supervisor marks someone without a phone: [markPresent].
/// * The owner reviews the last two: [review].
abstract final class CrewCheckin {
  static SupabaseClient get _db => SupaFlow.client;

  /// {payload, seconds_left}.
  static Future<({String payload, int secondsLeft})> code(String orderId) async {
    final r = Map<String, dynamic>.from(
        await _db.rpc('checkin_code', params: {'p_order': orderId}) as Map);
    return (
      payload: '${r['payload']}',
      secondsLeft: (r['seconds_left'] as num? ?? 30).toInt(),
    );
  }

  /// Returns the sentence to show the crew member.
  static Future<({bool ok, String message})> scan(String payload) async {
    final r = Map<String, dynamic>.from(
        await _db.rpc('crew_check_in', params: {'p_payload': payload}) as Map);
    if (r['ok'] == true) {
      final who = r['customer'] == null ? '${r['order']}' : '${r['customer']} · ${r['order']}';
      return (
        ok: true,
        message: r['already'] == true
            ? 'You are already checked in for $who.'
            : r['late'] == true
                ? 'Checked in for $who, after the start time.'
                : 'Checked in for $who.',
      );
    }
    return (
      ok: false,
      message: switch (r['reason']) {
        'expired' => 'That code has changed. Scan the supervisor\'s screen again.',
        'not_on_crew' => 'You are not on the crew for ${r['order']}. Ask your supervisor to add you.',
        'not_staff' => 'This phone is not signed in as a staff member of this company.',
        _ => 'That is not a Nagarva check-in code.',
      },
    );
  }

  /// Reads the position, takes a front-camera selfie, uploads it and
  /// checks in. Returns null when the supervisor cancels the selfie.
  static Future<String?> supervisorCheckIn(String orderId) async {
    final pos = await _position();
    final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 900,
        imageQuality: 70);
    if (photo == null) return null;
    final org = AppSession.instance.currentOrgId!;
    final staff = AppSession.instance.currentStaffId ?? 'staff';
    final path = '$org/checkins/$orderId/$staff-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage.from('job-photos').uploadBinary(path, await photo.readAsBytes(),
        fileOptions: const FileOptions(contentType: 'image/jpeg'));
    final r = Map<String, dynamic>.from(await _db.rpc('supervisor_check_in', params: {
      'p_order': orderId,
      'p_lat': pos.latitude,
      'p_lng': pos.longitude,
      'p_accuracy': pos.accuracy,
      'p_selfie_path': path,
    }) as Map);
    final d = r['distance_m'] as num?;
    return d == null
        ? 'Checked in. The site has no map location yet, so the owner will see where you were, not the distance.'
        : 'Checked in, ${d.round()} m from the site.';
  }

  static Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CheckinProblem('Turn on location, then try again.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      throw const CheckinProblem(
          'Nagarva needs your location to check you in. Allow it in your phone\'s settings.');
    }
    return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
  }

  static Future<void> markPresent(String orderId, String staffId, String reason) =>
      _db.rpc('mark_crew_present',
          params: {'p_order': orderId, 'p_staff': staffId, 'p_reason': reason});

  static Future<void> review(String id, String status) =>
      _db.rpc('review_checkin', params: {'p_id': id, 'p_status': status});

  /// A short-lived link to a check-in selfie (private bucket).
  static Future<String> selfieUrl(String path) =>
      _db.storage.from('job-photos').createSignedUrl(path, 600);
}

class CheckinProblem implements Exception {
  const CheckinProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A refusal from a check-in call in words: the functions raise plain
/// sentences (P0001).
String checkinError(Object e) => switch (e) {
      CheckinProblem p => p.message,
      PostgrestException p when p.code == 'P0001' => p.message,
      PostgrestException p when p.code == 'PGRST202' || p.code == '42883' =>
        'Check-in is not set up yet. Ask the owner to finish the update.',
      _ => 'Could not check in. Check your connection and try again.',
    };
