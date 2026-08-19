import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Settings → Help & About (18 Aug 2026).
///
/// **This screen is a launch blocker, not a nicety.** Two external
/// approvals depend on it:
///   - **Play Store** requires the privacy policy to be reachable
///     IN-APP, not merely linked from the store listing.
///   - **Meta's WhatsApp Business API review** asks for support contact
///     details to be discoverable in the product.
/// Neither existed anywhere in the app before this — grepped 18 Aug
/// 2026: no About, Help or Support entry in `settings_page_widget.dart`.
///
/// Built with no new dependencies, per instruction: `url_launcher` was
/// already a dependency (the signup screen opens the same two legal
/// links with it), and the version string comes from a `--dart-define`
/// rather than `package_info_plus` — see [kAppVersion] for why adding a
/// package here is not casual in this pinned-SDK project.
///
/// The support row is gated on [hasNagarvaSupportPhone] and simply does
/// not render until Arun hands over the dedicated WhatsApp Business
/// number. That is deliberate: a contact affordance that goes nowhere is
/// worse than none, which is the same call made on PlanPage's CTA.
class HelpAboutPage extends StatelessWidget {
  const HelpAboutPage({super.key});

  static String routeName = 'HelpAboutPage';
  static String routePath = '/help-about';

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: const Text('Help & About'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          // ---- Branding ------------------------------------------------
          Center(
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.local_shipping,
                      size: 32, color: theme.primary),
                ),
                const SizedBox(height: 12),
                Text('Nagarva',
                    style: GoogleFonts.interTight(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryText)),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    kNagarvaTagline,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.45,
                        color: theme.secondaryText),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Version $kAppVersion',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: theme.secondaryText)),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ---- Support -------------------------------------------------
          // Hidden entirely until the number exists — see the class doc.
          if (hasNagarvaSupportPhone) ...[
            _sectionLabel(theme, 'Support'),
            _card(theme, [
              _row(
                theme,
                icon: Icons.chat_bubble_outline,
                title: 'Chat with support',
                subtitle: kNagarvaSupportPhone,
                onTap: () => _open(
                  context,
                  buildWhatsAppLink(
                    phone: kNagarvaSupportPhone,
                    message: 'Hi Nagarva support, I need help with my account.',
                  ),
                ),
              ),
              _divider(theme),
              _row(
                theme,
                icon: Icons.call_outlined,
                title: 'Call support',
                subtitle: kNagarvaSupportPhone,
                onTap: () => _open(context, 'tel:$kNagarvaSupportPhone'),
              ),
            ]),
            const SizedBox(height: 22),
          ],

          // ---- Legal ---------------------------------------------------
          _sectionLabel(theme, 'Legal'),
          _card(theme, [
            _row(
              theme,
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              onTap: () => _open(context, kPrivacyPolicyUrl),
            ),
            _divider(theme),
            _row(
              theme,
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              onTap: () => _open(context, kTermsUrl),
            ),
          ]),

          const SizedBox(height: 26),
          Center(
            child: Text(
              '© ${DateTime.now().year} Nagarva',
              style:
                  GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(FlutterFlowTheme theme, String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: GoogleFonts.interTight(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: theme.secondaryText,
          ),
        ),
      );

  Widget _card(FlutterFlowTheme theme, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: children),
      );

  Widget _divider(FlutterFlowTheme theme) => Divider(
        height: 1,
        thickness: 1,
        indent: 52,
        color: theme.primaryBackground,
      );

  Widget _row(
    FlutterFlowTheme theme, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon, size: 21, color: theme.primary),
        title: Text(title,
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.primaryText)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: GoogleFonts.inter(
                    fontSize: 12, color: theme.secondaryText)),
        trailing: Icon(Icons.open_in_new, size: 16, color: theme.secondaryText),
        onTap: onTap,
      );
}
