import 'package:flutter/material.dart';
import '/flutter_flow/custom_functions.dart' as functions;

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

import '/backend/edge_function_errors.dart';
import '/backend/tracking_service.dart';
import '/backend/vendor_identity.dart';
import '/components/share_link_sheet.dart';
import '/config/app_config.dart';
import '/nav_items.dart';

/// Extra charges on an order: anything billed on top of the quote.
///
/// Mostly extra WORK agreed after the quote, which often happens on a
/// different day from the move itself. Also GOODS the customer buys —
/// cartons and the like — pushed here by
/// `MaterialUsage.record`.
///
/// **Renamed from "Add-on Services" on 3 Sept 2026.** Arun, seeing a
/// carton box listed under it: *"in add on service y the cartton box?"*.
/// He was right: the table is the single revenue path for everything
/// charged beyond the quote, which is the correct plumbing, but the
/// heading claimed it was all services. Filing goods under a label that
/// says "Services" makes a vendor distrust the line rather than the
/// label. The storage decision is unchanged; only the wording is.
///
/// Built 3 Sept 2026, from Arun's case: *"today ac uninstall done but
/// install is tomorrow, due to this customer have also hold some money —
/// how to track this and complete the pending work and collect the
/// balance money"*.
///
/// **The table and every rollup already existed; only this screen was
/// missing.** `addons` has carried `status`, `assigned_to` and
/// `completed_at` since it was created, and three separate places
/// already read it — the order P&L (`Add-ons (n)` line), Close Order's
/// balance warning, and the Operations "Awaiting Approval" balance, all
/// of which compute `quote_total + non-cancelled add-ons − paid_total`.
/// So the money side of Arun's question was answered in the schema and
/// unanswerable in the product: there were 0 rows and no way to create
/// one. Adding a row here makes the held balance mean something
/// everywhere else, with no change to those three call sites.
///
/// Three states, and they are deliberately not a free-text field:
///  * `pending`   — agreed, not done. Counts toward the balance.
///  * `completed` — done, `completed_at` stamped.
///  * `cancelled` — dropped. **Excluded from every balance**, which is
///    exactly why the existing readers all filter `neq('status',
///    'cancelled')`. Cancelling is therefore how a vendor drops agreed
///    work without editing money by hand.
///
/// A cancelled row is kept rather than deleted, so "we agreed this and
/// then dropped it" survives as a record of what was discussed.
///
/// **The customer's yes (13 Nov 2026).** Arun's phone test, report 7.1:
/// *"the vendor can add additional charges during Move Day without
/// obtaining customer approval"*, with a pending AC install already
/// "included in the balance due". Every charge now carries an approval
/// beside its work status:
///  * `awaiting` — asked, not answered. NOT in any balance.
///  * `approved` — the customer said yes on their tracking page (or the
///    office recorded a yes given on the phone). Billed.
///  * `rejected` — the customer said no. Never billed.
/// The database holds `amount` at zero until approval and keeps the
/// asked figure in `requested_amount`, so every screen that adds up
/// add-ons is right without knowing any of this. This screen is the one
/// place that shows the asked figure.
class OrderAddonsSection extends StatefulWidget {
  const OrderAddonsSection({
    super.key,
    required this.orderId,
    this.onChanged,
    this.readOnly = false,
  });

  final String orderId;

  /// Fires after any write so Order Details can reload the P&L card —
  /// an add-on is revenue, so the two must never disagree.
  final VoidCallback? onChanged;

  /// Set once the order is closed. The list still renders (the history
  /// matters after closing) but nothing can be added or changed.
  final bool readOnly;

  @override
  State<OrderAddonsSection> createState() => OrderAddonsSectionState();
}

