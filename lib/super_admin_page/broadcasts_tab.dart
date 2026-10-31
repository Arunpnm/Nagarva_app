import 'dart:async';

import 'package:flutter/material.dart';

import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import 'admin_common.dart';

/// Admin › Broadcasts: a message to vendors, shown in their app until they
/// dismiss it. In-app only for now: WhatsApp to vendors needs Nagarva's
/// own WhatsApp Business number, which does not exist yet, so the option
/// is shown switched off with the reason rather than hidden.
/// Who receives it is fixed when it is sent (platform_broadcast_fanout).
class BroadcastsTab extends StatefulWidget {
  const BroadcastsTab({super.key});
  @override
  State<BroadcastsTab> createState() => _BroadcastsTabState();
}

class _BroadcastsTabState extends AdminSectionState<BroadcastsTab> {
  List<Map<String, dynamic>> _sent = const [];
  List<Map<String, dynamic>> _plans = const [];
  List<String> _cities = const [];
  Map<String, String> _admins = const {};

  String _audience = 'all';
  String? _value;
  int? _count;
  final _body = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _body.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Future<void> fetch() async {
    final r = await Future.wait([
      db.from('platform_broadcasts').select().order('created_at', ascending: false).limit(100),
      db.from('subscription_plans').select('code,name').eq('active', true),
      db.from('organizations').select('city'),
      db.from('platform_admins').select('user_id,name,email'),
    ]);
    _sent = List<Map<String, dynamic>>.from(r[0]);
    _plans = List<Map<String, dynamic>>.from(r[1]);
    _cities = {
      for (final o in r[2])
        if ('${o['city'] ?? ''}'.trim().isNotEmpty) '${o['city']}'.trim()
    }.toList()
      ..sort();
    _admins = {
      for (final a in r[3]) '${a['user_id']}': '${a['name'] ?? a['email'] ?? 'Admin'}'
    };
    await _recount();
  }

  bool get _needsValue => _audience == 'plan' || _audience == 'city';

  Future<void> _recount() async {
    if (_needsValue && _value == null) {
      _count = null;
      return;
    }
    try {
      final n = await db.rpc('platform_audience_count',
          params: {'p_audience': _audience, 'p_value': _value});
      _count = (n as num).toInt();
    } catch (_) {
      _count = null;
    }
  }

  void _pick(String audience, [String? value]) {
    setState(() {
      _audience = audience;
      _value = value;
      _count = null;
    });
    _recount().then((_) => mounted ? setState(() {}) : null);
  }

  Future<void> _send() async {
    final text = _body.text.trim();
    if (text.isEmpty) return toast('Write the message first.');
    final ok = await run(
        () => db.from('platform_broadcasts').insert({
              'channel': 'in_app',
              'audience': _audience,
              'audience_value': _needsValue ? _value : null,
              'body': text,
              'created_by': db.auth.currentUser?.id,
            }),
        'Sent to ${_count ?? ''} vendors');
    if (ok) _body.clear();
  }

  String _audienceLabel(Map<String, dynamic> b) => switch ('${b['audience']}') {
        'all' => 'All vendors',
        'plan' => 'Plan ${_plans.where((p) => p['code'] == b['audience_value']).firstOrNull?['name'] ?? b['audience_value']}',
        'city' => '${b['audience_value']}',
        'trial' => 'Trial vendors',
        _ => 'Expiring in 7 days',
      };

  @override
  Widget build(BuildContext context) => body((c) {
        final canSend = _count != null && _count! > 0 && _body.text.trim().isNotEmpty;
        return [
          const AdminHeading('Broadcasts', 'In-app messages to vendors'),
          NgCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New broadcast',
                  style: NgFonts.geist(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Send by  ', style: NgFonts.geist(fontSize: 13, color: c.mute)),
                NgChip(label: 'In-app', selected: true, onTap: () {}),
                Tooltip(
                  message: 'Needs Nagarva\'s own WhatsApp Business number, not set up yet',
                  child: Opacity(
                      opacity: 0.45,
                      child: NgChip(label: 'WhatsApp', selected: false, onTap: () {})),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('To  ', style: NgFonts.geist(fontSize: 13, color: c.mute)),
                NgChip(label: 'All vendors', selected: _audience == 'all', onTap: () => _pick('all')),
                NgChip(label: 'Trial vendors', selected: _audience == 'trial', onTap: () => _pick('trial')),
                NgChip(
                    label: 'Expiring in 7 days',
                    selected: _audience == 'expiring',
                    onTap: () => _pick('expiring')),
                for (final p in _plans)
                  NgChip(
                      label: 'Plan ${p['name']}',
                      selected: _audience == 'plan' && _value == p['code'],
                      onTap: () => _pick('plan', '${p['code']}')),
                for (final city in _cities)
                  NgChip(
                      label: city,
                      selected: _audience == 'city' && _value == city,
                      onTap: () => _pick('city', city)),
              ]),
              const SizedBox(height: 10),
              NgInput(
                controller: _body,
                hint: 'Message to vendors',
                maxLines: 4,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Text(
                      _count == null
                          ? 'Counting vendors…'
                          : '$_count vendor${_count == 1 ? '' : 's'} · shown in their app until they dismiss it. Suspended vendors are skipped.',
                      style: NgFonts.geist(fontSize: 12, color: c.mute)),
                ),
                NgPrimaryButton(
                  label: _count == null ? 'Send' : 'Send to $_count',
                  icon: Icons.campaign_rounded,
                  compact: true,
                  onPressed: canSend ? _send : null,
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          const NgSectionHeader('Sent'),
          const SizedBox(height: 8),
          if (_sent.isEmpty)
            Text('Nothing sent yet.', style: NgFonts.geist(fontSize: 13, color: c.faint))
          else
            NgCardList(children: [
              for (final b in _sent)
                NgListRow(
                  icon: Icons.notifications_none_rounded,
                  title: '${b['body']}',
                  subtitle: [
                    'In-app',
                    _audienceLabel(b),
                    '${b['recipients']} vendors',
                    'by ${_admins['${b['created_by']}'] ?? 'admin'}',
                  ].join(' · '),
                  trailing: Text(adminDate(b['created_at']),
                      style: NgFonts.mono(fontSize: 11.5, color: c.mute)),
                ),
            ]),
        ];
      });
}
