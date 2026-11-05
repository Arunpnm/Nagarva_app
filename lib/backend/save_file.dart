import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

/// Saves a generated file for the user (5 Nov 2026): a browser download on
/// web, the phone's Downloads/Files on Android. Returns where it went (a
/// path or a short label), or null if nothing was saved.
///
/// The one place the app writes a non-PDF file (PDFs keep using
/// `Printing.sharePdf`). Added with `file_saver` 0.3.1 — not the newest
/// 0.4+, which needs Dart 3.11+ while the pinned Flutter 3.35.5 ships
/// Dart 3.9.
Future<String?> saveExcelFile(String name, Uint8List bytes) async {
  final where = await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    fileExtension: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
  // On failure file_saver returns its own "Something went wrong…" text
  // rather than throwing or returning empty; never report that as saved.
  if (where.isEmpty || where.startsWith('Something went wrong')) return null;
  return where;
}
