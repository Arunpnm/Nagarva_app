import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/backend/supabase/supabase.dart';
import '/backend/tracking_service.dart';
import '/backend/vendor_identity.dart';
import '/components/share_link_sheet.dart';
import '/config/app_config.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/nav_items.dart';

/// The arrival code, shown to the OFFICE — 19 Aug 2026.
///
/// The arrival-code gate shipped without anywhere to read the code from,
/// which made it unusable in the field: the supervisor is asked for a
/// code, the office has no way to see it, and the job cannot start. This
/// closes that.
///
/// **Who sees it, and why that asymmetry is the whole design.** Owner and
/// manager only. It is deliberately NOT on the supervisor's own job
/// screen, because a code the supervisor can read proves nothing — that
/// was exactly the flaw in the OTP flow this replaced, where the app
/// generated a code and showed it to the person who was supposed to be
/// proving they had reached the customer. The office reads it to the
/// customer; the customer tells the crew; the crew types it. Each step
/// requires someone actually being where they claim to be.
///
/// So: if this widget ever gets reused on a supervisor-facing screen, the
/// feature is back to being decorative. The gate is enforced here as well
/// as at the call site for that reason.
class ArrivalCodeCard extends StatefulWidget {
  const ArrivalCodeCard({super.key, required this.orderId});

  final String orderId;

  @override
  State<ArrivalCodeCard> createState() => ArrivalCodeCardState();
}

class ArrivalCodeCardState extends State<ArrivalCodeCard> {
  bool _loading = true;
  String? _code;
  String? _status;
  String? _supervisorStatus;
  String? _phone;
  String? _customer;
  String? _token;

  /// Sends the customer their booking confirmation: order id, the code,
  /// and their tracking link (13 Nov 2026, Arun's report 6.1: "Include
  /// the OTP in the customer's order confirmation... Share the document
  /// with the customer"). One tap from where the office reads the code.
  Future<void> _share() async {
    final code = (_code ?? '').trim();
    if (code.isEmpty) return;
    var token = _token;
    try {
      token ??= await TrackingService.tokenForOrder(widget.orderId);
    } catch (_) {}
    if (!mounted) return;
    final link = token == null ? '' : buildTokenLink('/track', token);
    await ShareLinkSheet.show(
      context,
      title: 'Send booking confirmation',
      subtitle: 'The customer gets the order number, their arrival code '
          'and their tracking link.',
      link: link,
      phone: _phone,
      message: 'Hello${(_customer ?? '').isEmpty ? '' : ' $_customer'}, '
          'your order ${widget.orderId} with ${VendorIdentity.forSentence} '
          'is confirmed.\n\n'
          'Your arrival code: $code\n'
          'Give this code to our supervisor only when the team reaches '
          'your pickup address on shifting day.\n\n'
          'Track your move and approve any extra charges here:',
    );
  }

  /// Owner, manager or admin — the same set `is_org_manager()` uses in
  /// SQL.
  ///
  /// This originally carried its own role check because
  /// `isOwnerOrManagerSession` omitted 'admin', which is the role the
  /// staff form actually offers. That getter was fixed on 19 Aug 2026,
  /// so this now defers to it: one definition of "owner-level session",
  /// not two that can drift apart.
  bool get _canSee => isOwnerOrManagerSession;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    if (!_canSee) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId),
      );
      if (!mounted) return;
      setState(() {
        if (rows.isNotEmpty) {
          _code = rows.first.arrivalCode;
          _status = (rows.first.status ?? '').toLowerCase();
          _supervisorStatus = rows.first.supervisorStatus;
          _phone = rows.first.phone;
          _customer = rows.first.customer;
          _token = rows.first.trackingToken;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _alreadyUsed =>
      (_supervisorStatus ?? '').isNotEmpty ||
      _status == 'transit' ||
      _status == 'delivered';

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    if (!_canSee || _loading) return const SizedBox.shrink();

    // A closed or cancelled job's code is spent and only adds noise.
    if (_status == 'closed' || _status == 'cancelled') {
      return const SizedBox.shrink();
    }
    final code = (_code ?? '').trim();
    if (code.isEmpty) return const SizedBox.shrink();

    final muted = _alreadyUsed;
    final accent = muted ? c.mute : c.acc;

    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                        muted
                            ? Icons.check_circle_outline_rounded
                            : Icons.key_rounded,
                        size: 18,
                        color: accent),
                    const SizedBox(width: 8),
                    Text('Arrival code',
                        style: NgFonts.geist(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.text)),
                    if (muted) ...[
                      const SizedBox(width: 8),
                      const NgPill('Already used'),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // Mono + wide spacing: this gets read aloud down a phone
                // line, so the digits have to be unambiguous.
                Text(code.split('').join(' '),
                    style: NgFonts.mono(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 4,
                      color: muted ? c.mute : c.text,
                    )),
                const SizedBox(height: 6),
                Text(
                  muted
                      ? 'This job has already been started with this code.'
                      : 'Send this to the customer now. On shifting day they '
                          'give it to the supervisor, who types it in to '
                          'start the job. The supervisor cannot see it, '
                          'which is what proves the crew arrived.',
                  style: NgFonts.geist(
                      fontSize: 12.5, color: c.mute, height: 1.4),
                ),
                if (!muted) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send to customer'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          NgHeaderButtonBox(
            icon: Icons.content_copy_rounded,
            tooltip: 'Copy',
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Arrival code copied.')));
            },
          ),
        ],
      ),
    );
  }
}
