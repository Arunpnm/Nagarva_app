import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/config/app_config.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// WA Inbox (Session 4, Part B3) — was a ComingSoonPage stub.
///
/// `wa_contacts`/`wa_messages` (migration 001) have no ingestion pipeline
/// anywhere in this app — no webhook receiver / Edge Function exists that
/// writes an inbound message when a customer replies on WhatsApp (CLAUDE.md's
/// Phase 4 rule is that AiSensy is only ever called from an Edge Function,
/// and none has been built yet for either direction). This screen is
/// therefore the read/manage side of a pipe that isn't connected yet: it
/// renders whatever rows exist, and "sending" here does the same thing
/// every other WhatsApp action in this app already does — opens the
/// device's own WhatsApp via a wa.me deep link — plus records an outbound
/// `wa_messages` row for the thread history. It does not call any Business
/// API.
///
/// "Auto-create lead on first inbound" (the brief's own wording) is
/// consequently something no CLIENT code can trigger — there's no app-side
/// moment where an inbound message "arrives". The correct place for that
/// logic is a database trigger on `wa_messages` INSERT, symmetrical with
/// this app's other derived-state triggers (`apply_stock_movement()` on
/// stock_movements). Written and handed over as migration 012 — inert
/// until a real ingestion pipeline starts inserting inbound rows, but
/// ready the moment one does.
class WaInboxPageWidget extends StatefulWidget {
  const WaInboxPageWidget({super.key});

  static String routeName = 'WaInboxPage';
  static String routePath = '/inbox';

  @override
  State<WaInboxPageWidget> createState() => _WaInboxPageWidgetState();
}