class OrderAddonsSectionState extends State<OrderAddonsSection> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await OrgScope.read(SupaFlow.client
              .from('addons')
              .select(
                  'id,description,amount,requested_amount,approval,'
                  'approval_at,approval_by,approval_note,status,assigned_to,'
                  'completed_at,created_at'))
          .eq('order_id', widget.orderId)
          .order('created_at', ascending: true);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load add-ons: ${friendlyError(e)}';
        _loading = false;
      });
    }
  }

  static String _approval(Map<String, dynamic> r) =>
      '${r['approval'] ?? 'approved'}';

  /// The figure asked for. `amount` is zero until the customer approves.
  static double _asked(Map<String, dynamic> r) =>
      (num.tryParse('${r['requested_amount'] ?? r['amount']}') ?? 0)
          .toDouble();

  bool _live(Map<String, dynamic> r) => r['status'] != 'cancelled';

  /// Approved work not yet done: money agreed, job outstanding.
  Iterable<Map<String, dynamic>> get _pendingRows => _rows
      .where((r) => r['status'] == 'pending' && _approval(r) == 'approved');

  double get _pendingTotal => _pendingRows.fold(0.0, (s, r) => s + _asked(r));

  int get _pendingCount => _pendingRows.length;

  Iterable<Map<String, dynamic>> get _awaitingRows =>
      _rows.where((r) => _live(r) && _approval(r) == 'awaiting');

  int get _awaitingCount => _awaitingRows.length;

  double get _awaitingTotal =>
      _awaitingRows.fold(0.0, (s, r) => s + _asked(r));

  /// Sends the customer their tracking link, where each waiting charge
  /// has Approve and Reject. The same link they already use to follow
  /// the move, so there is nothing new for them to learn.
  Future<void> _sendForApproval() async {
    try {
      final token = await TrackingService.tokenForOrder(widget.orderId);
      if (token == null) throw Exception('not ready');
      String? phone;
      String? name;
      try {
        final o = await OrgScope.read(
                SupaFlow.client.from('orders').select('phone,customer'))
            .eq('id', widget.orderId)
            .limit(1);
        if (o.isNotEmpty) {
          phone = o.first['phone'] as String?;
          name = o.first['customer'] as String?;
        }
      } catch (_) {}
      if (!mounted) return;
      final lines = _awaitingRows
          .map((r) => '• ${r['description']}: ${functions.inrFull(_asked(r))}')
          .join('\n');
      await ShareLinkSheet.show(
        context,
        title: 'Ask the customer to approve',
        subtitle: 'They open the link and tap Approve or Reject on each '
            'charge. Only approved charges are added to the bill.',
        link: buildTokenLink('/track', token),
        phone: phone,
        message: 'Hello${(name ?? '').isEmpty ? '' : ' $name'}, '
            '${VendorIdentity.forSentence} needs your approval for:\n'
            '$lines\n\nPlease approve or reject here:',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not open the approval link. Please try again.');
      }
    }
  }

  Future<void> _setApproval(Map<String, dynamic> row, String approval) async {
    try {
      await SupaFlow.client
          .from('addons')
          .update({
            'approval': approval,
            if (approval == 'approved') 'approval_by': 'vendor',
          })
          .eq('id', row['id'])
          .eq('org_id', AppSession.instance.currentOrgId!);
      await _afterWrite();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not update. Please try again.');
      }
    }
  }

  /// The office records a yes the customer gave by phone or in person.
  /// Owner and manager only, and logged as recorded by the office, so it
  /// can never be mistaken for the customer's own tap.
  Future<void> _recordVerbalYes(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NgPalette.of(context).s1,
        title: const Text('Customer agreed?'),
        content: Text(
            'Use this only when the customer has told you yes for '
            '${_desc(row)} at ${functions.inrFull(_asked(row))}. '
            'It is saved as approved by your office, with the time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes, customer agreed')),
        ],
      ),
    );
    if (ok == true) await _setApproval(row, 'approved');
  }

  static String _desc(Map<String, dynamic> r) => '${r['description'] ?? ''}';

  Future<void> _showHistory() async {
    List<Map<String, dynamic>> log = const [];
    try {
      final rows = await SupaFlow.client
          .from('addon_approval_log')
          .select('event,amount,description,actor,note,at')
          .eq('order_id', widget.orderId)
          .order('at', ascending: true);
      log = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}
    if (!mounted) return;
    final ng = NgPalette.of(context);
    String label(Map<String, dynamic> e) {
      final who = e['actor'] == 'customer' ? 'customer' : 'office';
      return switch ('${e['event']}') {
        'requested' => 'Sent for approval',
        'approved' => 'Approved by $who',
        'rejected' => 'Rejected by $who',
        'amount_changed' => 'Amount changed',
        'cancelled' => 'Cancelled',
        _ => '${e['event']}',
      };
    }

    String when(dynamic v) {
      final d = DateTime.tryParse('$v')?.toLocal();
      if (d == null) return '';
      String two(int n) => n.toString().padLeft(2, '0');
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '${d.day} ${m[d.month - 1]} ${d.year}, $h:${two(d.minute)} '
          '${d.hour < 12 ? 'AM' : 'PM'}';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ng.s1,
        title: const Text('Approval history'),
        content: SizedBox(
          width: 420,
          child: log.isEmpty
              ? Text('Nothing recorded yet.',
                  style: NgFonts.geist(fontSize: 13, color: ng.mute))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in log)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${e['description'] ?? ''} · '
                                '${functions.inrFull((num.tryParse('${e['amount']}') ?? 0).toDouble())}',
                                style: NgFonts.geist(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: ng.text)),
                            Text(
                                '${label(e)} · ${when(e['at'])}'
                                '${(e['note'] ?? '').toString().isEmpty ? '' : '\n${e['note']}'}',
                                style: NgFonts.geist(
                                    fontSize: 12, color: ng.mute)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  /// After a write the whole row set is RE-READ rather than patched in
  /// place. CLAUDE.md's standing rule, learned three times over: the DB
  /// was right and the screen was wrong, because someone updated the one
  /// field they remembered changing and missed what a default or trigger
  /// had also set.
  Future<void> _afterWrite() async {
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final descCtrl =
        TextEditingController(text: '${existing?['description'] ?? ''}');
    final amountCtrl = TextEditingController(
        text: existing == null ? '' : '${_asked(existing).toInt()}');
    final wasApproved =
        existing != null && _approval(existing) == 'approved';
    String? err;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: NgPalette.of(context).s1,
          title: Text(existing == null ? 'Add a charge' : 'Edit charge'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'What is being charged?',
                  hintText: 'e.g. AC install at destination',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                // No suggested figure. What this extra work costs is the
                // vendor's call and varies by job.
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 10),
              Text(
                existing == null
                    ? 'The customer approves this before it is added to '
                        'the bill.'
                    : wasApproved
                        ? 'If you change the amount, the customer has to '
                            'approve it again.'
                        : 'The customer approves this before it is added '
                            'to the bill.',
                style: TextStyle(
                    fontSize: 12, color: NgPalette.of(context).mute),
              ),
              if (err != null) ...[
                const SizedBox(height: 10),
                Text(err!,
                    style: TextStyle(
                        fontSize: 12,
                        color: NgPalette.of(context).red)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (descCtrl.text.trim().isEmpty) {
                  setLocal(() => err = 'Describe the work.');
                  return;
                }
                if ((double.tryParse(amountCtrl.text.trim()) ?? 0) <= 0) {
                  setLocal(() => err = 'Enter the amount agreed.');
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final desc = descCtrl.text.trim();
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;

    try {
      if (existing == null) {
        await SupaFlow.client.from('addons').insert({
          ...OrgScope.stamp(),
          'order_id': widget.orderId,
          'description': desc,
          'amount': amount,
          'status': 'pending',
        });
      } else {
        await SupaFlow.client
            .from('addons')
            .update({'description': desc, 'amount': amount})
            .eq('id', existing['id'])
            .eq('org_id', AppSession.instance.currentOrgId!);
      }
      await _afterWrite();
      // Straight to the ask: a charge that is saved and never sent is a
      // charge that never gets approved.
      if (mounted && _awaitingCount > 0 && existing == null) {
        await _sendForApproval();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save add-on: ${friendlyError(e)}');
    }
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    try {
      await SupaFlow.client
          .from('addons')
          .update({
            'status': status,
            // Stamped only on completion, and cleared if the row is
            // reopened, so completed_at can never describe a row that is
            // not actually complete.
            'completed_at':
                status == 'completed' ? DateTime.now().toUtc().toIso8601String() : null,
          })
          .eq('id', row['id'])
          .eq('org_id', AppSession.instance.currentOrgId!);
      await _afterWrite();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update: ${friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.handyman_outlined, size: 18, color: ng.mute),
              const SizedBox(width: 8),
              Text('Extra charges',
                  style: NgFonts.geist(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ng.text)),
              // Pending count on the HEADER, not only in the list below.
              // Arun, 3 Sept 2026: "that addon serice is pending so make
              // it clear its pending in that order". Outstanding work is
              // the thing a vendor needs to see without reading the
              // rows - it is money not yet earned and a job not yet
              // finished.
              if (_awaitingCount > 0) ...[
                const SizedBox(width: 8),
                NgPill('$_awaitingCount to approve', status: NgStatus.amber),
              ] else if (_pendingCount > 0) ...[
                const SizedBox(width: 8),
                NgPill('$_pendingCount pending', status: NgStatus.amber),
              ],
              const Spacer(),
              if (_rows.isNotEmpty)
                NgLinkButton('History', onTap: _showHistory),
              if (!widget.readOnly)
                NgLinkButton('Add',
                    icon: Icons.add_rounded, onTap: () => _addOrEdit()),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Anything charged on top of the quote — an AC install the '
                'next day, a carpenter, a second trip, or materials the '
                'customer bought. The customer approves each one before it '
                'is added to the bill.',
                style: NgFonts.geist(
                    fontSize: 13, height: 1.4, color: ng.mute),
              ),
            )
          else ...[
            if (_awaitingCount > 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ng.amberBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_awaitingCount waiting for the customer · '
                      '${functions.inrFull(_awaitingTotal)}. Not in the '
                      'bill until they approve.',
                      style: NgFonts.geist(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ng.text),
                    ),
                    if (!widget.readOnly) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _sendForApproval,
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Send approval link'),
                      ),
                    ],
                  ],
                ),
              ),
            if (_pendingCount > 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ng.amberBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_pendingCount pending · '
                  '${functions.inrFull(_pendingTotal)} still to be done. '
                  'This is included in the balance due.',
                  style: NgFonts.geist(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ng.text),
                ),
              ),
            for (final r in _rows) _addonRow(ng, r),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: NgFonts.geist(fontSize: 12, color: ng.red)),
          ],
        ],
      ),
    );
  }

  Widget _addonRow(NgPalette ng, Map<String, dynamic> r) {
    final status = '${r['status'] ?? 'pending'}';
    final approval = _approval(r);
    final amount = _asked(r);
    final cancelled = status == 'cancelled';
    final done = status == 'completed';
    final awaiting = !cancelled && approval == 'awaiting';
    final rejected = !cancelled && approval == 'rejected';
    final struck = cancelled || rejected;

    final (Color chipColor, String chipLabel, IconData icon) = cancelled
        ? (ng.mute, 'Cancelled', Icons.block_rounded)
        : rejected
            ? (ng.red, 'Customer said no · not billed', Icons.close_rounded)
            : awaiting
                ? (
                    ng.amber,
                    'Waiting for customer approval',
                    Icons.hourglass_top_rounded
                  )
                : done
                    ? (ng.green, 'Approved · Done', Icons.check_rounded)
                    : (
                        ng.amber,
                        'Approved · work pending',
                        Icons.schedule_rounded
                      );

    String sub = chipLabel;
    if (!cancelled && approval == 'approved' && r['approval_at'] != null) {
      final d = DateTime.tryParse('${r['approval_at']}')?.toLocal();
      final by = r['approval_by'] == 'customer' ? 'customer' : 'office';
      if (d != null) {
        sub = '$chipLabel\nApproved by $by · ${d.day}/${d.month}/${d.year}';
      }
    }
    final note = '${r['approval_note'] ?? ''}'.trim();
    if (rejected && note.isNotEmpty) sub = '$sub\n"$note"';

    final pending = !done && !struck;
    final office = isOwnerOrManagerSession;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
      decoration: BoxDecoration(
        color: pending ? ng.amberBg : ng.inset,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          NgIconTile(
              icon: icon,
              status: struck
                  ? NgStatus.neutral
                  : done && !awaiting
                      ? NgStatus.green
                      : NgStatus.amber,
              size: 32,
              iconSize: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['description'] ?? ''}',
                  style: NgFonts.geist(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: struck ? ng.mute : ng.text,
                    decoration: struck ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(sub,
                    style: NgFonts.geist(
                        fontSize: 12, height: 1.35, color: chipColor)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            functions.inrFull(amount),
            style: NgFonts.mono(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: struck || awaiting ? ng.mute : ng.text,
              decoration: struck ? TextDecoration.lineThrough : null,
            ),
          ),
          if (!widget.readOnly)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: ng.mute),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _addOrEdit(existing: r);
                  case 'send':
                    _sendForApproval();
                  case 'verbal':
                    _recordVerbalYes(r);
                  case 'ask_again':
                    _setApproval(r, 'awaiting');
                  default:
                    _setStatus(r, v);
                }
              },
              itemBuilder: (_) => [
                if (awaiting)
                  const PopupMenuItem(
                      value: 'send', child: Text('Send approval link')),
                if (awaiting && office)
                  const PopupMenuItem(
                      value: 'verbal',
                      child: Text('Customer agreed on call')),
                if (rejected)
                  const PopupMenuItem(
                      value: 'ask_again',
                      child: Text('Ask the customer again')),
                if (!done && !cancelled && !rejected)
                  const PopupMenuItem(
                      value: 'completed', child: Text('Mark work done')),
                if (done)
                  const PopupMenuItem(
                      value: 'pending', child: Text('Reopen as pending')),
                if (!cancelled)
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (!cancelled)
                  const PopupMenuItem(
                      value: 'cancelled', child: Text('Cancel this charge')),
                if (cancelled)
                  const PopupMenuItem(
                      value: 'pending', child: Text('Restore')),
              ],
            ),
        ],
      ),
    );
  }
}
