import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

/// Messages from Nagarva (Admin › Broadcasts) that this org has not
/// dismissed yet, newest first, on the Dashboard. Dismissing writes
/// read_at for the org, so it stays dismissed on every device.
///
/// Renders nothing while loading, when there is nothing unread, or before
/// the admin panel migration has run.
class NagarvaBroadcastBanner extends StatefulWidget {
  const NagarvaBroadcastBanner({super.key});
  @override
  State<NagarvaBroadcastBanner> createState() => _NagarvaBroadcastBannerState();
}

class _NagarvaBroadcastBannerState extends State<NagarvaBroadcastBanner> {
  List<Map<String, dynamic>> _unread = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final org = AppSession.instance.currentOrgId;
    if (org == null) return;
    try {
      final rows = await SupaFlow.client
          .from('platform_broadcast_recipients')
          .select('broadcast_id, platform_broadcasts(body, created_at)')
          .eq('org_id', org)
          .isFilter('read_at', null);
      final list = [
        for (final r in rows)
          if (r['platform_broadcasts'] is Map)
            {
              'id': r['broadcast_id'],
              ...Map<String, dynamic>.from(r['platform_broadcasts'] as Map),
            }
      ]..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
      if (mounted) setState(() => _unread = list);
    } catch (_) {
      // Table not there yet, or offline: show nothing.
    }
  }

  Future<void> _dismiss(String id) async {
    setState(() => _unread = _unread.where((b) => b['id'] != id).toList());
    try {
      await SupaFlow.client
          .from('platform_broadcast_recipients')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('broadcast_id', id)
          .eq('org_id', AppSession.instance.currentOrgId!);
    } catch (_) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unread.isEmpty) return const SizedBox.shrink();
    final c = NgPalette.of(context);
    return Column(children: [
      for (final b in _unread.take(3))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: NgCard(
            color: c.blueBg,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.campaign_outlined, color: c.blue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('From Nagarva',
                      style: NgFonts.geist(fontSize: 12, fontWeight: FontWeight.w600, color: c.blue)),
                  const SizedBox(height: 2),
                  Text('${b['body']}',
                      style: NgFonts.geist(fontSize: 13.5, color: c.text, height: 1.4)),
                ]),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: c.mute),
                onPressed: () => _dismiss('${b['id']}'),
              ),
            ]),
          ),
        ),
    ]);
  }
}
