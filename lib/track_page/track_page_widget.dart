import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/backend/order_stages.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Public, unauthenticated order-tracking page (live-test fix brief #2,
/// item 6). Reached via `/track?token=...` with no login.
///
/// Read-only, and reads go through the `track-order` Edge Function rather
/// than a direct query — `get_order_tracking` is granted to service_role
/// only, so anon RLS on `orders` stays closed. Crew details are gated
/// inside the RPC (on the org's `tracking_show_crew` setting), not here,
/// so nothing this file does can widen what is exposed.
class TrackPageWidget extends StatefulWidget {
  const TrackPageWidget({super.key, this.token});

  final String? token;

  static String routeName = 'TrackPage';
  static String routePath = '/track';

  @override
  State<TrackPageWidget> createState() => _TrackPageWidgetState();
}

class _TrackPageWidgetState extends State<TrackPageWidget> {
  // null = loading, 'ok', 'invalid', 'error'
  String? _state;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() => _state = 'invalid');
      return;
    }
    try {
      final res = await SupaFlow.client.functions.invoke(
        'track-order',
        body: {'token': token},
      );
      final data = res.data;
      if (data is! Map || data['orderRef'] == null) {
        setState(() => _state = 'invalid');
        return;
      }
      setState(() {
        _data = Map<String, dynamic>.from(data);
        _state = 'ok';
      });
    } catch (e) {
      // `invoke` throws FunctionException on any non-2xx response (17 Aug
      // 2026 finding) — track-order returns 404 for an invalid/expired
      // token, which used to land here as a generic 'error' ("Pull down
      // to try again"), the wrong message for a link that will never
      // resolve no matter how many times it's retried.
      final status = e is FunctionException ? e.status : null;
      setState(() => _state = status == 404 ? 'invalid' : 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: RefreshIndicator(
              onRefresh: _load,
              child: _body(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    if (_state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_state == 'invalid' || _state == 'error') {
      return ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 80),
          Icon(
            _state == 'invalid' ? Icons.link_off : Icons.wifi_off,
            size: 52,
            color: theme.primary,
          ),
          const SizedBox(height: 18),
          Text(
            _state == 'invalid'
                ? 'This tracking link is not valid'
                : 'Could not load tracking',
            textAlign: TextAlign.center,
            style: GoogleFonts.interTight(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: theme.primaryText),
          ),
          const SizedBox(height: 10),
          Text(
            _state == 'invalid'
                ? 'It may have expired. Please ask for a fresh link.'
                : 'Pull down to try again.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 14, height: 1.45, color: theme.secondaryText),
          ),
        ],
      );
    }

    final d = _data!;
    final history = d['history'] is List ? d['history'] as List : const [];
    final currentIdx = orderStageIndex(
      d['trackingStage'] as String?,
      d['status'] as String?,
    );
    final crew = d['crew'] is Map
        ? Map<String, dynamic>.from(d['crew'] as Map)
        : null;

    // Latest timestamp per stage, for the timeline's per-stage dates.
    final stageTimes = <String, DateTime>{};
    for (final h in history) {
      if (h is! Map) continue;
      final stage = canonicalOrderStage(h['status'] as String?);
      final at = DateTime.tryParse((h['changed_at'] as String?) ?? '');
      if (stage != null && at != null) stageTimes[stage] = at;
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          (d['orgName'] as String?) ?? 'Your move',
          style: GoogleFonts.interTight(
              fontSize: 13, fontWeight: FontWeight.w600, color: theme.primary),
        ),
        const SizedBox(height: 4),
        Text(
          'Order ${d['orderRef']}',
          style: GoogleFonts.interTight(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.primaryText),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _line(context, 'From', d['fromCity'] as String?),
              _line(context, 'To', d['toCity'] as String?),
              _line(context, 'Move date', _fmtDate(d['moveDate'] as String?)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Progress',
          style: GoogleFonts.interTight(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.primaryText),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < kOrderStages.length; i++)
          _timelineRow(
            context,
            label: orderStageLabel(kOrderStages[i]),
            done: i < currentIdx,
            current: i == currentIdx,
            isLast: i == kOrderStages.length - 1,
            at: stageTimes[kOrderStages[i]],
          ),
        if (crew != null &&
            (crew['vehicle'] != null ||
                crew['driver'] != null ||
                crew['phone'] != null)) ...[
          const SizedBox(height: 22),
          Text(
            'Your crew',
            style: GoogleFonts.interTight(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: theme.primaryText),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _line(context, 'Vehicle', crew['vehicle'] as String?),
                _line(context, 'Driver', crew['driver'] as String?),
                _line(context, 'Contact', crew['phone'] as String?),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),
        Center(
          child: Text(
            'Pull down to refresh',
            style:
                GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  static String? _fmtDate(String? iso) {
    if (iso == null) return null;
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('d MMM yyyy').format(d);
  }

  Widget _timelineRow(
    BuildContext context, {
    required String label,
    required bool done,
    required bool current,
    required bool isLast,
    DateTime? at,
  }) {
    final theme = FlutterFlowTheme.of(context);
    final active = done || current;
    final color = active ? theme.tertiary : theme.alternate;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: current ? 20 : 15,
                height: current ? 20 : 15,
                decoration: BoxDecoration(
                  color: active ? color : theme.alternate,
                  shape: BoxShape.circle,
                  border: current
                      ? Border.all(
                          color: color.withValues(alpha: 0.35), width: 3)
                      : null,
                ),
                child: done
                    ? const Icon(Icons.check, size: 10, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? color : theme.alternate,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                      color:
                          active ? theme.primaryText : theme.secondaryText,
                    ),
                  ),
                  if (at != null)
                    Text(
                      DateFormat('d MMM, h:mm a').format(at.toLocal()),
                      style: GoogleFonts.inter(
                          fontSize: 11.5, color: theme.secondaryText),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String? value) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 13, color: theme.secondaryText)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              (value == null || value.trim().isEmpty) ? '—' : value.trim(),
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: theme.primaryText),
            ),
          ),
        ],
      ),
    );
  }
}
