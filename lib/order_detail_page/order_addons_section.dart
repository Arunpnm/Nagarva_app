import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';

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
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
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
                        color: FlutterFlowTheme.of(context).error)),
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
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.handyman_outlined, size: 18, color: theme.primary),
              const SizedBox(width: 8),
              Text('Extra Charges',
                  style: GoogleFonts.interTight(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryText)),
              // Pending count on the HEADER, not only in the list below.
              // Arun, 3 Sept 2026: "that addon serice is pending so make
              // it clear its pending in that order". Outstanding work is
              // the thing a vendor needs to see without reading the
              // rows - it is money not yet earned and a job not yet
              // finished.
              if (_pendingCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.warning,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$_pendingCount PENDING',
                      style: GoogleFonts.interTight(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Colors.white)),
                ),
              ],
              const Spacer(),
              if (!widget.readOnly)
                TextButton.icon(
                  onPressed: () => _addOrEdit(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
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
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Anything charged on top of the quote — an AC install the '
                'next day, a carpenter, a second trip, or materials the '
                'customer bought. Pending items count toward the balance '
                'until they are done.',
                style:
                    GoogleFonts.inter(fontSize: 12, color: theme.secondaryText),
              ),
            )
          else ...[
            if (_pendingCount > 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6, bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_pendingCount pending · '
                  '₹${_pendingTotal.toStringAsFixed(0)} still to be done. '
                  'This is included in the balance due.',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryText),
                ),
              ),
            for (final r in _rows) _addonRow(theme, r),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: GoogleFonts.inter(fontSize: 12, color: theme.error)),
          ],
        ],
      ),
    );
  }

  Widget _addonRow(FlutterFlowTheme theme, Map<String, dynamic> r) {
    final status = '${r['status'] ?? 'pending'}';
    final amount = (num.tryParse('${r['amount']}') ?? 0).toDouble();
    final cancelled = status == 'cancelled';
    final done = status == 'completed';

    final (Color chipColor, String chipLabel, IconData icon) = switch (status) {
      'completed' => (theme.success, 'Done', Icons.check_circle_outline),
      'cancelled' => (theme.secondaryText, 'Cancelled', Icons.block),
      _ => (theme.warning, 'Pending', Icons.schedule),
    };

    final pending = !done && !cancelled;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.fromLTRB(pending ? 8 : 0, 6, 0, 6),
      decoration: pending
          // A pending charge is money not yet earned and work not yet
          // done. It gets a tint and a rule so it cannot be skimmed past
          // as if it were finished.
          ? BoxDecoration(
              color: theme.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                  left: BorderSide(color: theme.warning, width: 3)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: chipColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['description'] ?? ''}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cancelled ? theme.secondaryText : theme.primaryText,
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
                  style: GoogleFonts.inter(fontSize: 11, color: chipColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: GoogleFonts.interTight(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cancelled ? theme.secondaryText : theme.primaryText,
              decoration: cancelled ? TextDecoration.lineThrough : null,
            ),
          ),
          if (!widget.readOnly)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: theme.secondaryText),
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
