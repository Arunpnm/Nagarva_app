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
/// **UPDATE Oct 2026: the ARB files are now filled** (hi, ta, kn, te, ml;
/// Claude-written, pending native-speaker review), so `_untranslated` is
/// empty and the menu's caveat line no longer shows. The history below
/// is kept because the rule it records still applies to any new locale.
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
    ('te', 'తెలుగు'),
    ('ml', 'മലയാളം'),
  ];

  /// Locales with no strings yet. Empty since Oct 2026: every ARB now
  /// carries all of app_en.arb's messages (Claude-written, pending
  /// native-speaker review — see each file's @@x-nagarva-note). A locale
  /// added later without strings goes back in here in the same change.
  static const _untranslated = <String>{};

  /// CORRECTIONS.md D5: these translations are machine-written and wait
  /// for native-speaker review, so the pickers mark them "Beta". Remove a
  /// code from here when its review is done — keys never change.
  static const betaLanguages = <String>{'ta', 'hi', 'kn', 'te', 'ml'};

  /// The small "Beta" tag both language pickers show.
  static Widget betaTag(Color color) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('Beta',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final current = FFLocalizations.of(context).languageCode;
    return PopupMenuButton<String>(
      tooltip: 'Language',
      // The handoff's header shows the active language as its short code
      // ("EN", "TA") rather than a globe, so the current choice is
      // readable without opening the menu.
      child: SizedBox(
        width: 36,
        height: 40,
        child: Center(
          child: Text(
            current.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: iconColor ?? IconTheme.of(context).color,
            ),
          ),
        ),
      ),
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
                if (betaLanguages.contains(code))
                  betaTag(theme.secondaryText),
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
                'Some languages are not translated yet — '
                'the app stays in English for those.',
                style: TextStyle(
                    fontSize: 10.5, height: 1.25, color: theme.secondaryText),
              ),
            ),
          ),
      ],
    );
  }
}
