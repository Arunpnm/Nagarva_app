import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '/app_session.dart';
import '/backend/edge_function_errors.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/backend/tracking_service.dart';
import '/config/app_config.dart';

/// The vendor's own WhatsApp number, through Meta's Cloud API, via the
/// `whatsapp` Edge Function. The app never sees the access token.
///
/// Template keys are the rows of `wa_template_library`. Two kinds:
///  * AUTOMATIC ([kWaAutoKeys]) — sent by [WhatsAppCloud.auto] when the
///    event happens, if the owner switched that message on in Auto
///    WhatsApp. Nobody presses anything.
///  * ON DEMAND — sent when someone taps "Send on WhatsApp" (survey link,
///    balance reminder). Available as soon as Meta approves the template;
///    there is no switch, because a switch that only gates a button the
///    user is already pressing would be a decoy.
const kWaAutoKeys = [
  'enquiry_received',
  'order_confirmed',
  'move_started',
  'delivered',
  'payment_received',
];

class WaTemplate {
  WaTemplate(this.raw);
  final Map<String, dynamic> raw;
  String get key => '${raw['key']}';
  String get name => '${raw['name']}';
  String get status => '${raw['status'] ?? 'draft'}';
  bool get enabled => raw['enabled'] == true;
  bool get approved => status == 'approved';
  String? get rejectedReason => raw['rejected_reason'] as String?;
}

class WaStatus {
  WaStatus(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic>? get account =>
      raw['account'] == null ? null : Map<String, dynamic>.from(raw['account']);
  bool get connected => account?['status'] == 'connected';
  String get displayPhone => '${account?['display_phone'] ?? ''}';
  String get verifiedName => '${account?['verified_name'] ?? ''}';
  String get webhookUrl => '${account?['webhook_url'] ?? ''}';
  String get verifyToken => '${account?['webhook_verify_token'] ?? ''}';
  bool get inboxReady => account?['inbox_ready'] == true;
  String? get lastError => account?['last_error'] as String?;
  int get sentThisMonth => (raw['sent_this_month'] as num?)?.toInt() ?? 0;

  /// -1 means unlimited; null means the plan row has no such limit.
  int? get monthlyLimit => (raw['monthly_limit'] as num?)?.toInt();
  bool get planAllows => raw['plan_allows'] == true;
  List<WaTemplate> get templates => [
        for (final t in (raw['templates'] as List? ?? const []))
          WaTemplate(Map<String, dynamic>.from(t as Map)),
      ];
}

class WhatsAppCloud {
  static Future<Map<String, dynamic>> _call(
      String action, Map<String, dynamic> params) async {
    final org = AppSession.instance.currentOrgId;
    if (org == null) throw 'Choose a business first.';
    try {
      final res = await SupaFlow.client.functions.invoke('whatsapp',
          body: {'action': action, 'org_id': org, ...params});
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      throw extractFunctionErrorMessage(e,
          fallback: 'WhatsApp did not respond. Please try again.');
    }
  }

  static Future<WaStatus> status() async => WaStatus(await _call('status', {}));

  static Future<WaStatus> connect({
    required String phoneNumberId,
    required String wabaId,
    String? token,
    String? appSecret,
  }) async {
    await _call('connect', {
      'phone_number_id': phoneNumberId.trim(),
      'waba_id': wabaId.trim(),
      if ((token ?? '').trim().isNotEmpty) 'token': token!.trim(),
      if ((appSecret ?? '').trim().isNotEmpty) 'app_secret': appSecret!.trim(),
    });
    return status();
  }

  static Future<void> disconnect() => _call('disconnect', {});

  /// Submits every draft or rejected template to Meta. Returns the keys
  /// Meta refused, with its reason.
  static Future<Map<String, String>> submitTemplates() async {
    final r = await _call('submit_templates', {});
    return {
      for (final x in (r['results'] as List? ?? const []))
        if ((x as Map)['ok'] != true) '${x['key']}': '${x['error'] ?? ''}',
    };
  }

  static Future<void> syncTemplates() => _call('sync_templates', {});

  static Future<void> test(String to) => _call('test', {'to': to});

  static Future<void> send(
    String key, {
    required String to,
    required Map<String, String> params,
    String? entityType,
    String? entityId,
  }) =>
      _call('send', {
        'key': key,
        'to': to,
        'params': params,
        if (entityType != null) 'entity_type': entityType,
        if (entityId != null) 'entity_id': entityId,
      });

