import 'package:flutter/material.dart';

import '/app_session.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/l10n/gen/app_localizations.dart';
import '/plan_page/plan_page_widget.dart';

/// Dashboard pieces from the Claude Design handoff's "DASHBOARD A : Focus"
/// that hold no data of their own. HomePage loads the rows and passes
/// them in, so these stay pure layout and the page keeps one load path.

/// Plan card: plan name, a status pill, the expiry line, a CTA and a bar
/// showing how much of the period is left.
///
/// Owner sessions only. Plan and billing are owner-only in the handoff's
/// role table, and the plan columns are written only by Super Admin and
/// signup RPCs (20261021_org_plan_column_lockdown.sql), so a staff session
/// has nothing it could do from this card.
///
/// Subscription billing is on hold (Item 31), so a paid plan has no
/// renewal date to show. The card says "No expiry date" rather than
/// inventing one, and the button opens the plans page instead of a
/// checkout that does not exist.
class DashPlanCard extends StatelessWidget {
  const DashPlanCard({super.key});

  /// Length of the trial for the progress bar. The trial's real start is
  /// not stored; 30 days matches `subscription_plans.trial_days` today.
  static const _kTrialDays = 30;

  @override
  Widget build(BuildContext context) {
    final s = AppSession.instance;
    if (s.currentStaffId != null) return const SizedBox.shrink();
    final plan = (s.planName ?? '').trim();
    if (plan.isEmpty) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final c = NgPalette.of(context);
    final onTrial = s.planStatus == 'trial' && s.trialEndsAt != null;

    String name = l.ngPlanName(plan);
    String pill = l.ngPlanActive;
    NgStatus tone = NgStatus.green;
    String line = l.ngPlanNoExpiry;
    double left = 1;

    if (onTrial) {
      final days = s.trialDaysRemaining;
      name = '$plan · ${l.ngPlanTrial}';
      if (!s.isTrialExpired) {
        pill = days <= 3 ? l.ngPlanEndingSoon : l.ngPlanTrial;
        tone = days <= 3 ? NgStatus.amber : NgStatus.blue;
        line = l.ngPlanTrialEnds(
            DateFormat('d MMM yyyy').format(s.trialEndsAt!.toLocal()),
            days < 0 ? 0 : days);
        left = (days / _kTrialDays).clamp(0.04, 1.0);
      } else {
        pill = l.ngPlanEnded;
        tone = NgStatus.red;
        line = s.isInTrialGrace
            ? l.ngPlanReadOnlyIn(s.daysUntilReadOnly.clamp(0, 999))
            : l.ngPlanReadOnly;
        left = 0.04;
      }
    }
    final st = c.status(tone);

    void open() => context.pushNamed(PlanPageWidget.routeName);
    return NgCard(
      onTap: open,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NgIconTile(
                  icon: Icons.workspace_premium_outlined,
                  status: tone,
                  size: 36,
                  iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NgFonts.geist(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.text)),
                        ),
                        const SizedBox(width: 6),
                        NgPill(pill, status: tone),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NgPrimaryButton(
                  label: l.ngPlanSee, onPressed: open, compact: true, height: 34),
            ],
          ),
          const SizedBox(height: 10),
          NgProgressBar(value: left, color: st.fg, height: 4),
        ],
      ),
    );
  }
}

/// One-line summary card (the handoff's dashboard "widgets": Payments
/// due, Fleet status, Staff attendance): icon tile, label over a figure,
/// muted note on the right.
class DashInfoRow extends StatelessWidget {
  const DashInfoRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.note,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return NgCard(
      onTap: onTap,
      child: Row(
        children: [
          NgIconTile(icon: icon, color: iconColor, size: 38, iconSize: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: NgFonts.geist(fontSize: 13, color: c.mute)),
                const SizedBox(height: 2),
                Text(value,
                    style: NgFonts.geist(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
              ],
            ),
          ),
          if ((note ?? '').isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.4),
              child: Text(note!,
                  textAlign: TextAlign.right,
                  style: NgFonts.geist(fontSize: 12, color: c.mute)),
            ),
        ],
      ),
    );
  }
}

