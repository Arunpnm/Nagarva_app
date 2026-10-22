import 'package:flutter/material.dart';
import '/components/ng_widgets.dart';

import '/backend/lead_stage_evidence.dart';
import '/backend/lead_status.dart';
import '/flutter_flow/ng_tokens.dart';

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
    this.evidence = const LeadStageEvidence(),
    this.onStageTap,
    this.onMarkLost,
    this.busy = false,
    this.compact = false,
  });

  /// Claude Design handoff: five segmented bars with labels, no card or
  /// heading — for Lead Details, where the status pill already sits in
  /// the header. Same evidence rules as the full strip.
  final bool compact;

  final String? status;

  /// What each stage can point at as PROOF it happened.
  ///
  /// Before 12 Sept 2026 the strip had none of this and derived every
  /// stage from [status] alone, so reaching `quoted` ticked SURVEY on
  /// leads that were never surveyed — two of the six confirmed leads, in
  /// live data. See [LeadStageEvidence]; the fix is that each stage reads
  /// its own record, not that the tick was restyled.
  ///
  /// Defaults to empty, which renders evidence-backed stages as skipped
  /// rather than done. That default is deliberate: a caller that forgets
  /// to pass evidence understates progress instead of inventing it.
  final LeadStageEvidence evidence;

  /// Manual override (item 5.3). Null makes the strip read-only.
  final ValueChanged<String>? onStageTap;

  /// Separate from [onStageTap] because `lost` needs a confirm dialog and
  /// is not part of the linear pipeline.
  final VoidCallback? onMarkLost;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    final canonical = canonicalLeadStatus(status);
    final currentIdx = leadStageIndex(canonical);
    final isLost = canonical == kLeadStatusLost;

    if (compact) {
      if (isLost) {
        return _LostBanner(
            onReopen: () => onStageTap?.call(kLeadStatusFollowUp));
      }
      return _SegmentRow(currentIdx: currentIdx, evidence: evidence,
          status: canonical);
    }

    return NgCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Pipeline',
                style: NgFonts.geist(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: ng.text,
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
            _ProgressRow(
                currentIdx: currentIdx, evidence: evidence, onStageTap: null),
          if (!isLost && onMarkLost != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : onMarkLost,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: leadStatusColor(kLeadStatusLost, context),
                ),
                child: Text(
                  'Mark as lost',
                  style: NgFonts.geist(
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

class _SegmentRow extends StatelessWidget {
  const _SegmentRow(
      {required this.currentIdx, required this.evidence, required this.status});

  final int currentIdx;
  final LeadStageEvidence evidence;
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final color = c.status(leadStatusTone(status)).fg;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kLeadPipeline.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: Builder(builder: (context) {
              final st = leadStageState(
                stage: kLeadPipeline[i],
                stageIdx: i,
                currentIdx: currentIdx,
                evidence: evidence,
              );
              final reached = st == LeadStageState.done ||
                  st == LeadStageState.current;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      // Skipped: passed without happening, so a faded
                      // bar rather than a solid one (see _Stage).
                      color: reached
                          ? color
                          : st == LeadStageState.skipped
                              ? color.withValues(alpha: 0.3)
                              : c.w07,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    leadStageShortLabel(kLeadPipeline[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                      fontSize: 12.5,
                      fontWeight: st == LeadStageState.current
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: reached ? c.text : c.mute,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow(
      {required this.currentIdx, required this.evidence, this.onStageTap});

  final int currentIdx;
  final LeadStageEvidence evidence;
  final ValueChanged<String>? onStageTap;

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kLeadPipeline.length; i++) ...[
          Expanded(
            child: _Stage(
              label: leadStageShortLabel(kLeadPipeline[i]),
              state: leadStageState(
                stage: kLeadPipeline[i],
                stageIdx: i,
                currentIdx: currentIdx,
                evidence: evidence,
              ),
              color: leadStatusColor(kLeadPipeline[i], context),
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
                // A SKIPPED stage does not draw a solid connector — the
                // line is the visual claim that the chain is unbroken,
                // and a skipped stage is exactly where it is not.
                color: leadStageState(
                          stage: kLeadPipeline[i],
                          stageIdx: i,
                          currentIdx: currentIdx,
                          evidence: evidence,
                        ) ==
                        LeadStageState.done
                    ? leadStatusColor(kLeadPipeline[i], context)
                    : ng.w08,
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
    required this.state,
    required this.color,
    this.onTap,
  });

  final String label;

  /// Computed from evidence, not from position — see [leadStageState].
  final LeadStageState state;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ng = NgPalette.of(context);
    final done = state == LeadStageState.done;
    final current = state == LeadStageState.current;
    final skipped = state == LeadStageState.skipped;

    // A skipped stage reads as PASSED WITHOUT HAPPENING: filled in the
    // stage colour so it does not look unreached, but hollow-centred with
    // a dash instead of a tick, and muted. It must not look like a tick
    // (that was the lie) and must not look like an empty future stage
    // (that reads as the lead having gone backwards).
    final active = done || current || skipped;
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
                color: skipped
                    ? ng.s1
                    : (active ? color : ng.w08),
                shape: BoxShape.circle,
                border: current
                    ? Border.all(color: color.withValues(alpha: 0.35), width: 3)
                    : skipped
                        ? Border.all(
                            color: color.withValues(alpha: 0.55), width: 2)
                        : null,
              ),
              child: done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : skipped
                      ? Icon(Icons.remove,
                          size: 11, color: color.withValues(alpha: 0.8))
                      : null,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(
                fontSize: 10.5,
                height: 1.15,
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                color: skipped
                    ? ng.mute
                    : (active ? ng.text : ng.mute),
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
    final color = leadStatusColor(status, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        leadStatusLabel(status),
        style: NgFonts.geist(
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
    final color = leadStatusColor(kLeadStatusLost, context);
    return Row(
      children: [
        Icon(Icons.cancel_outlined, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'This lead is marked lost.',
            style: NgFonts.geist(
                fontSize: 12.5, color: NgPalette.of(context).mute),
          ),
        ),
        TextButton(
          onPressed: onReopen,
          style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
          child: Text('Reopen',
              style: NgFonts.geist(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
