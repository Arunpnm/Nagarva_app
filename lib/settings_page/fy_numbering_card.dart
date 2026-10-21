import 'package:flutter/material.dart';

import '/backend/edge_function_errors.dart';
import '/backend/fy_numbering.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

/// Settings › Financial year & numbering (CLAUDE.md, March 2027 deadline).
///
/// Shows which FY is current, and previews — from the same database
/// function that does the work, in dry-run mode — the first number every
/// document will get next year, before anyone confirms. Owner/manager
/// only: `roll_over_number_series` refuses everyone else.
class FyNumberingCard extends StatefulWidget {
  const FyNumberingCard({super.key});

  @override
  State<FyNumberingCard> createState() => _FyNumberingCardState();
}

class _FyNumberingCardState extends State<FyNumberingCard> {
  FyRolloverResult? _preview;
  String? _error;
  bool _busy = false;

  /// The year to act on: the current FY if any of its series is still
  /// missing (it is April and nobody started it), otherwise the next.
  late String _target;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cur = currentFy();
      final now = await FyNumbering.preview(cur);
      final missingNow = now.items.any((i) => i.status != 'exists');
      _target = missingNow && now.items.isNotEmpty ? cur : nextFy(cur);
      _preview = _target == cur ? now : await FyNumbering.preview(_target);
    } catch (e) {
      _error = extractDbErrorMessage(e,
          fallback: 'Could not read numbering: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _start() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Start $_target numbering?'),
        content: const Text(
            'Series with the year in their prefix start again at 1 under '
            'the new year. Series without a year continue from last '
            'year, and are only created once the year has begun, so no '
            'number can be issued twice.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Start $_target')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await FyNumbering.start(_target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(r.created == 0
                ? 'Nothing new to start yet.'
                : 'Started ${r.created} series for $_target.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(extractDbErrorMessage(e,
                fallback: 'Could not start numbering: $e'))));
      }
    }
    await _load();
  }

  static String _label(String docType) => switch (docType) {
        'invoice' => 'Tax invoice',
        'receipt' => 'Money receipt',
        'proforma' => 'Proforma',
        'voucher' => 'Voucher',
        'quotation' => 'Quotation',
        'credit_note' => 'Credit note',
        'debit_note' => 'Debit note',
        'lr' => 'Lorry receipt',
        'claim' => 'Claim',
        'contract' => 'Contract',
        'po' => 'Purchase order',
        'grn' => 'Goods received',
        'payslip' => 'Payslip',
        'storage_job' => 'Storage job',
        _ => docType,
      };

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final p = _preview;
    if (_error != null) {
      return NgCard(
          child: Text(_error!, style: NgFonts.geist(fontSize: 13, color: c.red)));
    }
    if (p == null) {
      return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()));
    }
    final items = p.items;
    final ready = items.where((i) => i.status == 'ready').length;
    final waits = items.where((i) => i.status == 'waits').length;
    final allDone = items.isNotEmpty && items.every((i) => i.status == 'exists');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NgCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current year ${currentFy()}',
                  style: NgFonts.geist(
                      fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 4),
              Text(
                  allDone
                      ? '$_target numbering is ready.'
                      : _target == currentFy()
                          ? 'This year\'s numbering has not been started. '
                              'Documents cannot get a number until it is.'
                          : 'Next: $_target, from 1 April ${_target.substring(0, 4)}. '
                              'Start it now so the first document of the year '
                              'does not stop to ask.',
                  style: NgFonts.geist(fontSize: 13, height: 1.4, color: c.mute)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        NgFieldLabel('First number in $_target'),
        NgCardList(children: [
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_label(i.docType),
                          style: NgFonts.geist(
                              fontSize: 14, fontWeight: FontWeight.w500, color: c.text)),
                      if (i.continues)
                        Text('Continues from last year',
                            style: NgFonts.geist(fontSize: 12, color: c.mute)),
                    ],
                  ),
                ),
                Text(i.firstNumber,
                    style: NgFonts.mono(fontSize: 13.5, color: c.text)),
                const SizedBox(width: 8),
                NgPill(
                  switch (i.status) {
                    'exists' || 'created' => 'Ready',
                    'waits' => 'On 1 Apr',
                    _ => 'To start',
                  },
                  status: switch (i.status) {
                    'exists' || 'created' => NgStatus.green,
                    'waits' => NgStatus.blue,
                    _ => NgStatus.amber,
                  },
                ),
              ]),
            ),
        ]),
        if (waits > 0) ...[
          const SizedBox(height: 10),
          Text(
              'Series marked "On 1 Apr" carry no year in their prefix, so they '
              'continue last year\'s count. They are created when the year '
              'begins — the first document that needs one will offer it.',
              style: NgFonts.geist(fontSize: 12.5, height: 1.4, color: c.mute)),
        ],
        const SizedBox(height: 16),
        if (ready > 0)
          NgPrimaryButton(
            label: 'Start $_target numbering',
            icon: Icons.play_arrow_rounded,
            onPressed: _busy ? null : _start,
          ),
      ],
    );
  }
}
