import 'package:flutter/material.dart';

import '/app_session.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import 'admin_common.dart';

/// Admin › Support tickets: what vendors raised from Help & support.
/// Open = waiting on Nagarva, Waiting = waiting on the vendor. A reply
/// moves the ticket by itself (support_reply_moves_ticket); an admin
/// resolves it, sets priority and picks it up here.
class TicketsTab extends StatefulWidget {
  const TicketsTab({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  State<TicketsTab> createState() => _TicketsTabState();
}

class _TicketsTabState extends AdminSectionState<TicketsTab> {
  List<Map<String, dynamic>> _tickets = const [];
  Map<String, String> _orgs = const {};
  Map<String, String> _admins = const {};
  String _filter = 'open';

  @override
  Future<void> fetch() async {
    final r = await Future.wait([
      db.from('support_tickets').select().order('updated_at', ascending: false).limit(500),
      db.from('organizations').select('id,name'),
      db.from('platform_admins').select('user_id,name,email'),
    ]);
    _tickets = List<Map<String, dynamic>>.from(r[0]);
    _orgs = {for (final o in r[1]) '${o['id']}': '${o['name']}'};
    _admins = {
      for (final a in r[2]) '${a['user_id']}': '${a['name'] ?? a['email'] ?? 'Admin'}'
    };
  }

  bool _match(Map<String, dynamic> t, String f) => switch (f) {
        'mine' => t['assigned_to'] == db.auth.currentUser?.id &&
            t['status'] != 'resolved',
        _ => t['status'] == f,
      };

  @override
  Widget build(BuildContext context) => body((c) {
        final shown = _tickets.where((t) => _match(t, _filter)).toList()
          ..sort((a, b) {
            final p = (b['priority'] == 'high' ? 1 : 0) - (a['priority'] == 'high' ? 1 : 0);
            return p != 0 ? p : '${b['updated_at']}'.compareTo('${a['updated_at']}');
          });
        return [
          const AdminHeading('Support tickets', 'From the Help button in the vendor app'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, l) in const [
              ('open', 'Open'),
              ('mine', 'Mine'),
              ('waiting', 'Waiting'),
              ('resolved', 'Resolved'),
            ])
              NgChip(
                label: l,
                count: _tickets.where((t) => _match(t, k)).length,
                selected: _filter == k,
                onTap: () => setState(() => _filter = k),
              ),
          ]),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            NgEmptyState(
              icon: Icons.support_agent_rounded,
              title: _filter == 'open' ? 'No open tickets' : 'Nothing here',
              subtitle: _filter == 'open'
                  ? 'Tickets vendors raise from Help & support appear here.'
                  : null,
            )
          else
            NgCardList(children: [
              for (final t in shown)
                NgListRow(
                  leading: Icon(Icons.circle,
                      size: 10,
                      color: t['priority'] == 'high' ? c.red : c.amber),
                  title: '${t['subject']}',
                  subtitle: [
                    _orgs['${t['org_id']}'] ?? 'Vendor',
                    adminAgo(t['created_at']),
                    t['assigned_to'] == null
                        ? 'Not picked up'
                        : _admins['${t['assigned_to']}'] ?? 'Admin',
                  ].join(' · '),
                  trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('T-${t['ticket_no']}',
                            style: NgFonts.mono(fontSize: 11.5, color: c.mute)),
                        Text(_statusLabel('${t['status']}'),
                            style: NgFonts.geist(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: switch ('${t['status']}') {
                                  'open' => c.amber,
                                  'waiting' => c.blue,
                                  _ => c.green,
                                })),
                      ]),
                  onTap: () => _open(t),
                ),
            ]),
        ];
      });

  static String _statusLabel(String s) => switch (s) {
        'open' => 'Open',
        'waiting' => 'Waiting',
        _ => 'Resolved',
      };

  Future<void> _open(Map<String, dynamic> t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TicketThreadPage(
          ticket: t, orgName: _orgs['${t['org_id']}'] ?? 'Vendor', asAdmin: true),
    ));
    await load();
    widget.onChanged?.call();
  }
}

