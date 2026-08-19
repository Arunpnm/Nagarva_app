import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
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

  /// Owner, manager or admin. `isOwnerOrManagerSession` alone is not
  /// enough: it tests for the literal roles 'owner'/'manager', while the
  /// staff form actually offers 'admin' as the owner-equivalent role (see
  /// permissions.dart, and is_org_manager() in SQL, which includes all
  /// three). An admin-role session would otherwise be locked out of a
  /// screen they administer.
  bool get _canSee {
    if (AppSession.instance.currentStaffId == null) return true; // vendor
    final role = AppSession.instance.currentStaffRole;
    return role == 'owner' || role == 'manager' || role == 'admin';
  }

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
    final theme = FlutterFlowTheme.of(context);
    if (!_canSee || _loading) return const SizedBox.shrink();

    // A closed or cancelled job's code is spent and only adds noise.
    if (_status == 'closed' || _status == 'cancelled') {
      return const SizedBox.shrink();
    }
    final code = (_code ?? '').trim();
    if (code.isEmpty) return const SizedBox.shrink();

    final muted = _alreadyUsed;
    final accent = muted ? theme.secondaryText : theme.primary;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: muted ? 0.25 : 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(muted ? Icons.check_circle_outline : Icons.vpn_key_outlined,
                  size: 18, color: accent),
              const SizedBox(width: 8),
              Text('Arrival code',
                  style: GoogleFonts.interTight(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryText)),
              const Spacer(),
              if (muted)
                Text('Already used',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: theme.secondaryText)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Monospace + wide spacing: this gets read aloud down a
              // phone line, so the digits have to be unambiguous.
              Text(
                code.split('').join(' '),
                style: GoogleFonts.robotoMono(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.content_copy, size: 18, color: accent),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Arrival code copied.')));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            muted
                ? 'This job has already been started with this code.'
                : 'Read this to the customer when the crew reaches the '
                    'address. The supervisor types it in to start the job — '
                    'they cannot see it themselves, which is what makes it '
                    'proof the crew actually arrived.',
            style: GoogleFonts.inter(
                fontSize: 11.5, color: theme.secondaryText, height: 1.35),
          ),
        ],
      ),
    );
  }
}
