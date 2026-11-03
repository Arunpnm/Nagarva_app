import 'package:flutter/material.dart';
import '/components/ng_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '/backend/edge_function_errors.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';

/// Admin › Approvals › "New vendor signups" (Claude Design handoff,
/// 21 Oct 2026). Lists `vendor_signups`; Approve creates the org on the
/// Free plan, Send back records a reason the applicant sees on their
/// status screen. Both go through `review_vendor_signup()`, which checks
/// `is_platform_admin()` itself — this tab hiding for non-admins is
/// presentation, the function is the gate.
///
/// The design's "owner notified on WhatsApp" is deliberately absent:
/// there is no send path yet, so the applicant finds out by opening the
/// app, which is what the status screen tells them.
class SignupsTab extends StatefulWidget {
  const SignupsTab({super.key, this.onChanged});

  /// Called after a decision so the Tenants tab can reload.
  final VoidCallback? onChanged;

  @override
  State<SignupsTab> createState() => _SignupsTabState();
}

const _kReasons = [
  'PAN card photo is not clear',
  'GST certificate does not match the GSTIN',
  'Business details are incomplete',
  'This business already has an account',
];

const _kDocLabels = {
  'pan': 'PAN card',
  'gstc': 'GST certificate',
  'shop': 'Office photo',
};

const _kBizLabels = {
  'packers_movers': 'Packers & movers',
  'transport': 'Transport',
  'both': 'Packers & transport',
};

