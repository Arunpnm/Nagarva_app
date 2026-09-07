import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '/flutter_flow/flutter_flow_theme.dart';

/// Looks at a generated document without downloading it first.
///
/// Arun, 7 Sept 2026: *"also create view option so that we dont have to
/// download evertime then do correction"*.
///
/// Every document in this app was download-or-print only, so checking
/// one — which is what you do while a quote or an invoice is still being
/// corrected — meant a file in Downloads each time. After a few rounds
/// that is a folder of near-identical PDFs and no way to tell which is
/// current.
///
/// Uses `PdfPreview` from `printing`, already a dependency (it is what
/// Print and Share go through), so this adds a screen and no package.
/// Print and Share are kept ON the preview's own action bar: having
/// looked at it is exactly when you want to send it.
class PdfViewPage extends StatelessWidget {
  const PdfViewPage({
    super.key,
    required this.title,
    required this.bytes,
    this.filename,
  });

  final String title;
  final Uint8List bytes;

  /// Used when sharing from the preview. Without it the platform picks
  /// something like "document.pdf", which is the same problem as the
  /// Downloads folder, one step later.
  final String? filename;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required Uint8List bytes,
    String? filename,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PdfViewPage(title: title, bytes: bytes, filename: filename),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text(title,
            style: TextStyle(color: theme.primaryText, fontSize: 17)),
        iconTheme: IconThemeData(color: theme.primaryText),
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        // The document is already built and handed in; regenerating it
        // per format would re-run the whole pipeline for a preview.
        useActions: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: filename,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
