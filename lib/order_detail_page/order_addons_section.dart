import 'package:flutter/material.dart';
import '/flutter_flow/custom_functions.dart' as functions;

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

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
                  'id,description,amount,status,assigned_to,completed_at,created_at'))
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
        _error = 'Could not load add-ons: $e';
        _loading = false;
      });
    }
  }

  double get _pendingTotal => _rows
      .where((r) => r['status'] == 'pending')
      .fold(0.0, (s, r) => s + (num.tryParse('${r['amount']}') ?? 0));

  int get _pendingCount => _rows.where((r) => r['status'] == 'pending').length;

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
        text: existing == null || existing['amount'] == null
            ? ''
            : '${(num.tryParse('${existing['amount']}') ?? 0).toInt()}');
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
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save add-on: $e');
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
                status == 'completed' ? DateTime.now().toIso8601String() : null,
          })
          .eq('id', row['id'])
          .eq('org_id', AppSession.instance.currentOrgId!);
      await _afterWrite();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update: $e');
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
              if (_pendingCount > 0) ...[
                const SizedBox(width: 8),
                NgPill('$_pendingCount pending', status: NgStatus.amber),
              ],
              const Spacer(),
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
                'customer bought. Pending items count toward the balance '
                'until they are done.',
                style: NgFonts.geist(
                    fontSize: 13, height: 1.4, color: ng.mute),
              ),
            )
          else ...[
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
    final amount = (num.tryParse('${r['amount']}') ?? 0).toDouble();
    final cancelled = status == 'cancelled';
    final done = status == 'completed';

    final (Color chipColor, String chipLabel, IconData icon) = switch (status) {
      'completed' => (ng.green, 'Done', Icons.check_rounded),
      'cancelled' => (ng.mute, 'Cancelled', Icons.block_rounded),
      _ => (ng.amber, 'Pending', Icons.schedule_rounded),
    };

    final pending = !done && !cancelled;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
      decoration: BoxDecoration(
        // A pending charge is money not yet earned and work not yet
        // done. It gets a tint so it cannot be skimmed past as if it
        // were finished.
        color: pending ? ng.amberBg : ng.inset,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          NgIconTile(
              icon: icon,
              status: done
                  ? NgStatus.green
                  : cancelled
                      ? NgStatus.neutral
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
                    color: cancelled ? ng.mute : ng.text,
                    // A cancelled row stays visible as a record of what
                    // was discussed, struck through so it cannot be
                    // misread as outstanding work.
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  done && r['completed_at'] != null
                      ? '$chipLabel · ${'${r['completed_at']}'.split('T').first}'
                      : chipLabel,
                  style: NgFonts.geist(fontSize: 12, color: chipColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            functions.inrFull(amount),
            style: NgFonts.mono(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: cancelled ? ng.mute : ng.text,
              decoration: cancelled ? TextDecoration.lineThrough : null,
            ),
          ),
          if (!widget.readOnly)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: ng.mute),
              onSelected: (v) {
                if (v == 'edit') {
                  _addOrEdit(existing: r);
                } else {
                  _setStatus(r, v);
                }
              },
              itemBuilder: (_) => [
                if (!done)
                  const PopupMenuItem(
                      value: 'completed', child: Text('Mark done')),
                if (done)
                  const PopupMenuItem(
                      value: 'pending', child: Text('Reopen as pending')),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (!cancelled)
                  const PopupMenuItem(
                      value: 'cancelled',
                      child: Text('Cancel (drops from balance)')),
                if (cancelled)
                  const PopupMenuItem(
                      value: 'pending', child: Text('Restore as pending')),
              ],
            ),
        ],
      ),
    );
  }
}
