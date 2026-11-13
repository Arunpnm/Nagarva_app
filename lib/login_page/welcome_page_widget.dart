import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/app_session.dart';
import '/backend/device_org_binding.dart';
import '/backend/login_memory.dart';
import '/backend/supabase/supabase.dart';
import '/components/auth_shell.dart';
import '/components/language_quick_button.dart';
import '/components/ng_widgets.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/index.dart';
import '/l10n/gen/app_localizations.dart';
import '/permissions.dart';

/// First screen after install, and whenever this phone is not tied to a
/// company (login redesign, 12 Nov 2026): one front door with three
/// choices — Log in, Create company account, or staff joining a company.
///
/// Vendor-facing, so it carries the Nagarva name and tagline.
class WelcomePageWidget extends StatefulWidget {
  const WelcomePageWidget({super.key});

  static String routeName = 'WelcomePage';
  static String routePath = '/welcome';

  @override
  State<WelcomePageWidget> createState() => _WelcomePageWidgetState();
}

class _WelcomePageWidgetState extends State<WelcomePageWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _truck;

  @override
  void initState() {
    super.initState();
    _truck =
        AnimationController(vsync: this, duration: const Duration(seconds: 7));
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  Future<void> _afterFirstFrame() async {
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) {
      _truck.value = 0.62;
    } else {
      _truck.repeat();
    }
    // A login restored from the last run: go straight in, unless the
    // person asked not to be kept logged in on this phone.
    if (AppSession.instance.currentOrgId == null) return;
    if (await LoginMemory.shouldForgetNow()) {
      try {
        await SupaFlow.client.auth.signOut();
      } catch (_) {}
      StaffPermissions.clearActive();
      AppSession.instance.clear();
      return;
    }
    if (mounted) context.go(HomePageWidget.routePath);
  }

  @override
  void dispose() {
    _truck.dispose();
    super.dispose();
  }

  Widget _feature(NgPalette c, int n, String title, String sub,
          {bool last = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.w06)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kAuthBlue,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text('$n',
                  style: NgFonts.mono(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: NgFonts.geist(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: c.text)),
                  const SizedBox(height: 1),
                  Text(sub,
                      style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final pad = MediaQuery.paddingOf(context);
    final link = authLinkColor(context);

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
      child: Scaffold(
        backgroundColor: c.bg,
        body: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: kAuthBlue,
                padding: EdgeInsets.only(top: pad.top + 10),
                child: Column(
                  children: [
                    framed(
                      Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const LanguageQuickButton(
                                  iconColor: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 2),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: Image.asset(
                              'assets/images/nagarva_logo.png',
                              width: 112,
                              height: 112,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(width: 112, height: 112),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text.rich(
                            TextSpan(children: [
                              const TextSpan(text: 'Naga'),
                              TextSpan(
                                  text: 'rva',
                                  style: NgFonts.geist(
                                      color: kAuthOrangeOnBlue)),
                            ]),
                            style: NgFonts.geist(
                                fontSize: 36,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.72,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          // The tagline is the brand line: one line, never
                          // translated, shrinks to fit a narrow phone.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                              TextSpan(children: [
                                const TextSpan(text: kNagarvaTaglineA),
                                const TextSpan(text: ' '),
                                TextSpan(
                                    text: kNagarvaTaglineB,
                                    style: NgFonts.geist(
                                        color: kAuthOrangeOnBlue)),
                              ]),
                              maxLines: 1,
                              style: NgFonts.geist(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.46,
                                  color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(l.auTagSub,
                              textAlign: TextAlign.center,
                              style: NgFonts.geist(
                                  fontSize: 14,
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                  color: kAuthOnBlueSoft)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // A small truck driving along a dashed road.
                    ExcludeSemantics(
                      child: SizedBox(
                        height: 86,
                        width: double.infinity,
                        child: LayoutBuilder(
                          builder: (context, box) => AnimatedBuilder(
                            animation: _truck,
                            builder: (context, _) => Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 36,
                                  child: CustomPaint(
                                      size: const Size(double.infinity, 2),
                                      painter: _RoadPainter()),
                                ),
                                Positioned(
                                  left: -50 +
                                      (box.maxWidth + 50) * _truck.value,
                                  top: 2,
                                  child: const Icon(
                                      Icons.local_shipping_rounded,
                                      size: 38,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -40),
                child: framed(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NgAuthCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        child: Column(
                          children: [
                            _feature(c, 1, l.auF1, l.auF1s),
                            _feature(c, 2, l.auF2, l.auF2s),
                            _feature(c, 3, l.auF3, l.auF3s, last: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      NgPrimaryButton(
                        label: l.lpLogIn,
                        height: 52,
                        onPressed: () =>
                            context.go(LoginPageWidget.routePath),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: link,
                            backgroundColor: c.s1,
                            side: BorderSide(color: link, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () =>
                              context.go(VendorSignupPageWidget.routePath),
                          child: Text(l.auCreate,
                              style: NgFonts.geist(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: link)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(46)),
                        onPressed: () async {
                          await DeviceOrgBinding.unbind();
                          if (context.mounted) {
                            context.go(OrgBindingPageWidget.routePath);
                          }
                        },
                        icon: Icon(Icons.person_add_alt_1_outlined,
                            size: 19, color: link),
                        label: Text(l.auStaff,
                            style: NgFonts.geist(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: link)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => launchURL(kPrivacyPolicyUrl),
                            child: Text(l.lgPriv,
                                style: NgFonts.geist(
                                    fontSize: 12.5, color: c.mute)),
                          ),
                          Text('·',
                              style: NgFonts.geist(
                                  fontSize: 12.5, color: c.mute)),
                          TextButton(
                            onPressed: () => launchURL(kTermsUrl),
                            child: Text(l.lgTerms,
                                style: NgFonts.geist(
                                    fontSize: 12.5, color: c.mute)),
                          ),
                        ],
                      ),
                      SizedBox(height: pad.bottom),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, 1), Offset(x + 8, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
