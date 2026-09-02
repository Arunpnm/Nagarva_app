import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/main.dart' show MyApp;

/// Always-visible theme switcher for the app bar.
///
/// Arun, 2 Sept 2026: theme should not be buried in Settings — a vendor
/// working outdoors in daylight, or at night in a customer's flat, wants
/// it in one tap from wherever they already are.
///
/// **Theme only, deliberately — language is NOT here.** The same request
/// asked for the language picker to move up here too, and it was held
/// back on purpose: `app_ta.arb`, `app_hi.arb` and `app_kn.arb` contain
/// **zero message keys** against `app_en.arb`'s 487, so every lookup
/// falls through to English. Selecting தமிழ் highlights the chip and
/// changes nothing on screen — verified on device 2 Sept 2026. Promoting
/// a control that visibly does nothing, onto every screen, reads as a
/// broken product rather than an unfinished one. Language stays in
/// Settings until the ARB files are actually translated; move it here in
/// the same change that fills them, not before.
///
/// Reuses `MyApp.of(context).setThemeVariant` and
/// `FlutterFlowTheme.effectiveVariant` rather than holding any state of
/// its own — the sidebar rail, the supervisor overflow menu and the
/// Settings chips all drive the same two calls, so all four stay in step
/// by construction.
///
/// Add to a screen's `AppBar.actions`. Renders the CURRENT theme's icon
/// so the control also reports state, not just offers it.
class ThemeQuickButton extends StatelessWidget {
  const ThemeQuickButton({super.key, this.iconColor});

  /// Matches the sibling actions' colour. Pass
  /// `IconTheme.of(context).color` so it tracks the AppBar's own
  /// IconTheme across light/dark/midnight instead of hardcoding one.
  final Color? iconColor;

  static const _variants = <(String, String, IconData)>[
    ('light', 'Light', Icons.light_mode_outlined),
    ('dark', 'Dark', Icons.dark_mode_outlined),
    ('midnight', 'Midnight', Icons.nights_stay_outlined),
  ];

  static IconData _iconFor(String variant) =>
      _variants.firstWhere((v) => v.$1 == variant,
          orElse: () => _variants.first).$3;

  @override
  Widget build(BuildContext context) {
    final current = FlutterFlowTheme.effectiveVariant(context);
    return PopupMenuButton<String>(
      tooltip: 'Theme',
      icon: Icon(_iconFor(current),
          color: iconColor ?? IconTheme.of(context).color),
      onSelected: (value) => MyApp.of(context).setThemeVariant(value),
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child:
              Text('THEME', style: TextStyle(fontSize: 11, letterSpacing: 1)),
        ),
        for (final (value, label, icon) in _variants)
          CheckedPopupMenuItem<String>(
            value: value,
            checked: current == value,
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 10),
                Text(label),
              ],
            ),
          ),
      ],
    );
  }
}
