import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/flutter_flow/ng_tokens.dart';

/// Building blocks of the redesign (Claude Design handoff, 20 Oct 2026).
///
/// Each one is a direct reading of a pattern the handoff repeats on every
/// screen — values (radius, padding, type size) come from it, not from
/// taste. Kept small and dumb: no data, no navigation, so a page can adopt
/// them one widget at a time without touching its queries.

/// Card: s1 surface, 1px w06 hairline, radius 18. No shadow — depth in
/// the redesign is surface steps and hairlines only.
class NgCard extends StatelessWidget {
  const NgCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = NgRadius.card,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: c.w06),
    );
    return Material(
      color: color ?? c.s1,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// Rows inside one card, separated by w06 hairlines (the agenda / list
/// pattern: `border-top` on every row but the first).
class NgCardList extends StatelessWidget {
  const NgCardList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return NgCard(
      padding: EdgeInsets.zero,
      radius: 20,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.w06),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Rounded-square icon tile (36–38px, radius 11–12). [status] picks a
/// tinted background with the matching hue; without it the tile is s3 with
/// [color] (or soft) for the icon.
class NgIconTile extends StatelessWidget {
  const NgIconTile({
    super.key,
    required this.icon,
    this.status,
    this.color,
    this.size = 36,
    this.iconSize = 19,
  });

  final IconData icon;
  final NgStatus? status;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final s = status == null ? null : c.status(status!);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: s?.bg ?? c.s3,
        borderRadius:
            BorderRadius.circular(size >= 38 ? 12 : NgRadius.iconTile),
      ),
      child: Icon(icon, size: iconSize, color: s?.fg ?? color ?? c.soft),
    );
  }
}

/// Status pill: 20–22px tall, radius 999, 11px semibold.
class NgPill extends StatelessWidget {
  const NgPill(this.label,
      {super.key, this.status = NgStatus.neutral, this.icon});

  final String label;
  final NgStatus status;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = NgPalette.of(context).status(status);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: s.fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            maxLines: 1,
            style: NgFonts.geist(
                fontSize: 11, fontWeight: FontWeight.w600, color: s.fg),
          ),
        ],
      ),
    );
  }
}

/// Section title row above a card: 16px semibold title, optional trailing
/// link in accent (e.g. "See all") or a muted count.
class NgSectionHeader extends StatelessWidget {
  const NgSectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.onTrailing,
  });

  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: NgFonts.geist(
                  fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
            ),
          ),
          if (trailing != null)
            GestureDetector(
              onTap: onTrailing,
              child: Text(
                trailing!,
                style: NgFonts.geist(
                  fontSize: 13,
                  fontWeight:
                      onTrailing != null ? FontWeight.w600 : FontWeight.w400,
                  color: onTrailing != null ? c.acc : c.mute,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Screen title block: 21px / 600 / −0.02em with an optional muted line
/// under it, and an optional trailing action (the per-screen "new" button
/// that replaced Quick Entry in the redesign).
class NgScreenTitle extends StatelessWidget {
  const NgScreenTitle(this.title,
      {super.key, this.subtitle, this.action, this.large = false});

  final String title;

  /// 26px, the handoff's size for the main tab screens (Leads, Orders,
  /// Operations, Payments, Staff...). Module screens keep 21px.
  final bool large;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: NgFonts.geist(
                    fontSize: large ? 26 : 21,
                    fontWeight: FontWeight.w600,
                    letterSpacing: large ? -0.52 : -0.42,
                    color: c.text,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: NgFonts.geist(fontSize: 13, color: c.mute),
                    ),
                  ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Filled accent button (46–52 tall, radius 14–16). Label is always the
/// near-black [NgPalette.onAcc], in every theme.
class NgPrimaryButton extends StatelessWidget {
  const NgPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 50,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  /// Header-sized: 36 tall, 13px label, hugs its content.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final h = compact ? 36.0 : height;
    final r = compact ? 11.0 : NgRadius.tile;
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: c.accBtn,
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(r),
          child: Container(
            height: h,
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: compact ? 18 : 20, color: NgPalette.onAcc),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w600,
                      color: NgPalette.onAcc,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary button: s2 fill, text colour, 42–44 tall.
class NgSecondaryButton extends StatelessWidget {
  const NgSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 42,
    this.iconColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Material(
      color: c.s2,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: iconColor ?? c.soft),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filter chip. Selected = background `text`, label inverted; otherwise
/// s1 with a w06 hairline and soft label. 34 tall, radius 999.
class NgChip extends StatelessWidget {
  const NgChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final fg = selected ? c.invText : c.soft;
    return Material(
      color: selected ? c.inv : c.s1,
      shape: StadiumBorder(side: BorderSide(color: selected ? c.inv : c.w06)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: NgFonts.geist(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: fg),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: NgFonts.geist(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: selected ? fg.withValues(alpha: 0.7) : c.faint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling chip row, bleeding to the screen edge.
class NgChipRow extends StatelessWidget {
  const NgChipRow({super.key, required this.chips, this.edge = 16});

  final List<Widget> chips;
  final double edge;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: edge),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            chips[i],
          ],
        ],
      ),
    );
  }
}

/// Small stat card: coloured icon on top, big number, muted label
/// (dashboard "today" row).
class NgStatTile extends StatelessWidget {
  const NgStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return NgCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color ?? c.acc),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NgFonts.geist(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.44,
              color: c.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NgFonts.geist(fontSize: 12.5, color: c.mute),
          ),
        ],
      ),
    );
  }
}

