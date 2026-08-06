import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/lead_status.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Lead pipeline progress strip + tappable stage chips.
///
/// Live-test fix brief #2, item 5.3/5.4 — visual parity with the APC web
/// app's New / Follow Up / Survey / Quoted / Order strip. Nagarva only had
/// a static "new" badge that never advanced.
///
/// Purely presentational: it renders [status] and reports taps through
/// [onStageTap] / [onMarkLost]. All persistence stays in the page so the
/// optimistic-update + rollback logic lives in one place.
class LeadStatusStrip extends StatelessWidget {
  const LeadStatusStrip({
    super.key,
    required this.status,
    this.onStageTap,
    this.onMarkLost,
    this.busy = false,
  });

  final String? status;

  /// Manual override (item 5.3). Null makes the strip read-only.
  final ValueChanged<String>? onStageTap;

  /// Separate from [onStageTap] because `lost` needs a confirm dialog and
  /// is not part of the linear pipeline.
  final VoidCallback? onMarkLost;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final canonical = canonicalLeadStatus(status);
    final currentIdx = leadStageIndex(canonical);
    final isLost = canonical == kLeadStatusLost;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Pipeline',
                style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: theme.primaryText,
                ),
              ),
              const Spacer(),
              if (busy)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _StatusPill(status: canonical),
            ],
          ),
          const SizedBox(height: 12),
          if (isLost)
            _LostBanner(onReopen: () => onStageTap?.call(kLeadStatusFollowUp))
          else
            // Session 4, A3: the freely-tappable status chips above this
            // strip are now the one interactive control for lead status —
            // the strip itself is a read-only mirror of that state, so
            // there's no longer a second, independent way to change it
            // from the same screen. onStageTap is still accepted (and
            // still used by the Lost banner's Reopen button above) but no
            // longer wired to per-stage taps here.
            _ProgressRow(currentIdx: currentIdx, onStageTap: null),
          if (!isLost && onMarkLost != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : onMarkLost,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: leadStatusColor(kLeadStatusLost),
                ),
                child: Text(
                  'Mark as lost',
                  style: GoogleFonts.inter(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.currentIdx, this.onStageTap});

  final int currentIdx;
  final ValueChanged<String>? onStageTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kLeadPipeline.length; i++) ...[
          Expanded(
            child: _Stage(
              label: leadStageShortLabel(kLeadPipeline[i]),
              done: i < currentIdx,
              current: i == currentIdx,
              color: leadStatusColor(kLeadPipeline[i]),
              onTap: onStageTap == null
                  ? null
                  : () => onStageTap!(kLeadPipeline[i]),
            ),
          ),
          if (i < kLeadPipeline.length - 1)
            Padding(
              // Nudged down to sit level with the dots, not the labels.
              padding: const EdgeInsets.only(top: 13),
              child: Container(
                width: 12,
                height: 2,
                color: i < currentIdx
                    ? leadStatusColor(kLeadPipeline[i])
                    : theme.alternate,
              ),
            ),
        ],
      ],
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.label,
    required this.done,
    required this.current,
    required this.color,
    this.onTap,
  });

  final String label;
  final bool done;
  final bool current;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final active = done || current;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      // 48dp minimum touch target, same rule as the nav items.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: current ? 26 : 20,
              height: current ? 26 : 20,
              decoration: BoxDecoration(
                color: active ? color : theme.alternate,
                shape: BoxShape.circle,
                border: current
                    ? Border.all(color: color.withValues(alpha: 0.35), width: 3)
                    : null,
              ),
              child: done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                height: 1.15,
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                color: active ? theme.primaryText : theme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = leadStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        leadStatusLabel(status),
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _LostBanner extends StatelessWidget {
  const _LostBanner({required this.onReopen});

  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final color = leadStatusColor(kLeadStatusLost);
    return Row(
      children: [
        Icon(Icons.cancel_outlined, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'This lead is marked lost.',
            style: GoogleFonts.inter(
                fontSize: 12.5, color: FlutterFlowTheme.of(context).secondaryText),
          ),
        ),
        TextButton(
          onPressed: onReopen,
          style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
          child: Text('Reopen',
              style: GoogleFonts.inter(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