/// One ticket and its replies. Shared by the admin panel and the vendor's
/// Help & support (asAdmin false): the same thread, from either side.
class TicketThreadPage extends StatefulWidget {
  const TicketThreadPage(
      {super.key, required this.ticket, required this.orgName, required this.asAdmin});
  final Map<String, dynamic> ticket;
  final String orgName;
  final bool asAdmin;
  @override
  State<TicketThreadPage> createState() => _TicketThreadPageState();
}

class _TicketThreadPageState extends AdminSectionState<TicketThreadPage> {
  late Map<String, dynamic> _t = widget.ticket;
  List<Map<String, dynamic>> _replies = const [];
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  @override
  Future<void> fetch() async {
    final r = await Future.wait([
      db.from('support_tickets').select().eq('id', _t['id']).single(),
      db
          .from('support_ticket_replies')
          .select()
          .eq('ticket_id', _t['id'])
          .order('created_at'),
    ]);
    _t = Map<String, dynamic>.from(r[0] as Map);
    _replies = List<Map<String, dynamic>>.from(r[1] as List);
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final s = AppSession.instance;
    final ok = await run(
        () => db.from('support_ticket_replies').insert({
              'ticket_id': _t['id'],
              'author_name': widget.asAdmin ? 'Nagarva support' : s.currentStaffName,
              'from_admin': widget.asAdmin,
              'body': text,
            }),
        'Reply sent');
    if (ok) _reply.clear();
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _set(Map<String, dynamic> patch, String done) => run(
      () => db.from('support_tickets').update({
            ...patch,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', _t['id']),
      done);

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final me = db.auth.currentUser?.id;
    final resolved = _t['status'] == 'resolved';
    Widget bubble(String who, String text, dynamic at, bool mine) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: mine ? c.sel : c.s1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.w08),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$who · ${adminAgo(at)}',
                  style: NgFonts.geist(fontSize: 11.5, color: c.mute)),
              const SizedBox(height: 4),
              Text(text, style: NgFonts.geist(fontSize: 14, color: c.text, height: 1.4)),
            ]),
          ),
        );
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgSimpleBar(title: 'T-${_t['ticket_no']} · ${widget.orgName}'),
      body: Column(children: [
        Expanded(
          child: body((c) => [
                Text('${_t['subject']}',
                    style: NgFonts.geist(
                        fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 4),
                Text(
                    [
                      switch ('${_t['status']}') {
                        'open' => widget.asAdmin ? 'Waiting on Nagarva' : 'With Nagarva support',
                        'waiting' => widget.asAdmin ? 'Waiting on the vendor' : 'Waiting for your reply',
                        _ => 'Resolved',
                      },
                      if (_t['priority'] == 'high') 'High priority',
                      'raised ${adminDate(_t['created_at'], time: true)}',
                    ].join(' · '),
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                if (widget.asAdmin) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_t['assigned_to'] != me)
                      OutlinedButton(
                          onPressed: () => _set({'assigned_to': me}, 'Picked up'),
                          child: const Text('Pick up')),
                    OutlinedButton(
                        onPressed: () => _set(
                            {'priority': _t['priority'] == 'high' ? 'normal' : 'high'},
                            'Priority changed'),
                        child: Text(_t['priority'] == 'high'
                            ? 'Mark normal priority'
                            : 'Mark high priority')),
                    OutlinedButton(
                        onPressed: () => _set(
                            {'status': resolved ? 'open' : 'resolved'},
                            resolved ? 'Reopened' : 'Resolved'),
                        child: Text(resolved ? 'Reopen' : 'Resolve')),
                  ]),
                ],
                const SizedBox(height: 16),
                bubble('${_t['raised_by_name'] ?? widget.orgName}', '${_t['body']}',
                    _t['created_at'], !widget.asAdmin),
                for (final r in _replies)
                  bubble(
                      r['from_admin'] == true
                          ? 'Nagarva support'
                          : '${r['author_name'] ?? widget.orgName}',
                      '${r['body']}',
                      r['created_at'],
                      (r['from_admin'] == true) == widget.asAdmin),
              ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
                color: c.s1, border: Border(top: BorderSide(color: c.w08))),
            child: Row(children: [
              Expanded(
                child: NgInput(
                    controller: _reply,
                    hint: resolved && !widget.asAdmin
                        ? 'Write to reopen this ticket'
                        : 'Write a reply',
                    maxLines: 3),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
