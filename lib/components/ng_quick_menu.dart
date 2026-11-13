import 'package:flutter/material.dart';

import '/flutter_flow/ng_tokens.dart';

/// Shared look for the small header menus (theme, language), 13 Nov 2026.
///
/// Arun: the two menus "are not matching, too huge and odd". They were
/// stock Material popups, one with ticks on the left and one with radio
/// buttons. Both now use this: a compact rounded card, 40px rows, the
/// same type size, and one tick on the right for the current choice.
class NgQuickMenu {
  NgQuickMenu._();

  static const double width = 184;

  static ShapeBorder shape(BuildContext context) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: NgPalette.of(context).w08),
      );

  static const constraints = BoxConstraints(minWidth: width, maxWidth: width);

  static AnimationStyle get animation => AnimationStyle(
        duration: const Duration(milliseconds: 170),
        reverseDuration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
      );

  static PopupMenuEntry<T> header<T>(BuildContext context, String text) =>
      PopupMenuItem<T>(
        enabled: false,
        height: 26,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
        child: Text(text.toUpperCase(),
            style: NgFonts.geist(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.9,
                color: NgPalette.of(context).mute)),
      );

  static PopupMenuEntry<T> item<T>(
    BuildContext context, {
    required T value,
    required String label,
    required bool selected,
    IconData? icon,
    Widget? trailingTag,
  }) {
    final c = NgPalette.of(context);
    return PopupMenuItem<T>(
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? c.accBtn.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: selected ? c.acc : c.mute),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? c.acc : c.text)),
            ),
            if (trailingTag != null) trailingTag,
            const Spacer(),
            if (selected) Icon(Icons.check_rounded, size: 17, color: c.acc),
          ],
        ),
      ),
    );
  }
}