/// One row of "Today's plan".
class DashAgendaItem {
  const DashAgendaItem({
    required this.time,
    this.ampm = '',
    required this.icon,
    required this.tone,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  /// "8:00", or a day label when the item has no time.
  final String time;
  final String ampm;
  final IconData icon;
  final NgStatus tone;
  final String title;
  final String sub;
  final VoidCallback onTap;
}

/// "Today's plan": time column, tinted icon tile, title and subtitle,
/// chevron, hairline-divided inside one card. [later] renders under a
/// "Coming up" caption in the same card, so moves booked for the next
/// days stay on the dashboard without a second section.
class DashAgenda extends StatelessWidget {
  const DashAgenda({
    super.key,
    required this.today,
    required this.later,
    this.emptyAction,
  });

  final List<DashAgendaItem> today;
  final List<DashAgendaItem> later;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = NgPalette.of(context);
    Widget row(DashAgendaItem a) => InkWell(
          onTap: a.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Column(
                    children: [
                      Text(a.time,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: NgFonts.mono(
                              fontSize: a.ampm.isEmpty ? 11 : 14,
                              fontWeight: FontWeight.w600,
                              color: c.text)),
                      if (a.ampm.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(a.ampm,
                            style:
                                NgFonts.geist(fontSize: 10.5, color: c.faint)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                NgIconTile(icon: a.icon, status: a.tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NgFonts.geist(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: c.text)),
                      const SizedBox(height: 2),
                      Text(a.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              NgFonts.geist(fontSize: 12.5, color: c.mute)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NgSectionHeader(l.ngTodaysPlan, trailing: '${today.length}'),
        const SizedBox(height: 10),
        if (today.isEmpty && later.isEmpty)
          NgCard(
            child: Column(
              children: [
                Icon(Icons.event_available_outlined, size: 26, color: c.faint),
                const SizedBox(height: 8),
                Text(l.ngNothingToday,
                    style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                if (emptyAction != null) ...[
                  const SizedBox(height: 10),
                  emptyAction!,
                ],
              ],
            ),
          )
        else
          NgCardList(children: [
            if (today.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(l.ngNothingToday,
                    style: NgFonts.geist(fontSize: 13, color: c.mute)),
              ),
            for (final a in today) row(a),
            if (later.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Text(l.ngComingUp.toUpperCase(),
                    style: NgFonts.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.88,
                        color: c.faint)),
              ),
            for (final a in later) row(a),
          ]),
      ],
    );
  }
}

/// "This month" panel: header with a period picker, the target block,
/// the KPI grid, and the profit row under it.
class DashMonthPanel extends StatelessWidget {
  const DashMonthPanel({
    super.key,
    required this.title,
    required this.periodLabel,
    required this.onPickPeriod,
    required this.target,
    required this.grid,
    required this.profit,
  });

  final String title;
  final String periodLabel;
  final VoidCallback onPickPeriod;
  final Widget? target;
  final Widget grid;
  final Widget? profit;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: NgFonts.geist(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
              ),
              InkWell(
                onTap: onPickPeriod,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(periodLabel,
                          style: NgFonts.geist(fontSize: 13, color: c.mute)),
                      const SizedBox(width: 2),
                      Icon(Icons.expand_more_rounded,
                          size: 18, color: c.mute),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        NgCard(
          radius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (target != null) ...[target!, const SizedBox(height: 16)],
              grid,
              if (profit != null) ...[const SizedBox(height: 12), profit!],
            ],
          ),
        ),
      ],
    );
  }
}

/// The target block at the top of [DashMonthPanel]: label and percent,
/// the figure over the target, and a bar.
class DashTargetBlock extends StatelessWidget {
  const DashTargetBlock({
    super.key,
    required this.label,
    required this.value,
    this.target,
    required this.fraction,
    required this.percentLabel,
    this.barColor,
    this.note,
    this.onTap,
  });

  final String label;
  final String value;

  /// "/ ₹3.00L" after the figure. Null when [value] is the target itself
  /// or a prompt, which then renders smaller.
  final String? target;
  final double fraction;
  final String percentLabel;
  final Color? barColor;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: NgFonts.geist(fontSize: 13, color: c.mute))),
              Text(percentLabel,
                  style: NgFonts.geist(fontSize: 13, color: c.mute)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                        fontSize: target == null && value.length > 12 ? 17 : 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.52,
                        color: c.text)),
              ),
              if (target != null) ...[
                const SizedBox(width: 6),
                Text('/ $target',
                    style: NgFonts.geist(fontSize: 14, color: c.faint)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          NgProgressBar(value: fraction, color: barColor ?? c.accBtn),
          if ((note ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note!, style: NgFonts.geist(fontSize: 12, color: c.mute)),
          ],
        ],
      ),
    );
  }
}

/// Profit line under the grid. With a figure it is a plain row; without
/// one it is the handoff's dashed "needs expenses" prompt, which offers
/// the action that fixes it instead of showing a misleading number.
class DashProfitRow extends StatelessWidget {
  const DashProfitRow({
    super.key,
    required this.title,
    required this.sub,
    this.value,
    this.action,
    this.onTap,
  });

  final String title;
  final String sub;

  /// Null renders the dashed "unavailable" form.
  final String? value;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final empty = value == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: CustomPaint(
        painter: empty ? _DashedBorder(c.w12) : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: empty
              ? null
              : BoxDecoration(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(14),
                ),
          child: Row(
            children: [
              Icon(Icons.savings_outlined, size: 20, color: c.mute),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: NgFonts.geist(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: c.text)),
                    Text(sub,
                        style: NgFonts.geist(fontSize: 12, color: c.mute)),
                  ],
                ),
              ),
              if (!empty)
                Text(value!,
                    style: NgFonts.geist(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.green))
              else if (action != null)
                Text(action!,
                    style: NgFonts.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.acc)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(14)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