/// Search field: inset surface, w07 hairline, radius 13, 44 tall.
class NgSearchField extends StatelessWidget {
  const NgSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.w07),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: c.faint),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: NgFonts.geist(fontSize: 14, color: c.text),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint,
                hintStyle: NgFonts.geist(fontSize: 14, color: c.faint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circle initial avatar tinted by status (lead cards, hot leads).
class NgAvatar extends StatelessWidget {
  const NgAvatar(this.name,
      {super.key, this.status = NgStatus.neutral, this.size = 34});

  final String name;
  final NgStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = NgPalette.of(context).status(status);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: s.bg, shape: BoxShape.circle),
      child: Text(
        initial,
        style: NgFonts.geist(
            fontSize: size * 0.41, fontWeight: FontWeight.w600, color: s.fg),
      ),
    );
  }
}

/// Count badge pinned to the top-right of [child] (nav slot, menu tile).
/// Renders [child] alone when [count] is zero.
class NgCountBadge extends StatelessWidget {
  const NgCountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -2,
          right: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 16),
            height: 16,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NgPalette.badge,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: NgFonts.geist(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Thin progress bar (plan card, month target, order progress).
class NgProgressBar extends StatelessWidget {
  const NgProgressBar(
      {super.key, required this.value, this.color, this.height = 6});

  /// 0..1
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: c.w07)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color ?? c.accBtn,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented control (the handoff's Orders tabs, Payments Due/Received,
/// Operations Today/Tomorrow): an s1 track with 4px padding and equal
/// cells; the selected cell sits on `sel`.
class NgSegmented extends StatelessWidget {
  const NgSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.counts,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<int>? counts;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? c.sel : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NgFonts.geist(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: i == selected ? c.text : c.mute,
                          ),
                        ),
                      ),
                      if (counts != null) ...[
                        const SizedBox(width: 4),
                        Opacity(
                          opacity: 0.6,
                          child: Text(
                            '${counts![i]}',
                            style: NgFonts.mono(
                              fontSize: 11,
                              color: i == selected ? c.text : c.mute,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The handoff's 6-segment stage bar: done segments in the stage hue,
/// the rest on a w07 track.
class NgStageBar extends StatelessWidget {
  const NgStageBar({
    super.key,
    required this.done,
    required this.color,
    this.total = 6,
  });

  final int done;
  final Color color;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < done ? color : c.w07,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Title row for module screens (everything reached from More): a 40×40
/// back button, the 24px title with an optional muted line, and the
/// screen's own action on the right. Sits under [NgTopBar], as in the
/// handoff's Expenses / Fleet / Materials / Trips / Customers screens.
///
/// Back pops when there is somewhere to pop to. A module opened as a
/// tab (NavBarPage renders it in place) has nothing under it, so back
/// goes to the Dashboard instead of doing nothing.
class NgModuleHeader extends StatelessWidget {
  const NgModuleHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Overrides the default pop-or-go-home, for an in-page level such as
  /// a conversation opened from a list.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Material(
            color: c.s1,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onBack ??
                  () {
                final nav = Navigator.of(context);
                if (nav.canPop()) {
                  nav.pop();
                } else {
                  GoRouter.of(context).go('/home');
                }
              },
              child: Icon(Icons.arrow_back_rounded, size: 22, color: c.soft),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NgFonts.geist(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.48,
                  color: c.text,
                ),
              ),
              if ((subtitle ?? '').isNotEmpty)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 8), a],
      ],
    );
  }
}

