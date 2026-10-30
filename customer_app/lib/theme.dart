import 'package:flutter/material.dart';

/// Customer tokens (design handoff README, "Customer tokens", light only).
abstract final class C {
  static const blue = Color(0xFF0B2F73); // hero, selected card, ticket
  static const blueText = Color(0xFF0B3A8C);
  static const orange = Color(0xFFF37A0E); // CTA, highlight, truck
  static const onOrange = Color(0xFF0A0C10);
  static const page = Color(0xFFF4F3F0);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF16181D);
  static const secondary = Color(0xFF5E6572);
  static const hairline = Color(0x1416181D); // rgba(22,24,29,0.08)
  static const red = Color(0xFFB42318);
  static const green = Color(0xFF1F7A4D);
}

TextStyle geist(double size,
        {FontWeight weight = FontWeight.w400, Color color = C.ink, double? height}) =>
    TextStyle(
        fontFamily: 'Geist',
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height);

TextStyle mono(double size,
        {FontWeight weight = FontWeight.w600, Color color = C.ink}) =>
    TextStyle(
        fontFamily: 'GeistMono', fontSize: size, fontWeight: weight, color: color);

ThemeData customerTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: 'Geist',
      scaffoldBackgroundColor: C.page,
      colorScheme: ColorScheme.fromSeed(
          seedColor: C.blue, primary: C.blue, secondary: C.orange),
      appBarTheme: const AppBarTheme(
          backgroundColor: C.page,
          foregroundColor: C.ink,
          elevation: 0,
          scrolledUnderElevation: 0),
    );

/// A white card with the design's 1px hairline and radius 18, no shadow.
class CCard extends StatelessWidget {
  const CCard(
      {super.key,
      required this.child,
      this.onTap,
      this.selected = false,
      this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? C.blue : C.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? C.blue : C.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

/// The orange call to action, 52 high.
class CButton extends StatelessWidget {
  const CButton({super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: C.orange,
            foregroundColor: C.onOrange,
            disabledBackgroundColor: C.hairline,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onPressed,
          child: Text(label,
              style: geist(15,
                  weight: FontWeight.w600,
                  color: onPressed == null ? C.secondary : C.onOrange)),
        ),
      );
}
