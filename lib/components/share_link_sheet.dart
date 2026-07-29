import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Shared "here is a customer link" sheet — WhatsApp first, copy as
/// fallback (fix brief #2, items 3 and 6).
///
/// Replaces the copy-only AlertDialog the survey/quote links used, which
/// was the remaining half of item 1's acceptance criterion ("opens the
/// WhatsApp share flow").
class ShareLinkSheet extends StatelessWidget {
  const ShareLinkSheet({
    super.key,
    required this.title,
    required this.link,
    required this.message,
    this.phone,
    this.subtitle,
  });

  final String title;
  final String link;

  /// Pre-filled WhatsApp body. The link is appended if not already in it.
  final String message;
  final String? phone;
  final String? subtitle;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String link,
    required String message,
    String? phone,
    String? subtitle,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ShareLinkSheet(
          title: title,
          link: link,
          message: message,
          phone: phone,
          subtitle: subtitle,
        ),
      );

  String get _fullMessage =>
      message.contains(link) ? message : '$message\n\n$link';

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: theme.alternate,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              title,
              style: GoogleFonts.interTight(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: theme.primaryText,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: GoogleFonts.inter(
                    fontSize: 12.5, height: 1.4, color: theme.secondaryText),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.primaryBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                link,
                style: GoogleFonts.inter(
                    fontSize: 12.5, color: theme.primaryText),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(buildWhatsAppLink(
                            phone: phone, message: _fullMessage));
                        final ok = await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Could not open WhatsApp')),
                          );
                        }
                      },
                      icon: const Icon(Icons.chat, size: 19),
                      label: const Text('WhatsApp'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kWhatsAppGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.primary,
                      side: BorderSide(color: theme.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