/// List row inside an [NgCardList]: icon tile, title over a muted line,
/// trailing widget (amount, pill, chevron). The handoff's standard row.
class NgListRow extends StatelessWidget {
  const NgListRow({
    super.key,
    this.icon,
    this.iconStatus,
    this.leading,
    required this.title,
    this.titleTrailing,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData? icon;
  final NgStatus? iconStatus;
  final Widget? leading;
  final String title;
  final Widget? titleTrailing;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final lead = leading ??
        (icon == null ? null : NgIconTile(icon: icon!, status: iconStatus));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NgFonts.geist(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: c.text)),
                      ),
                      if (titleTrailing != null) ...[
                        const SizedBox(width: 6),
                        titleTrailing!,
                      ],
                    ],
                  ),
                  if ((subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(
                            fontSize: 12.5, height: 1.35, color: c.mute)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 40×40 square icon button for a module header (the handoff's settings /
/// import-export buttons beside the title).
class NgHeaderButtonBox extends StatelessWidget {
  const NgHeaderButtonBox({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final box = SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.w06),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Icon(icon, size: 20, color: c.soft),
        ),
      ),
    );
    return tooltip == null ? box : Tooltip(message: tooltip!, child: box);
  }
}

/// Top bar for detail and form screens (the handoff's Lead / Order detail
/// and New lead / New order): a 40×40 back (or close) button, a centred
/// title, and the screen's own actions on the right.
class NgSimpleBar extends StatelessWidget implements PreferredSizeWidget {
  const NgSimpleBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions = const [],
    this.close = false,
    this.mono = false,
    this.onBack,
  });

  final String? title;
  final Widget? titleWidget;
  final List<Widget> actions;

  /// Close (×) instead of back, for create forms.
  final bool close;

  /// Render the title in Geist Mono (record ids such as LD-1041).
  final bool mono;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final style = mono
        ? NgFonts.mono(fontSize: 13, color: c.mute)
        : NgFonts.geist(
            fontSize: 17, fontWeight: FontWeight.w600, color: c.text);
    return Material(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Material(
                    color: c.s1,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                      child: Icon(
                          close ? Icons.close_rounded : Icons.arrow_back_rounded,
                          size: 21,
                          color: c.soft),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: DefaultTextStyle.merge(
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: titleWidget ??
                          Text(title ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style),
                    ),
                  ),
                ),
                if (actions.isEmpty)
                  const SizedBox(width: 40)
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final a in actions)
                        IconTheme.merge(
                            data: IconThemeData(color: c.soft, size: 21),
                            child: a),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A [TabBar] dressed as the handoff's segmented control, for screens
/// that keep a [TabController] (swipe between tabs still works).
class NgTabBar extends StatelessWidget {
  const NgTabBar({
    super.key,
    required this.controller,
    required this.labels,
    this.scrollable = false,
  });

  final TabController controller;
  final List<String> labels;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: scrollable,
        tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: c.sel,
          borderRadius: BorderRadius.circular(10),
        ),
        labelColor: c.text,
        unselectedLabelColor: c.mute,
        labelStyle:
            NgFonts.geist(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            NgFonts.geist(fontSize: 13, fontWeight: FontWeight.w600),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        splashBorderRadius: BorderRadius.circular(10),
        tabs: [
          for (final l in labels) Tab(height: 36, text: l),
        ],
      ),
    );
  }
}