class _SignupsTabState extends State<SignupsTab> {
  bool _loading = true;
  bool _pendingOnly = true;
  List<Map<String, dynamic>> _rows = [];
  String? _picking; // signup id whose reason chips are open
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await SupaFlow.client
          .from('vendor_signups')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _rows = List<Map<String, dynamic>>.from(rows as List));
      }
    } catch (e) {
      _snack('Could not load signups. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _confirmSendBack(Map<String, dynamic> r, String reason) async {
    final ctrl = TextEditingController(text: reason);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send back ${r['business_name'] ?? 'this application'}?'),
        content: TextField(
          controller: ctrl,
          autofocus: reason.isEmpty,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Reason the owner will see'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isNotEmpty) Navigator.pop(ctx, t);
              },
              child: const Text('Send back')),
        ],
      ),
    );
    if (picked != null && mounted) await _decide(r, false, picked);
  }

  Future<void> _decide(Map<String, dynamic> r, bool approve,
      [String? reason]) async {
    setState(() => _busy = r['id'] as String);
    try {
      await SupaFlow.client.rpc('review_vendor_signup', params: {
        'p_signup_id': r['id'],
        'p_approve': approve,
        'p_reason': reason,
      });
      _snack(approve
          ? '${r['business_name']} approved · owner can start a Pro trial'
          : 'Sent back · ${r['owner_name']}');
      _picking = null;
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      _snack(extractDbErrorMessage(e, fallback: 'Could not save: ${friendlyError(e)}'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // BUG-008: show +91 98765 43210, not the raw stored digits.
  String _fmtPhone(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 10) return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
    return '+$d';
  }

  // BUG-008: unknown doc keys read as words, not snake_case keys.
  String _docLabel(String key) {
    final known = _kDocLabels[key];
    if (known != null) return known;
    final t = key.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return t.isEmpty ? 'Document' : t[0].toUpperCase() + t.substring(1);
  }

  Future<void> _openDoc(String path) async {
    try {
      final url = await SupaFlow.client.storage
          .from('vendor-docs')
          .createSignedUrl(path, 300);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      _snack('Could not open the document: ${friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    final c = NgPalette.of(context);
    final shown = _rows
        .where((r) =>
            _pendingOnly ? r['status'] == 'pending' : r['status'] != 'pending')
        .toList();
    final pendingN = _rows.where((r) => r['status'] == 'pending').length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('Pending ($pendingN)'),
                selected: _pendingOnly,
                onSelected: (_) => setState(() => _pendingOnly = true),
              ),
              ChoiceChip(
                label: const Text('Decided'),
                selected: !_pendingOnly,
                onSelected: (_) => setState(() => _pendingOnly = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                    _pendingOnly
                        ? 'No signups waiting for review.'
                        : 'No decided signups yet.',
                    style: NgFonts.geist(color: ng.mute)),
              ),
            )
          else
            for (final r in shown) _card(ng, c, r),
        ],
      ),
    );
  }

  Widget _card(NgPalette ng, NgPalette c, Map<String, dynamic> r) {
    final st = r['status'] as String? ?? 'pending';
    final (:fg, :bg) = c.status(st == 'approved'
        ? NgStatus.green
        : st == 'rejected'
            ? NgStatus.red
            : NgStatus.amber);
    final created = DateTime.tryParse(r['created_at'] ?? '')?.toLocal();
    final docs = Map<String, dynamic>.from(r['docs'] ?? {})
      ..removeWhere((_, v) => (v as String? ?? '').isEmpty);
    final busy = _busy == r['id'];
    final details = [
      ('Application', r['app_no'] ?? ''),
      ('GSTIN', (r['gstin'] as String?) ?? 'Not registered'),
      ('Email', (r['email'] as String?) ?? '—'),
      ('Referral code', (r['referral_code'] as String?) ?? '—'),
    ];

    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.storefront_outlined, color: fg, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['business_name'] ?? '',
                        style: NgFonts.geist(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: ng.text)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        r['owner_name'],
                        _fmtPhone('${r['phone'] ?? ''}'),
                        r['city'],
                        _kBizLabels[r['business_type']] ?? '',
                        if (created != null)
                          dateTimeFormat('d MMM, h:mm a', created),
                      ]
                          .where((x) => (x ?? '').toString().isNotEmpty)
                          .join(' · '),
                      style: NgFonts.geist(
                          fontSize: 12.5, color: ng.mute),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              for (final d in details)
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${d.$1}  ',
                      style: NgFonts.geist(
                          fontSize: 12, color: ng.mute)),
                  TextSpan(
                      text: d.$2.toString(),
                      style: NgFonts.geist(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: ng.text)),
                ])),
            ],
          ),
          if (docs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in docs.entries)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 16),
                    label: Text(_docLabel(e.key)),
                    onPressed: () => _openDoc(e.value as String),
                  ),
              ],
            ),
          ],
          if (st == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => _picking =
                          _picking == r['id'] ? null : r['id'] as String),
                  child: const Text('Send back'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : () => _decide(r, true),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Approve'),
                ),
              ],
            ),
            if (_picking == r['id']) ...[
              const SizedBox(height: 10),
              Text('Reason the owner will see',
                  style: NgFonts.geist(
                      fontSize: 12.5, color: ng.mute)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // BUG-007 (3 Nov 2026): one tap used to send the
                  // application back. A chip now opens a confirm with the
                  // reason editable; the GST chip only shows when a GSTIN
                  // was given.
                  for (final w in _kReasons)
                    if (!w.startsWith('GST') ||
                        '${r['gstin'] ?? ''}'.trim().isNotEmpty)
                      ActionChip(
                        label: Text(w),
                        onPressed:
                            busy ? null : () => _confirmSendBack(r, w),
                      ),
                  ActionChip(
                    label: const Text('Other reason…'),
                    onPressed: busy ? null : () => _confirmSendBack(r, ''),
                  ),
                ],
              ),
            ],
          ] else ...[
            const SizedBox(height: 10),
            Text(
              st == 'approved'
                  ? 'Approved${r['plan_choice'] == null ? ' · plan not chosen yet' : ' · chose ${r['plan_choice'] == 'trial' ? 'Pro trial' : 'Free'}'}'
                  : 'Sent back: ${r['reason'] ?? ''}',
              style: NgFonts.geist(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: st == 'approved' ? c.green : c.red),
            ),
          ],
        ],
      ),
    );
  }
}
