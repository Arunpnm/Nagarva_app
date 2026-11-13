import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '/components/pdf_view_page.dart';
import '/flutter_flow/ng_tokens.dart';

/// View / Share / Print for a document that is already built (13 Nov
/// 2026). Arun: "I want all documents generated and view, download, share
/// option within app."
///
/// The nine order documents already had these three in their dialog. The
/// survey and the quotation did not: their one button went straight to
/// the phone's share sheet (a download on the web), so there was no way
/// to simply look at a quote before sending it. They now open this.
///
/// "Share or download" is one action on purpose: on a phone it opens the
/// share sheet (WhatsApp, email, Save to files), on the web it downloads.
class PdfActionsSheet {
  PdfActionsSheet._();

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String filename,
    required Uint8List bytes,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: NgPalette.of(context).s1,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) {
        final c = NgPalette.of(sheet);
        Widget row(IconData icon, String label, String sub,
                Future<void> Function() run) =>
            ListTile(
              leading: Icon(icon, color: c.acc),
              title: Text(label,
                  style: NgFonts.geist(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
              subtitle:
                  Text(sub, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
              onTap: () async {
                Navigator.of(sheet).pop();
                await run();
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(title,
                    style: NgFonts.geist(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
              ),
              row(Icons.visibility_outlined, 'View', 'Look at it here first',
                  () async {
                if (!context.mounted) return;
                await PdfViewPage.open(context,
                    title: title, bytes: bytes, filename: filename);
              }),
              row(Icons.ios_share_rounded, 'Share or download',
                  'WhatsApp, email, or save the PDF', () async {
                await Printing.sharePdf(bytes: bytes, filename: filename);
              }),
              row(Icons.print_outlined, 'Print', 'Send it to a printer',
                  () async {
                await Printing.layoutPdf(onLayout: (_) async => bytes);
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
