import 'package:flutter/material.dart';

import '/backend/doc_prefix.dart';
import '/backend/edge_function_errors.dart';
import '/backend/fy_numbering.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

/// Settings › Financial year & numbering › Document prefixes
/// (4 Nov 2026, BUG-017).
///
/// Every series got an automatic prefix (the first letters of the company
/// name) and nothing let the owner change it. A prefix can be changed
/// only while the series has issued nothing (`last_number = 0`): rewriting
/// it mid-count would leave issued documents under an identity the series
/// no longer carries. Uniqueness across companies is checked by the
/// `check_doc_prefix` RPC first and enforced again by the
/// `number_series_prefix_unique` trigger.
class DocPrefixCard extends StatefulWidget {
  const DocPrefixCard({super.key});

  @override
  State<DocPrefixCard> createState() => _DocPrefixCardState();
}

class _DocPrefixCardState extends State<DocPrefixCard> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  static const _labels = {
    'invoice': 'Tax invoice',
    'receipt': 'Money receipt',
    'proforma': 'Proforma',
    'voucher': 'Voucher',
    'quotation': 'Quotation',
    'credit_note': 'Credit note',
    'debit_note': 'Debit note',
    'lr': 'Lorry receipt',
    'claim': 'Claim',
    'contract': 'Contract',
    'po': 'Purchase order',
    'grn': 'Goods received',
    'payslip': 'Payslip',
    'storage_job': 'Storage job',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cur = currentFy();
      final rows = await OrgScope.read(SupaFlow.client
              .from('number_series')
              .select('id, doc_type, fy, prefix, padding, last_number, branch'))
          .eq('active', true)
          .inFilter('fy', [cur, nextFy(cur)])
          .order('doc_type', ascending: true);
      final list = [
        for (final r in rows as List)
          if (_labels.containsKey(r['doc_type']))
            Map<String, dynamic>.from(r as Map)
      ]..sort((a, b) {
          final t = '${a['doc_type']}'.compareTo('${b['doc_type']}');
          return t != 0 ? t : '${a['fy']}'.compareTo('${b['fy']}');
        });
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      if (mounted) {
        setState(() => _error = extractDbErrorMessage(e,
            fallback: 'Could not read document prefixes.'));
      }
    }
  }

  String _sample(Map<String, dynamic> r) {
    final pad = (r['padding'] as num?)?.toInt() ?? 4;
    final next = ((r['last_number'] as num?)?.toInt() ?? 0) + 1;
    return '${r['prefix'] ?? ''}${next.toString().padLeft(pad, '0')}';
  }

  Future<void> _edit(Map<String, dynamic> r) async {
    final ctrl = TextEditingController(text: '${r['prefix'] ?? ''}');
    String? err;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> save() async {
          final p = ctrl.text.trim();
          if (!RegExp(r'^[A-Za-z0-9/-]{1,12}$').hasMatch(p)) {
            setD(() => err = 'Use up to 12 letters, numbers, / or -.');
            return;
          }
          try {
            final taken = docPrefixRejection(await SupaFlow.client.rpc(
                'check_doc_prefix',
                params: {'p_prefix': p, 'p_org_id': OrgScope.currentOrgId}));
            if (taken != null) {
              setD(() => err = 'Another company already uses this prefix.');
              return;
            }
            // Only while nothing has been issued from this series.
            final updated = await OrgScope.write(SupaFlow.client
                    .from('number_series')
                    .update({'prefix': p}))
                .eq('id', r['id'])
                .eq('last_number', 0)
                .select('id');
            if ((updated as List).isEmpty) {
              setD(() => err =
                  'A number has already been issued from this series, so '
                  'its prefix can no longer change.');
              return;
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            setD(() => err = extractDbErrorMessage(e,
                fallback: 'Could not save the prefix. Try again.'));
          }
        }

        return AlertDialog(
          title: Text('${_labels[r['doc_type']]} prefix · ${r['fy']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              maxLength: 12,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'e.g. APC/2026-27/',
                  helperText: 'Put the year in it if numbers should start '
                      'again at 1 every April.',
                  helperMaxLines: 2),
            ),
            if (err != null)
              Text(err!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(onPressed: save, child: const Text('Save')),
          ],
        );
      }),
    );
    Future.delayed(const Duration(milliseconds: 600), ctrl.dispose);
    if (saved == true) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Prefix saved.')));
      }
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    if (_error != null) {
      return NgCard(
          child: Text(_error!, style: NgFonts.geist(fontSize: 13, color: c.red)));
    }
    final rows = _rows;
    if (rows == null) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NgFieldLabel('Document prefixes'),
        Text(
            'Tap a series that has not issued a number yet to change its '
            'prefix. A series already in use keeps its prefix so issued '
            'documents stay valid.',
            style: NgFonts.geist(fontSize: 12.5, height: 1.4, color: c.mute)),
        const SizedBox(height: 10),
        NgCardList(children: [
          for (final r in rows)
            InkWell(
              onTap: ((r['last_number'] as num?) ?? 0) == 0 ? () => _edit(r) : null,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_labels[r['doc_type']]}',
                            style: NgFonts.geist(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: c.text)),
                        Text('${r['fy']}',
                            style: NgFonts.geist(fontSize: 12, color: c.mute)),
                      ],
                    ),
                  ),
                  Text(_sample(r),
                      style: NgFonts.mono(fontSize: 13.5, color: c.text)),
                  const SizedBox(width: 8),
                  Icon(
                      ((r['last_number'] as num?) ?? 0) == 0
                          ? Icons.edit_outlined
                          : Icons.lock_outline_rounded,
                      size: 18,
                      color: c.mute),
                ]),
              ),
            ),
        ]),
      ],
    );
  }
}
