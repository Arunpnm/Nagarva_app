import 'package:flutter/material.dart';

import '/app_session.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/super_admin_page/admin_common.dart';
import '/super_admin_page/tickets_tab.dart';

/// Help & support › Ask Nagarva: the vendor raises a ticket and follows the
/// replies. Only this org's tickets are visible (support_tickets RLS), and
/// the thread is the same page Nagarva support answers from.
class SupportTicketsPage extends StatefulWidget {
  const SupportTicketsPage({super.key});
  @override
  State<SupportTicketsPage> createState() => _SupportTicketsPageState();
}

class _SupportTicketsPageState extends AdminSectionState<SupportTicketsPage> {
  List<Map<String, dynamic>> _tickets = const [];

  String? get _org => AppSession.instance.currentOrgId;

  @override
  Future<void> fetch() async {
    final org = _org;
    if (org == null) {
      _tickets = const [];
      return;
    }
    _tickets = List<Map<String, dynamic>>.from(await db
        .from('support_tickets')
        .select()
        .eq('org_id', org)
        .order('updated_at', ascending: false));
  }

  Future<void> _new() async {
    final subject = TextEditingController();
    final details = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ask Nagarva',
              style: NgFonts.geist(
                  fontSize: 18, fontWeight: FontWeight.w600, color: NgPalette.of(ctx).text)),
          const SizedBox(height: 12),
          NgInput(controller: subject, label: 'What is it about?', hint: 'e.g. Forgot PIN'),
          const SizedBox(height: 10),
          NgInput(controller: details, label: 'Details', hint: 'What happened, and on which screen', maxLines: 5),
          const SizedBox(height: 14),
          NgPrimaryButton(label: 'Send to Nagarva', onPressed: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    final s = subject.text.trim(), d = details.text.trim();
    subject.dispose();
    details.dispose();
    if (ok != true) return;
    if (s.length < 3 || d.isEmpty) return toast('Add a short subject and the details.');
    final org = _org;
    if (org == null) return toast('Sign in to your business first.');
    await run(
        () => db.from('support_tickets').insert({
              'org_id': org,
              'raised_by_name': AppSession.instance.currentStaffName ?? AppSession.instance.currentOrgName,
              'subject': s,
              'body': d,
            }),
        'Sent. Nagarva support will reply here.');
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgSimpleBar(title: 'Ask Nagarva'),
      floatingActionButton: missing
          ? null
          : FloatingActionButton.extended(
              onPressed: _new,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New question')),
      body: body((c) => [
            Text('Questions to Nagarva support about your account, plan or the app. Replies appear here.',
                style: NgFonts.geist(fontSize: 13, color: c.mute, height: 1.4)),
            const SizedBox(height: 12),
            if (_tickets.isEmpty)
              const NgEmptyState(
                  icon: Icons.support_agent_rounded,
                  title: 'No questions yet',
                  subtitle: 'Tap New question to ask Nagarva support.')
            else
              NgCardList(children: [
                for (final t in _tickets)
                  NgListRow(
                    icon: Icons.forum_outlined,
                    title: '${t['subject']}',
                    subtitle: 'T-${t['ticket_no']} · ${adminAgo(t['updated_at'])}',
                    trailing: NgPill(
                        switch ('${t['status']}') {
                          'waiting' => 'Reply needed',
                          'resolved' => 'Resolved',
                          _ => 'With Nagarva',
                        },
                        status: switch ('${t['status']}') {
                          'waiting' => NgStatus.amber,
                          'resolved' => NgStatus.green,
                          _ => NgStatus.blue,
                        }),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TicketThreadPage(
                              ticket: t,
                              orgName: AppSession.instance.currentOrgName ?? 'You',
                              asAdmin: false)));
                      load();
                    },
                  ),
              ]),
          ]),
    );
  }
}
