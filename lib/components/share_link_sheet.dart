import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '/backend/whatsapp_cloud.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/ng_tokens.dart';

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
    this.cloud,
  });

  /// When set, and the vendor's own WhatsApp number can send this
  /// template, the sheet offers that first. Otherwise unchanged.
  final WaCloudSend? cloud;

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
    WaCloudSend? cloud,
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
          cloud: cloud,
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
              style: NgFonts.geist(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: theme.primaryText,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: NgFonts.geist(
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
                style: NgFonts.geist(
                    fontSize: 12.5, color: theme.primaryText),
              ),
            ),
            const SizedBox(height: 16),
            if (cloud != null && (phone ?? '').trim().isNotEmpty)
              _CloudSendButton(cloud: cloud!, phone: phone!),
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

/// "Send from your WhatsApp number" — shown only once the template is
/// approved for this vendor. Sends through the `whatsapp` function, so the
/// message comes from the vendor's business number, not this phone.
class _CloudSendButton extends StatefulWidget {
  const _CloudSendButton({required this.cloud, required this.phone});
  final WaCloudSend cloud;
  final String phone;

  @override
  State<_CloudSendButton> createState() => _CloudSendButtonState();
}

class _CloudSendButtonState extends State<_CloudSendButton> {
  late final Future<bool> _ready = WhatsAppCloud.ready(widget.cloud.key);
  bool _busy = false;
  bool _sent = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await WhatsAppCloud.send(widget.cloud.key,
          to: widget.phone,
          params: widget.cloud.params,
          entityType: widget.cloud.entityType,
          entityId: widget.cloud.entityId);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _ready,
        builder: (context, snap) {
          if (snap.data != true) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _busy || _sent ? null : _send,
                icon: Icon(_sent ? Icons.check_rounded : Icons.send_rounded,
                    size: 19),
                label: Text(_sent
                    ? 'Sent from your WhatsApp number'
                    : _busy
                        ? 'Sending…'
                        : 'Send from your WhatsApp number'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kWhatsAppGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: kWhatsAppGreen.withValues(alpha: 0.55),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          );
        },
      );
}
