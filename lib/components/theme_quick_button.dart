import 'package:flutter/material.dart';

import '/components/ng_quick_menu.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/ng_tokens.dart';
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
    final c = NgPalette.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Theme',
      // Compact shared menu (13 Nov 2026) - see NgQuickMenu.
      color: c.s1,
      elevation: 6,
      shape: NgQuickMenu.shape(context),
      constraints: NgQuickMenu.constraints,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      popUpAnimationStyle: NgQuickMenu.animation,
      icon: Icon(_iconFor(current),
          color: iconColor ?? IconTheme.of(context).color),
      onSelected: (value) => MyApp.of(context).setThemeVariant(value),
      itemBuilder: (context) => [
        NgQuickMenu.header<String>(context, 'Theme'),
        for (final (value, label, icon) in _variants)
          NgQuickMenu.item<String>(context,
              value: value,
              label: label,
              icon: icon,
              selected: current == value),
      ],
    );
  }
}
