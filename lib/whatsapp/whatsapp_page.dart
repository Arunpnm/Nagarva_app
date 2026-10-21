import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/backend/whatsapp_cloud.dart';
import '/components/ng_widgets.dart';
import '/config/app_config.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/nav_items.dart';

/// Account › WhatsApp (handoff `wa`): connect the vendor's OWN WhatsApp
/// Business number through Meta's Cloud API, get Nagarva's message
/// templates approved on it, and send a test.
///
/// The vendor brings three things from Meta: the phone number ID, the
/// WhatsApp Business Account ID and a permanent access token. The token
/// goes straight to the `whatsapp` Edge Function and into Vault; this
/// screen never shows it again. Owner/admin/manager only — the function
/// refuses everyone else.
class WhatsAppPage extends StatefulWidget {
  const WhatsAppPage({super.key});

  static String routeName = 'WhatsAppPage';
  static String routePath = '/whatsapp';

  @override
  State<WhatsAppPage> createState() => _WhatsAppPageState();
}

class _WhatsAppPageState extends State<WhatsAppPage> {
  WaStatus? _s;
  Map<String, Map<String, dynamic>> _lib = {};
  String? _error;
  bool _busy = false;

  final _phoneId = TextEditingController();
  final _wabaId = TextEditingController();
  final _token = TextEditingController();
  final _appSecret = TextEditingController();
  final _testTo = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (kWhatsAppCloudLive) _load();
  }

  @override
  void dispose() {
    for (final c in [_phoneId, _wabaId, _token, _appSecret, _testTo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await WhatsAppCloud.status();
      final lib = await SupaFlow.client
          .from('wa_template_library')
          .select('key, label, body, params, sort_order')
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        _s = s;
        _lib = {for (final r in lib) '${r['key']}': Map<String, dynamic>.from(r)};
        final a = s.account;
        if (a != null) {
          _phoneId.text = '${a['phone_number_id'] ?? ''}';
          _wabaId.text = '${a['waba_id'] ?? ''}';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _flash(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    setState(() => _busy = true);
    try {
      await job();
      if (done != null && mounted) _flash(done);
    } catch (e) {
      if (mounted) _flash('$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _connect() => _run(() async {
        final s = await WhatsAppCloud.connect(
          phoneNumberId: _phoneId.text,
          wabaId: _wabaId.text,
          token: _token.text,
          appSecret: _appSecret.text,
        );
        _token.clear();
        _appSecret.clear();
        if (mounted) setState(() => _s = s);
        await _load();
      }, done: 'WhatsApp connected.');

  Future<void> _submit() => _run(() async {
        final refused = await WhatsAppCloud.submitTemplates();
        await _load();
        if (refused.isNotEmpty && mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Meta did not accept some messages'),
              content: Text(refused.entries
                  .map((e) => '${_label(e.key)}: ${e.value}')
                  .join('\n\n')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK')),
              ],
            ),
          );
        }
      }, done: 'Sent to Meta for approval. This usually takes minutes, sometimes a day.');

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect WhatsApp?'),
        content: const Text(
            'Messages stop going out from your number, and every automatic '
            'message is switched off. Your templates stay approved at Meta, '
            'so connecting again later picks them back up.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await WhatsAppCloud.disconnect();
      await _load();
    }, done: 'WhatsApp disconnected.');
  }

  String _label(String key) => '${_lib[key]?['label'] ?? key}';

  /// The template body with each {{n}} shown as what fills it, e.g.
  /// "Hi [customer name], …" — a vendor should not have to read {{1}}.
  String _preview(String key) {
    final body = '${_lib[key]?['body'] ?? ''}';
    final params = (_lib[key]?['params'] as List?) ?? const [];
    return body.replaceAllMapped(RegExp(r'\{\{(\d+)\}\}'), (m) {
      final i = int.parse(m[1]!) - 1;
      return i >= 0 && i < params.length
          ? '[${'${params[i]}'.replaceAll('_', ' ')}]'
          : m[0]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgSimpleBar(title: 'WhatsApp'),
      body: SafeArea(
        top: false,
        child: !kWhatsAppCloudLive
            ? _notLive(c)
            : _error != null
                ? _errorView(c)
                : _s == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          children: _s!.connected
                              ? _connectedView(c, _s!)
                              : _connectForm(c, _s!),
                        ),
                      ),
      ),
    );
  }

  Widget _notLive(NgPalette c) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NgCard(
            child: Text(
              'Sending from your own WhatsApp number needs a server update '
              'that has not been switched on yet. Until then, WhatsApp '
              'buttons open WhatsApp on this phone with the message ready.',
              style: NgFonts.geist(fontSize: 13.5, height: 1.45, color: c.mute),
            ),
          ),
        ],
      );

  Widget _errorView(NgPalette c) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NgCard(
              child: Text(_error!,
                  style: NgFonts.geist(fontSize: 13.5, color: c.red))),
          const SizedBox(height: 12),
          NgSecondaryButton(label: 'Try again', onPressed: _load),
        ],
      );

  // ------------------------------------------------------------ not connected

  List<Widget> _connectForm(NgPalette c, WaStatus s) {
    final mgr = isOwnerOrManagerSession;
    Widget field(String label, TextEditingController ctl,
            {String? hint, bool secret = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NgFieldLabel(label),
              NgInput(
                controller: ctl,
                hint: hint,
                mono: !secret,
                obscure: secret,
                keyboardType: secret ? TextInputType.visiblePassword : TextInputType.number,
              ),
            ],
          ),
        );
    return [
      NgCard(
        child: Row(children: [
          const NgIconTile(icon: Icons.chat_rounded, status: NgStatus.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Send order updates, receipts and reminders from your own '
              'WhatsApp Business number. Meta bills your account directly '
              'for each conversation.',
              style: NgFonts.geist(fontSize: 13, height: 1.4, color: c.mute),
            ),
          ),
        ]),
      ),
      if (!s.planAllows) ...[
        const SizedBox(height: 10),
        NgCard(
          color: c.amberBg,
          child: Text(
              'Your current plan does not include WhatsApp. You can connect '
              'now; messages start going out once the plan includes it.',
              style: NgFonts.geist(fontSize: 13, height: 1.4, color: c.text)),
        ),
      ],
      const SizedBox(height: 18),
      if (!mgr)
        Text('Only the owner or a manager can connect WhatsApp.',
            style: NgFonts.geist(fontSize: 13.5, color: c.mute))
      else ...[
        Text('From Meta (developers.facebook.com › your app › WhatsApp › API setup):',
            style: NgFonts.geist(fontSize: 12.5, height: 1.4, color: c.mute)),
        const SizedBox(height: 12),
        field('Phone number ID', _phoneId, hint: '1234567890'),
        field('WhatsApp Business Account ID', _wabaId, hint: '1234567890'),
        field('Permanent access token', _token,
            hint: 'From a System User in Business Settings', secret: true),
        field('App secret (for replies in Inbox, optional)', _appSecret,
            hint: 'App settings › Basic › App secret', secret: true),
        NgPrimaryButton(
          label: _busy ? 'Checking with Meta…' : 'Connect',
          icon: Icons.link_rounded,
          onPressed: _busy ? null : _connect,
        ),
        const SizedBox(height: 10),
        Text(
            'Use a permanent token: the 24-hour test token stops working '
            'tomorrow. We check the three IDs with Meta before saving, and '
            'the token is stored encrypted on the server — it never comes '
            'back to this phone.',
            style: NgFonts.geist(fontSize: 12, height: 1.45, color: c.faint)),
      ],
    ];
  }

  // ------------------------------------------------------------ connected

  List<Widget> _connectedView(NgPalette c, WaStatus s) {
    final mgr = isOwnerOrManagerSession;
    final tpls = [...s.templates]..sort((a, b) =>
        ((_lib[a.key]?['sort_order'] as num?) ?? 0)
            .compareTo((_lib[b.key]?['sort_order'] as num?) ?? 0));
    final toSubmit =
        tpls.where((t) => t.status == 'draft' || t.status == 'rejected').length;
    final limit = s.monthlyLimit;
    return [
      NgCard(
        child: Row(children: [
          const NgIconTile(icon: Icons.chat_rounded, status: NgStatus.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.verifiedName.isEmpty ? s.displayPhone : s.verifiedName,
                    style: NgFonts.geist(
                        fontSize: 15.5, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 2),
                Text(
                    [s.displayPhone, 'Connected · Meta Cloud API']
                        .where((x) => x.isNotEmpty)
                        .join(' · '),
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
              ],
            ),
          ),
          const NgPill('Live', status: NgStatus.green),
        ]),
      ),
      const SizedBox(height: 10),
      NgCard(
        child: Row(children: [
          Expanded(
            child: Text('Sent this month',
                style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
          ),
          Text(
              limit == null || limit < 0
                  ? '${s.sentThisMonth}'
                  : '${s.sentThisMonth} of $limit',
              style: NgFonts.mono(fontSize: 14, color: c.text)),
        ]),
      ),
      if (!s.planAllows) ...[
        const SizedBox(height: 10),
        NgCard(
          color: c.amberBg,
          child: Text(
              'Your current plan does not include WhatsApp, so nothing is '
              'being sent. Upgrade the plan to start.',
              style: NgFonts.geist(fontSize: 13, height: 1.4, color: c.text)),
        ),
      ],
      const SizedBox(height: 18),
      NgFieldLabel('Messages',
          action: mgr ? 'Refresh' : null,
          onAction: mgr
              ? () => _run(() async {
                    await WhatsAppCloud.syncTemplates();
                    await _load();
                  })
              : null),
      NgCardList(children: [
        for (final t in tpls)
          NgListRow(
            icon: Icons.chat_bubble_outline_rounded,
            iconStatus: t.approved ? NgStatus.green : NgStatus.neutral,
            title: _label(t.key),
            subtitle: t.status == 'rejected' && (t.rejectedReason ?? '').isNotEmpty
                ? 'Meta: ${t.rejectedReason}'
                : _preview(t.key),
            trailing: NgPill(_statusLabel(t.status), status: _statusTone(t.status)),
          ),
      ]),
      const SizedBox(height: 8),
      Text(
          'These are the standard messages, the same for every business; '
          'your business name is filled in when each one is sent. Meta '
          'reviews each message once before it can be used.',
          style: NgFonts.geist(fontSize: 12, height: 1.45, color: c.faint)),
      if (mgr && toSubmit > 0) ...[
        const SizedBox(height: 12),
        NgPrimaryButton(
          label: 'Send $toSubmit for approval',
          icon: Icons.verified_outlined,
          onPressed: _busy ? null : _submit,
        ),
      ],
      if (mgr) ...[
        const SizedBox(height: 22),
        const NgFieldLabel('Send a test message'),
        Row(children: [
          Expanded(
            child: NgInput(
              controller: _testTo,
              hint: 'Your mobile number',
              keyboardType: TextInputType.phone,
              mono: true,
            ),
          ),
          const SizedBox(width: 8),
          NgSecondaryButton(
            label: 'Send',
            icon: Icons.send_rounded,
            height: 52,
            onPressed: _busy
                ? null
                : () => _run(() => WhatsAppCloud.test(_testTo.text),
                    done: 'Test sent. It arrives as Meta\'s "hello world" message.'),
          ),
        ]),
        const SizedBox(height: 22),
        _inboxCard(c, s),
        const SizedBox(height: 22),
        NgSecondaryButton(
          label: 'Disconnect',
          icon: Icons.link_off_rounded,
          iconColor: c.red,
          onPressed: _busy ? null : _disconnect,
        ),
      ],
    ];
  }

  Widget _inboxCard(NgPalette c, WaStatus s) {
    Widget copyRow(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: NgFonts.geist(fontSize: 12, color: c.mute)),
                  const SizedBox(height: 2),
                  SelectableText(value,
                      style: NgFonts.mono(fontSize: 12.5, color: c.text)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.copy_rounded, size: 18, color: c.mute),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                _flash('$label copied');
              },
            ),
          ]),
        );
    return NgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Replies in Inbox',
                  style: NgFonts.geist(
                      fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text)),
            ),
            NgPill(s.inboxReady ? 'On' : 'Not set up',
                status: s.inboxReady ? NgStatus.green : NgStatus.amber),
          ]),
          const SizedBox(height: 6),
          Text(
              'In your Meta app, open WhatsApp › Configuration › Webhook, '
              'paste these two values, and subscribe to "messages". '
              'Delivery ticks and customer replies then show in Inbox.',
              style: NgFonts.geist(fontSize: 12.5, height: 1.45, color: c.mute)),
          copyRow('Callback URL', s.webhookUrl),
          copyRow('Verify token', s.verifyToken),
          if (!s.inboxReady) ...[
            const SizedBox(height: 12),
            NgInput(
              controller: _appSecret,
              hint: 'App secret (App settings › Basic)',
              obscure: true,
            ),
            const SizedBox(height: 8),
            NgSecondaryButton(
              label: 'Save app secret',
              onPressed: _busy ? null : _connect,
            ),
            const SizedBox(height: 6),
            Text(
                'Needed so only Meta can post into your Inbox: every '
                'incoming message is checked against it.',
                style: NgFonts.geist(fontSize: 12, height: 1.4, color: c.faint)),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'approved' => 'Approved',
        'pending' => 'In review',
        'rejected' => 'Rejected',
        'paused' => 'Paused',
        'disabled' => 'Disabled',
        _ => 'Not sent',
      };

  static NgStatus _statusTone(String s) => switch (s) {
        'approved' => NgStatus.green,
        'pending' => NgStatus.blue,
        'rejected' || 'disabled' => NgStatus.red,
        'paused' => NgStatus.amber,
        _ => NgStatus.neutral,
      };
}