class _WaInboxPageWidgetState extends State<WaInboxPageWidget>
    with RefreshOnPopMixin<WaInboxPageWidget> {
  bool _loading = true;
  List<WaContactsRow> _contacts = [];
  WaContactsRow? _selected;
  List<WaMessagesRow> _thread = [];
  bool _threadLoading = false;
  final _composeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onPageRefresh() => _load();

  @override
  void dispose() {
    _composeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _contacts = await WaContactsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('last_message_at', ascending: false),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load inbox: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openThread(WaContactsRow contact) async {
    setState(() {
      _selected = contact;
      _threadLoading = true;
      _thread = [];
    });
    try {
      _thread = await WaMessagesTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eq('contact_id', contact.id!)
            .order('sent_at', ascending: true),
      );
      // Opening a conversation clears its unread count — same convention
      // as any messaging inbox.
      if ((contact.unreadCount) > 0) {
        await WaContactsTable().update(
          data: {'unread_count': 0},
          matchingRows: (q) => OrgScope.write(q).eq('id', contact.id!),
        );
        contact.unreadCount = 0;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load thread: $e')));
      }
    } finally {
      if (mounted) setState(() => _threadLoading = false);
    }
  }

  Future<void> _send({String? templateName, required String body}) async {
    final contact = _selected;
    if (contact == null || body.trim().isEmpty) return;
    try {
      final orgId = OrgScope.currentOrgId;
      final inserted = await WaMessagesTable().insert({
        'org_id': orgId,
        'contact_id': contact.id,
        'direction': 'out',
        'msg_type': 'text',
        'body': body.trim(),
        if (templateName != null) 'template_name': templateName,
        'status': 'sent',
        'sent_at': DateTime.now().toIso8601String(),
      });
      await WaContactsTable().update(
        data: {
          'last_message_at': DateTime.now().toIso8601String(),
          'last_message_text': body.trim(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', contact.id!),
      );
      setState(() {
        _thread = [..._thread, inserted];
        _composeCtrl.clear();
      });
      final uri = Uri.parse(buildWhatsAppLink(phone: contact.phone, message: body.trim()));
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not send: $e')));
    }
  }

  Future<void> _toggleMute(WaContactsRow contact) async {
    final next = !contact.muted;
    try {
      await WaContactsTable().update(
        data: {'muted': next},
        matchingRows: (q) => OrgScope.write(q).eq('id', contact.id!),
      );
      setState(() => contact.muted = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  static const _templates = <String, String>{
    'Follow up': 'Hi, just checking in on your upcoming move — happy to '
        'answer any questions.',
    'Payment reminder': 'Hi, this is a gentle reminder about your pending '
        'balance. Let us know if you have any questions.',
    'Thank you': 'Thank you for choosing us for your move! Please reach out '
        'any time if you need help.',
  };

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    final wide = MediaQuery.of(context).size.width > 760;

    final list = _contactList(ng);
    // NG-FIX follow-up (7 Aug 2026): _threadView() reads `_selected!` on
    // its very first line, so it must never be called while `_selected`
    // is null — which it always is until a contact is tapped. This used
    // to be called unconditionally here, crashing the page on its very
    // first build (before the query even resolved, let alone before any
    // row existed to look at). Lazy fix: only build it when there's a
    // selection to build it from; `_threadView` itself is untouched.
    final thread = _selected != null ? _threadView(ng) : null;

    return Scaffold(
      backgroundColor: ng.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wide
              ? Row(
                  children: [
                    SizedBox(width: 320, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(child: thread ?? _threadPlaceholder(ng)),
                  ],
                )
              // Narrow layout is unchanged: thread is only ever non-null
              // here when _selected is non-null (same condition drove
              // both), so falling back to `list` reproduces the original
              // `_selected == null ? list : thread` exactly.
              : (thread == null
                  ? list
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: NgModuleHeader(
                            _selected!.displayName ?? _selected!.phone,
                            onBack: () => setState(() => _selected = null),
                          ),
                        ),
                        Expanded(child: thread),
                      ],
                    )),
    );
  }

  /// Wide-screen right pane when no conversation is selected yet — was a
  /// bare `Text('Select a conversation')` with no visual weight; matches
  /// the icon-plus-message empty-state pattern already used in
  /// [_contactList] instead of reading as an accidentally-blank panel.
  Widget _threadPlaceholder(NgPalette ng) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 40, color: ng.mute),
              const SizedBox(height: 12),
              Text(
                'Select a conversation',
                style: NgFonts.geist(color: ng.mute, fontSize: 13.5),
              ),
            ],
          ),
        ),
      );

  Widget _contactList(NgPalette ng) {
    final c = NgPalette.of(context);
    final unread = _contacts.where((x) => x.unreadCount > 0).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          NgModuleHeader('Inbox', subtitle: 'WhatsApp · $unread unread'),
          const SizedBox(height: 14),
          if (_contacts.isEmpty)
            NgCard(
              child: Text('No WhatsApp conversations yet.',
                  textAlign: TextAlign.center,
                  style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
            )
          else
            NgCardList(children: [
              for (final ct in _contacts)
                InkWell(
                  onTap: () => _openThread(ct),
                  child: Container(
                    color: _selected?.id == ct.id ? c.sel : null,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const NgIconTile(
                            icon: Icons.chat_outlined,
                            status: NgStatus.green,
                            size: 40,
                            iconSize: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(ct.displayName ?? ct.phone,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: NgFonts.geist(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: c.text)),
                                  ),
                                  if (ct.leadId != null) ...[
                                    const SizedBox(width: 6),
                                    const NgPill('Lead',
                                        status: NgStatus.amber),
                                  ],
                                  if (ct.muted) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.notifications_off_outlined,
                                        size: 14, color: c.mute),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(ct.lastMessageText ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: NgFonts.geist(
                                      fontSize: 13, color: c.mute)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (ct.lastMessageAt != null)
                              Text(
                                  DateFormat('d MMM')
                                      .format(ct.lastMessageAt!.toLocal()),
                                  style: NgFonts.geist(
                                      fontSize: 12,
                                      color: ct.unreadCount > 0
                                          ? c.acc
                                          : c.faint)),
                            if (ct.unreadCount > 0) ...[
                              const SizedBox(height: 4),
                              Container(
                                constraints: const BoxConstraints(
                                    minWidth: 20, minHeight: 20),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.accBtn,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('${ct.unreadCount}',
                                    style: NgFonts.geist(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: NgPalette.onAcc)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _threadView(NgPalette ng) {
    final contact = _selected!;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: ng.s1,
          child: Row(
            children: [
              Expanded(
                child: Text(contact.phone,
                    style: NgFonts.geist(fontSize: 12, color: ng.mute)),
              ),
              if (contact.leadId != null)
                TextButton(
                  onPressed: () => context.pushNamed(
                    LeadDetailPageWidget.routeName,
                    queryParameters: {
                      'leadId': serializeParam(contact.leadId, ParamType.String),
                    }.withoutNulls,
                  ),
                  child: const Text('Open Lead'),
                ),
              IconButton(
                tooltip: contact.muted ? 'Unmute' : 'Mute',
                icon: Icon(contact.muted ? Icons.notifications_off : Icons.notifications_active,
                    size: 18),
                onPressed: () => _toggleMute(contact),
              ),
            ],
          ),
        ),
        Expanded(
          child: _threadLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _thread.length,
                  itemBuilder: (context, i) => _bubble(ng, _thread[i]),
                ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: ng.s1,
            border: Border(top: BorderSide(color: ng.w08)),
          ),
          child: Row(
            children: [
              PopupMenuButton<String>(
                tooltip: 'Templates',
                icon: const Icon(Icons.bolt, size: 20),
                onSelected: (t) => _send(templateName: t, body: _templates[t]!),
                itemBuilder: (context) => [
                  for (final t in _templates.keys)
                    PopupMenuItem(value: t, child: Text(t)),
                ],
              ),
              Expanded(
                child: TextField(
                  controller: _composeCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Message…', isDense: true, border: OutlineInputBorder()),
                  minLines: 1,
                  maxLines: 3,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => _send(body: _composeCtrl.text),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bubble(NgPalette ng, WaMessagesRow m) {
    final inbound = m.direction == 'in';
    final isUnsupported = m.msgType == 'unsupported';
    return Align(
      alignment: inbound ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: inbound ? ng.s1 : ng.acc.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUnsupported ? '[unsupported]' : (m.body ?? ''),
              style: NgFonts.geist(
                fontSize: 13,
                fontStyle: isUnsupported ? FontStyle.italic : FontStyle.normal,
                color: inbound ? ng.text : Colors.white,
              ),
            ),
            if (m.sentAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  DateFormat('d MMM, h:mm a').format(m.sentAt!.toLocal()),
                  style: NgFonts.geist(
                      fontSize: 9.5,
                      color: inbound
                          ? ng.mute
                          : Colors.white.withValues(alpha: 0.8)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