  /// Whether [key] can go out through the vendor's number right now.
  /// [requireEnabled] adds the Auto WhatsApp switch, for automatic sends.
  /// Reads `wa_templates` directly (RLS: any member of the org).
  static Future<bool> ready(String key, {bool requireEnabled = false}) async {
    if (!kWhatsAppCloudLive) return false;
    final org = AppSession.instance.currentOrgId;
    if (org == null) return false;
    try {
      final row = await OrgScope.read(
              SupaFlow.client.from('wa_templates').select('status, enabled'))
          .eq('key', key)
          .maybeSingle();
      if (row == null || row['status'] != 'approved') return false;
      return !requireEnabled || row['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Fire-and-forget automatic message for an event that just happened.
  /// Never throws and never blocks the screen: the event itself (an order
  /// saved, a payment recorded) has already succeeded, and a WhatsApp
  /// problem must not read as if it had not. Failures are kept in
  /// `wa_messages` by the Edge Function, with Meta's reason.
  static void auto(
    String key, {
    required String? to,
    required Map<String, String?> params,
    String? entityType,
    String? entityId,
  }) {
    if (!kWhatsAppCloudLive || (to ?? '').trim().isEmpty) return;
    () async {
      try {
        if (!await ready(key, requireEnabled: true)) return;
        await send(key,
            to: to!,
            params: {
              for (final e in params.entries)
                if ((e.value ?? '').trim().isNotEmpty) e.key: e.value!.trim(),
            },
            entityType: entityType,
            entityId: entityId);
      } catch (e) {
        debugPrint('WhatsApp auto $key: $e');
      }
    }();
  }

  // -------------------------------------------------- event shortcuts
  // One line at each event site. Amounts are always the record's own;
  // nothing is rounded up, guessed or defaulted.

  static String date(DateTime? d) =>
      d == null ? '' : DateFormat('d MMM yyyy').format(d);

  /// Indian grouping without a currency sign (the template says "Rs").
  static String money(num? v) => v == null
      ? ''
      : NumberFormat.decimalPattern('en_IN').format(v % 1 == 0 ? v.round() : v);

  static void leadCreated(LeadsRow? l) {
    if (l == null) return;
    auto('enquiry_received',
        to: l.phone,
        params: {'customer_name': l.customer},
        entityType: 'lead',
        entityId: l.id);
  }

  static void orderBooked(OrdersRow? o) {
    if (o == null) return;
    auto('order_confirmed',
        to: o.phone,
        params: {
          'customer_name': o.customer,
          'move_date': date(o.moveDateOrNull),
          'order_no': o.id,
        },
        entityType: 'order',
        entityId: o.id);
  }

  static void paymentReceived({
    required String? orderId,
    required String? customer,
    required String? phone,
    required num amount,
  }) =>
      auto('payment_received',
          to: phone,
          params: {
            'customer_name': customer,
            'amount': money(amount),
            'order_no': orderId,
          },
          entityType: 'order',
          entityId: orderId);

  /// The crew has started. Carries the live tracking link — and only when
  /// `/track` is actually served, never a dead link.
  static void moveStarted(OrdersRow? o) {
    if (o == null || o.id == null || !kWhatsAppCloudLive) return;
    () async {
      String? link;
      if (kTrackLinkHosted) {
        try {
          final t = await TrackingService.tokenForOrder(o.id!);
          if (t != null) link = buildTokenLink('/track', t);
        } catch (_) {}
      }
      // No link, no message: the template needs one, and a send with a
      // blank variable would only be refused by Meta.
      if (link == null) return;
      auto('move_started',
          to: o.phone,
          params: {'customer_name': o.customer, 'order_no': o.id, 'track_link': link},
          entityType: 'order',
          entityId: o.id);
    }();
  }

  static void delivered(OrdersRow? o) {
    if (o == null) return;
    auto('delivered',
        to: o.phone,
        params: {'customer_name': o.customer, 'order_no': o.id},
        entityType: 'order',
        entityId: o.id);
  }

  /// On-demand balance reminder from the vendor's own number. Returns
  /// false when that is not possible yet (not connected, not approved),
  /// so the caller can fall back to opening WhatsApp on the phone; throws
  /// with Meta's reason when a send was attempted and refused.
  static Future<bool> remindBalance({
    required String? orderId,
    required String? customer,
    required String? phone,
    required num balance,
  }) async {
    if ((phone ?? '').trim().isEmpty || !await ready('balance_reminder')) {
      return false;
    }
    await send('balance_reminder',
        to: phone!,
        params: {
          'customer_name': customer ?? '',
          'amount': money(balance),
          'order_no': orderId ?? '',
        },
        entityType: 'order',
        entityId: orderId);
    return true;
  }
}

/// What [ShareLinkSheet] needs to offer "Send from your WhatsApp number"
/// next to the open-WhatsApp-on-this-phone button.
class WaCloudSend {
  const WaCloudSend(this.key,
      {required this.params, this.entityType, this.entityId});
  final String key;
  final Map<String, String> params;
  final String? entityType;
  final String? entityId;
}