/// Setup › Auto WhatsApp (handoff `plat:wa`): which events send a message
/// by themselves. Only the AUTOMATIC templates appear here — the survey
/// link and the balance reminder go out when someone taps Send, so a
/// switch for them would change nothing.
class AutoWhatsAppPage extends StatefulWidget {
  const AutoWhatsAppPage({super.key});

  static String routeName = 'AutoWhatsAppPage';
  static String routePath = '/auto-whatsapp';

  @override
  State<AutoWhatsAppPage> createState() => _AutoWhatsAppPageState();
}

class _AutoWhatsAppPageState extends State<AutoWhatsAppPage> {
  WaStatus? _s;
  Map<String, Map<String, dynamic>> _lib = {};
  Map<String, int> _sent = {};
  String? _error;

  static const _when = {
    'enquiry_received': 'When a new lead is saved',
    'order_confirmed': 'When an order is booked',
    'move_started': 'When the crew starts the move',
    'delivered': 'When the move is completed with the customer\'s code',
    'payment_received': 'When a payment is recorded',
  };

  @override
  void initState() {
    super.initState();
    if (kWhatsAppCloudLive) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await WhatsAppCloud.status();
      final lib = await SupaFlow.client
          .from('wa_template_library')
          .select('key, label, body');
      final now = DateTime.now();
      final rows = await OrgScope.read(SupaFlow.client
              .from('wa_messages')
              .select('template_key, status'))
              .eq('direction', 'out')
              .neq('status', 'failed')
              .gte('created_at',
                  DateTime(now.year, now.month).toUtc().toIso8601String());
      final sent = <String, int>{};
      for (final r in rows) {
        final k = '${r['template_key'] ?? ''}';
        if (k.isNotEmpty) sent[k] = (sent[k] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _s = s;
        _lib = {for (final r in lib) '${r['key']}': Map<String, dynamic>.from(r)};
        _sent = sent;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _toggle(WaTemplate t, bool on) async {
    try {
      await OrgScope.write(
              SupaFlow.client.from('wa_templates').update({'enabled': on}))
          .eq('id', t.raw['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not change it: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final s = _s;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgSimpleBar(title: 'Auto WhatsApp'),
      body: SafeArea(
        top: false,
        child: !kWhatsAppCloudLive
            ? ListView(padding: const EdgeInsets.all(16), children: [
                NgCard(
                  child: Text(
                      'Automatic messages need your own WhatsApp number to be '
                      'connected, and that server update is not switched on yet.',
                      style: NgFonts.geist(fontSize: 13.5, height: 1.45, color: c.mute)),
                ),
              ])
            : _error != null
                ? ListView(padding: const EdgeInsets.all(16), children: [
                    NgCard(
                        child: Text(_error!,
                            style: NgFonts.geist(fontSize: 13.5, color: c.red))),
                  ])
                : s == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          children: _body(c, s),
                        ),
                      ),
      ),
    );
  }

  List<Widget> _body(NgPalette c, WaStatus s) {
    final mgr = isOwnerOrManagerSession;
    final byKey = {for (final t in s.templates) t.key: t};
    final autos = [for (final k in kWaAutoKeys) if (byKey[k] != null) byKey[k]!];
    final on = autos.where((t) => t.enabled && t.approved).length;
    if (!s.connected) {
      return [
        NgCard(
          child: Text(
              'Connect your WhatsApp Business number first. Automatic '
              'messages go out from your own number.',
              style: NgFonts.geist(fontSize: 13.5, height: 1.45, color: c.mute)),
        ),
        const SizedBox(height: 12),
        if (mgr)
          NgPrimaryButton(
            label: 'Connect WhatsApp',
            icon: Icons.link_rounded,
            onPressed: () => context
                .pushNamed(WhatsAppPage.routeName)
                .then((_) => _load()),
          ),
      ];
    }
    return [
      Row(children: [
        Expanded(child: NgStatTile(icon: Icons.send_rounded, label: 'Sent this month', value: '${s.sentThisMonth}')),
        const SizedBox(width: 8),
        Expanded(child: NgStatTile(icon: Icons.toggle_on_outlined, label: 'Switched on', value: '$on / ${autos.length}')),
      ]),
      const SizedBox(height: 16),
      NgCardList(children: [
        for (final t in autos)
          NgListRow(
            icon: Icons.chat_rounded,
            iconStatus: t.enabled && t.approved ? NgStatus.green : NgStatus.neutral,
            title: '${_lib[t.key]?['label'] ?? t.key}',
            subtitle: t.approved
                ? '${_when[t.key] ?? ''} · ${_sent[t.key] ?? 0} this month'
                : 'Waiting for Meta to approve this message',
            trailing: Switch(
              value: t.enabled && t.approved,
              onChanged: mgr && t.approved ? (v) => _toggle(t, v) : null,
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Text(
          'The survey link and balance reminders are sent when you tap '
          'Send on WhatsApp, so they have no switch here.',
          style: NgFonts.geist(fontSize: 12, height: 1.45, color: c.faint)),
    ];
  }
}
