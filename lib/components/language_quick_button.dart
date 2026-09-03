import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/internationalization.dart';
import '/main.dart' show MyApp;

/// Language switcher for the app bar, beside [ThemeQuickButton].
///
/// Arun asked for this on 2 Sept 2026 and again on 3 Sept 2026: *"i need
/// the language button in top near same like theme"*.
///
/// It was held back the first time, on purpose, and the reason has NOT
/// gone away — it is simply his call to make, and he has made it twice.
/// Recorded here so nobody later reads this as an oversight:
///
/// **`app_ta.arb`, `app_hi.arb` and `app_kn.arb` contain ZERO message
/// keys against `app_en.arb`'s 487** (counted 3 Sept 2026, not carried
/// over from the earlier note). Every lookup falls through to English by
/// design — `internationalization.dart` has a fallback so nothing ever
/// renders blank. So picking தமிழ் marks the choice, persists it across
/// restarts, and changes not one word on screen.
///
/// The menu therefore SAYS so. A control that silently does nothing
/// reads as a broken app; one that explains itself reads as an
/// unfinished feature, which is the truth. Delete that line in the same
/// change that fills the ARB files — not before, and not separately.
///
/// Language names are in their OWN script, never transliterated: the
/// crew member who cannot read English is the entire reason this exists,
/// and "Tamil" written in Latin script is no use to him.
class LanguageQuickButton extends StatelessWidget {
  const LanguageQuickButton({super.key, this.iconColor});

  /// Pass `IconTheme.of(context).color` so it tracks the AppBar across
  /// light/dark/midnight, exactly as the theme button does.
  final Color? iconColor;

  /// Keys must match `FFLocalizations.languages()`.
  static const _languages = <(String, String)>[
    ('en', 'English'),
    ('ta', 'தமிழ்'),
    ('hi', 'हिन्दी'),
    ('kn', 'ಕನ್ನಡ'),
  ];

  /// The three that have no strings yet. When one is translated, take it
  /// out of this set in the same change.
  static const _untranslated = {'ta', 'hi', 'kn'};

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final current = FFLocalizations.of(context).languageCode;
    return PopupMenuButton<String>(
      tooltip: 'Language',
      icon: Icon(Icons.language,
          color: iconColor ?? IconTheme.of(context).color),
      onSelected: (code) => MyApp.of(context).setLocale(code),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text('LANGUAGE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: theme.secondaryText,
              )),
        ),
        for (final (code, name) in _languages)
          PopupMenuItem<String>(
            value: code,
            child: Row(
              children: [
                Icon(
                  code == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: code == current ? theme.primary : theme.secondaryText,
                ),
                const SizedBox(width: 10),
                Text(name,
                    style: TextStyle(
                      fontWeight:
                          code == current ? FontWeight.w700 : FontWeight.w500,
                      color:
                          code == current ? theme.primary : theme.primaryText,
                    )),
              ],
            ),
          ),
        if (_untranslated.isNotEmpty)
          PopupMenuItem<String>(
            enabled: false,
            height: 34,
            child: SizedBox(
              width: 190,
              child: Text(
                'Tamil, Hindi and Kannada are not translated yet — '
                'the app stays in English.',
                style: TextStyle(
                    fontSize: 10.5, height: 1.25, color: theme.secondaryText),
              ),
            ),
          ),
      ],
    );
  }
}
