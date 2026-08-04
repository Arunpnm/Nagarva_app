import 'package:flutter/material.dart';

/// An icon with an optional unread-style count badge on its top-right.
///
/// Deliberately generic — it takes a [count] and knows nothing about what
/// is being counted. Which nav destination gets which count is decided at
/// the nav render sites (`main.dart`'s sidebar rail and
/// `mobile_bottom_nav.dart`), so this widget stays reusable if a second
/// queue ever needs a badge.
///
/// Renders the bare [Icon] unchanged when [count] is 0, so a badge-less
/// destination is pixel-identical to before this existed.
class NavBadgeIcon extends StatelessWidget {
  const NavBadgeIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
    required this.count,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final base = Icon(icon, size: size, color: color);
    if (count <= 0) return base;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          right: -5,
          top: -3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 15),
            decoration: BoxDecoration(
              // Gold, matching the "⏳ Awaiting" badge the supervisor sees
              // on the same job in My Jobs — the two ends of one workflow
              // should read as the same state.
              color: const Color(0xFFE0A82E),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
