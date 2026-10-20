import 'package:flutter/material.dart';

import 'flutter_flow_theme.dart';

/// Redesign tokens (Claude Design handoff, 20 Oct 2026 — "Nagarva App").
///
/// [FlutterFlowTheme] still carries the colours every existing page reads
/// (`primary`, `primaryBackground`, ...). Those were re-pointed at this
/// palette in the same change, so untouched pages pick up the new look for
/// free. This class holds the finer steps the redesign uses on top of that
/// — three surface levels, a sheet and an inset colour, four text weights,
/// hairlines and the status hue pairs — which the FlutterFlow palette has
/// no slots for.
///
/// The three variants match the existing Light / Dark / Midnight switch
/// one to one, so [of] needs no state of its own: it asks
/// [FlutterFlowTheme.effectiveVariant] which one is live.
///
/// Elevation rule from the handoff: **no shadows**. Depth is surface
/// colour steps plus 1px hairlines.
class NgPalette {
  const NgPalette._({
    required this.isLight,
    required this.bg,
    required this.s1,
    required this.s1b,
    required this.s2,
    required this.s3,
    required this.sheet,
    required this.inset,
    required this.nav,
    required this.text,
    required this.soft,
    required this.mute,
    required this.faint,
    required this.navOff,
    required Color hairlineBase,
    required double hairlineK,
    required this.acc,
    required this.accBtn,
    required this.green,
    required this.amber,
    required this.blue,
    required this.red,
    required this.greenBg,
    required this.amberBg,
    required this.blueBg,
    required this.redBg,
  })  : _hairlineBase = hairlineBase,
        _hairlineK = hairlineK;

  final bool isLight;

  /// Page background.
  final Color bg;

  /// Card.
  final Color s1;

  /// Cell inside a card (KPI grid cells).
  final Color s1b;

  /// Raised secondary button.
  final Color s2;

  /// Icon tile, chip, neutral pill.
  final Color s3;

  /// Bottom sheet.
  final Color sheet;

  /// Field / inner panel.
  final Color inset;

  /// Bottom nav bar.
  final Color nav;

  final Color text;
  final Color soft;
  final Color mute;
  final Color faint;
  final Color navOff;

  final Color _hairlineBase;
  final double _hairlineK;

  /// Accent for TEXT and icons. Darker than [accBtn] in Light so it stays
  /// readable on white.
  final Color acc;

  /// Accent for filled buttons. Label on it is always [onAcc].
  final Color accBtn;

  final Color green;
  final Color amber;
  final Color blue;
  final Color red;
  final Color greenBg;
  final Color amberBg;
  final Color blueBg;
  final Color redBg;

  /// Text on an accent button — the same near-black in every theme.
  static const Color onAcc = Color(0xFF0A0C10);

  /// Notification-count badge (nav, bell). Same in every theme.
  static const Color badge = Color(0xFFEF6661);

  /// Hairline at nominal alpha [a] (0.04 … 0.25), scaled per theme and
  /// capped at 0.5 — the handoff's `w04 … w25`.
  Color hairline(double a) =>
      _hairlineBase.withValues(alpha: (a * _hairlineK).clamp(0.0, 0.5));

  Color get w04 => hairline(0.04);
  Color get w06 => hairline(0.06);
  Color get w07 => hairline(0.07);
  Color get w08 => hairline(0.08);
  Color get w1 => hairline(0.1);
  Color get w12 => hairline(0.12);
  Color get w15 => hairline(0.15);

  /// Selected chip: background is the text colour, label inverts.
  Color get inv => text;
  Color get invText => isLight ? Colors.white : onAcc;

  /// Status hue pairs. The design addresses status colour by hue
  /// (green 155, amber 85, blue 255, red 25); these name the four it uses.
  ({Color fg, Color bg}) status(NgStatus s) => switch (s) {
        NgStatus.green => (fg: green, bg: greenBg),
        NgStatus.amber => (fg: amber, bg: amberBg),
        NgStatus.blue => (fg: blue, bg: blueBg),
        NgStatus.red => (fg: red, bg: redBg),
        NgStatus.neutral => (fg: mute, bg: s3),
        NgStatus.accent => (fg: acc, bg: acc.withValues(alpha: 0.14)),
      };

  static const midnight = NgPalette._(
    isLight: false,
    bg: Color(0xFF0A0C10),
    s1: Color(0xFF12151B),
    s1b: Color(0xFF161920),
    s2: Color(0xFF1A1E26),
    s3: Color(0xFF1F232B),
    sheet: Color(0xFF14171D),
    inset: Color(0xFF0F1217),
    nav: Color(0xFF0D1015),
    text: Color(0xFFECEEF2),
    soft: Color(0xFFC3C8D1),
    mute: Color(0xFF8A93A3),
    faint: Color(0xFF5B6372),
    navOff: Color(0xFF7A8292),
    hairlineBase: Color(0xFFFFFFFF),
    hairlineK: 1,
    acc: Color(0xFFF68C36),
    accBtn: Color(0xFFF68C36),
    green: Color(0xFF5CCB89),
    amber: Color(0xFFEBBD57),
    blue: Color(0xFF71B4FF),
    red: Color(0xFFFE8B83),
    greenBg: Color(0x245CCB89),
    amberBg: Color(0x24DAA932),
    blueBg: Color(0x2471B4FF),
    redBg: Color(0x24FE8B83),
  );

