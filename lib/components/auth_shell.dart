import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/flutter_flow/ng_tokens.dart';

/// Brand colours of the sign-in screens (login redesign, 12 Nov 2026):
/// a deep blue header, white card, orange primary button.
const kAuthBlue = Color(0xFF173A94);
const kAuthOnBlueSoft = Color(0xFFD5DEF5);
const kAuthOrangeOnBlue = Color(0xFFFFA35C);

/// Blue that stays readable as TEXT on the page: the brand blue on light
/// themes, a light blue on Dark / Midnight.
Color authLinkColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9DB8FF)
        : kAuthBlue;

/// Shared layout of every sign-in screen: blue header (back, title,
/// subtitle), a white card that overlaps it, then anything [below].
class NgAuthShell extends StatelessWidget {
  const NgAuthShell({
    super.key,
    required this.title,
    required this.card,
    this.subtitle,
    this.subtitleWidget,
    this.onBack,
    this.icon,
    this.showLogo = false,
    this.trailing,
    this.headerExtra,
    this.below = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final VoidCallback? onBack;
  final IconData? icon;
  final bool showLogo;
  final Widget? trailing;
  final Widget? headerExtra;
  final Widget card;
  final List<Widget> below;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final pad = MediaQuery.paddingOf(context);
    Widget framed(Widget child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: child,
            ),
          ),
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Scaffold(
          backgroundColor: c.bg,
          body: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: kAuthBlue,
                  padding: EdgeInsets.only(top: pad.top + 8, bottom: 56),
                  child: framed(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 44,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 44,
                                child: onBack == null
                                    ? null
                                    : IconButton(
                                        padding: EdgeInsets.zero,
                                        alignment: Alignment.centerLeft,
                                        tooltip: MaterialLocalizations.of(
                                                context)
                                            .backButtonTooltip,
                                        icon: const Icon(
                                            Icons.arrow_back_ios_new_rounded,
                                            size: 20,
                                            color: Colors.white),
                                        onPressed: onBack,
                                      ),
                              ),
                              Expanded(
                                child: showLogo
                                    ? Center(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(11),
                                          child: Image.asset(
                                            'assets/images/nagarva_logo.png',
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const SizedBox(
                                                    width: 40, height: 40),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minWidth: 44),
                                child: trailing ?? const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                        if (icon != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(icon, size: 26, color: Colors.white),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(title,
                            style: NgFonts.geist(
                                fontSize: 26,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.52,
                                color: Colors.white)),
                        if (subtitleWidget != null) ...[
                          const SizedBox(height: 6),
                          subtitleWidget!,
                        ] else if (subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(subtitle!,
                              style: NgFonts.geist(
                                  fontSize: 14,
                                  height: 1.45,
                                  color: kAuthOnBlueSoft)),
                        ],
                        if (headerExtra != null) headerExtra!,
                      ],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -36),
                  child: framed(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        NgAuthCard(child: card),
                        ...below,
                        SizedBox(height: pad.bottom),
                      ],
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

/// The white card that overlaps the blue header.
class NgAuthCard extends StatelessWidget {
  const NgAuthCard(
      {super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.w06),
      ),
      child: child,
    );
  }
}

/// Field label used inside an auth card.
class NgAuthLabel extends StatelessWidget {
  const NgAuthLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: NgFonts.geist(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: NgPalette.of(context).soft)),
      );
}

/// Input look of the sign-in screens: white field, orange when focused.
InputDecoration authInputDecoration(BuildContext context,
    {String? hint, Widget? prefix, Widget? suffix}) {
  final c = NgPalette.of(context);
  OutlineInputBorder b(Color color, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: NgFonts.geist(color: c.faint, fontSize: 15),
    counterText: '',
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    filled: true,
    fillColor: c.s1,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    enabledBorder: b(c.w12, 1),
    focusedBorder: b(c.accBtn, 1.5),
    border: b(c.w12, 1),
  );
}

/// One plain line in a tinted box (error = red, info = card with icon).
class NgAuthNote extends StatelessWidget {
  const NgAuthNote(this.text,
      {super.key, this.error = false, this.success = false, this.icon});

  final String text;
  final bool error;
  final bool success;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final fg = error
        ? c.red
        : success
            ? c.green
            : authLinkColor(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error
            ? c.redBg
            : success
                ? c.greenBg
                : c.s1,
        borderRadius: BorderRadius.circular(14),
        border: error || success ? null : Border.all(color: c.w06),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              icon ??
                  (error
                      ? Icons.error_outline_rounded
                      : success
                          ? Icons.check_circle_outline_rounded
                          : Icons.info_outline_rounded),
              size: 19,
              color: fg),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: NgFonts.geist(
                    fontSize: 13,
                    height: 1.45,
                    color: error ? c.red : c.soft)),
          ),
        ],
      ),
    );
  }
}