  static const dark = NgPalette._(
    isLight: false,
    bg: Color(0xFF0C1A2B),
    s1: Color(0xFF12243A),
    s1b: Color(0xFF152840),
    s2: Color(0xFF1A2E47),
    s3: Color(0xFF1F3550),
    sheet: Color(0xFF13263D),
    inset: Color(0xFF0E1E31),
    nav: Color(0xFF0E1F33),
    text: Color(0xFFEEF2F7),
    soft: Color(0xFFC5CFDC),
    mute: Color(0xFF93A1B6),
    faint: Color(0xFF66768F),
    navOff: Color(0xFF8090A6),
    hairlineBase: Color(0xFFFFFFFF),
    hairlineK: 1.2,
    acc: Color(0xFFF68C36),
    accBtn: Color(0xFFF68C36),
    green: Color(0xFF5CCB89),
    amber: Color(0xFFEBBD57),
    blue: Color(0xFF71B4FF),
    red: Color(0xFFFE8B83),
    greenBg: Color(0x245CCB89),
    amberBg: Color(0x24DAA932),
    blueBg: Color(0x2471B4FF),
    redBg: Color(0x24FE8B83),
  );

  static const light = NgPalette._(
    isLight: true,
    bg: Color(0xFFF4F3F0),
    s1: Color(0xFFFFFFFF),
    s1b: Color(0xFFFAF9F7),
    s2: Color(0xFFF2F1ED),
    s3: Color(0xFFECEAE5),
    sheet: Color(0xFFFFFFFF),
    inset: Color(0xFFF4F3F0),
    nav: Color(0xFFFFFFFF),
    text: Color(0xFF16181D),
    soft: Color(0xFF3D424B),
    mute: Color(0xFF5E6572),
    faint: Color(0xFF7D838E),
    navOff: Color(0xFF6B717C),
    hairlineBase: Color(0xFF16181D),
    hairlineK: 1.4,
    acc: Color(0xFFBF4B00),
    accBtn: Color(0xFFEF7926),
    green: Color(0xFF008442),
    amber: Color(0xFF9D6800),
    blue: Color(0xFF226BC0),
    red: Color(0xFFB2403D),
    greenBg: Color(0x21269E5F),
    amberBg: Color(0x21AC7D00),
    blueBg: Color(0x214687D8),
    redBg: Color(0x21CD605A),
  );

  static NgPalette of(BuildContext context) =>
      switch (FlutterFlowTheme.effectiveVariant(context)) {
        'light' => light,
        'dark' => dark,
        _ => midnight,
      };
}

enum NgStatus { green, amber, blue, red, neutral, accent }

/// Shape tokens from the handoff ("Shape and spacing").
abstract final class NgRadius {
  static const double card = 18;
  static const double tile = 16;
  static const double field = 12;
  static const double button = 14;
  static const double iconTile = 11;
  static const double sheet = 28;
}

/// The redesign's two type families. Geist for UI, Geist Mono for
/// numbers, IDs, amounts and odometer readings. Both are bundled assets
/// (pubspec `fonts:`) — the pinned google_fonts has neither.
///
/// [geist] takes the same named parameters as `GoogleFonts.inter`, so the
/// FlutterFlow-era call sites could be switched by name alone.
abstract final class NgFonts {
  static const String family = 'Geist';
  static const String monoFamily = 'Geist Mono';

  static TextStyle geist({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) =>
      _style(family, textStyle, color, backgroundColor, fontSize, fontWeight,
          fontStyle, letterSpacing, wordSpacing, textBaseline, height, locale,
          foreground, background, shadows, fontFeatures, decoration,
          decorationColor, decorationStyle, decorationThickness);

  static TextStyle mono({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      _style(monoFamily, textStyle, color, null, fontSize,
          fontWeight ?? FontWeight.w500, null, letterSpacing, null, null,
          height, null, null, null, null, null, decoration, null, null, null);

  static TextStyle _style(
    String family,
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  ) =>
      (textStyle ?? const TextStyle()).copyWith(
        fontFamily: family,
        color: color,
        backgroundColor: backgroundColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        textBaseline: textBaseline,
        height: height,
        locale: locale,
        foreground: foreground,
        background: background,
        shadows: shadows,
        fontFeatures: fontFeatures,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        decorationThickness: decorationThickness,
      );
}
