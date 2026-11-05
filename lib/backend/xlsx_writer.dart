import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Minimal .xlsx writer (5 Nov 2026, Backup & export).
///
/// An .xlsx file is a zip of a few XML parts. This writes exactly what
/// Excel, Google Sheets and LibreOffice need for plain tables: one sheet
/// per entry, a bold header row, numbers as numbers, everything else as
/// text. No formulas, no styling beyond the header.
///
/// Why not the `excel` package: its latest release (4.0.6) needs
/// `archive` 3.x, and the PDF stack already locks `archive` 4.x — the two
/// cannot resolve together. `archive` is already in the app, so this
/// adds no dependency.
///
/// Pure Dart (no Flutter import) so `dart test` can open the output.
class XlsxSheet {
  XlsxSheet(this.name, this.rows);

  /// Shown on the tab. Cleaned and cut to Excel's 31-character limit.
  final String name;

  /// First row is the header. Cells may be null, num, bool, DateTime,
  /// String, or anything else (written with toString / JSON).
  final List<List<Object?>> rows;
}

/// Excel refuses a cell longer than this.
const kXlsxMaxCellChars = 32767;

Uint8List buildXlsx(List<XlsxSheet> sheets) {
  if (sheets.isEmpty) {
    throw ArgumentError('A workbook needs at least one sheet.');
  }
  final names = _uniqueSheetNames(sheets.map((s) => s.name).toList());
  final archive = Archive();
  void add(String path, String xml) =>
      archive.addFile(ArchiveFile.bytes(path, utf8.encode(xml)));

  add('[Content_Types].xml', _contentTypes(sheets.length));
  add('_rels/.rels', _rootRels);
  add('xl/workbook.xml', _workbook(names));
  add('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
  add('xl/styles.xml', _styles);
  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i].rows));
  }
  return ZipEncoder().encodeBytes(archive);
}

// ---------------------------------------------------------------------------

String _contentTypes(int n) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    ..write('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  for (var i = 1; i <= n; i++) {
    b.write('<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  b.write('</Types>');
  return b.toString();
}

const _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(List<String> names) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
    ..write('<sheets>');
  for (var i = 0; i < names.length; i++) {
    b.write('<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
  }
  b.write('</sheets></workbook>');
  return b.toString();
}

String _workbookRels(int n) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  for (var i = 1; i <= n; i++) {
    b.write('<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>');
  }
  b.write('<Relationship Id="rId${n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
  b.write('</Relationships>');
  return b.toString();
}

/// Style 0 = normal, style 1 = bold (header row).
const _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

String _sheet(List<List<Object?>> rows) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  if (rows.isNotEmpty) {
    // Keep the header visible while scrolling.
    b.write('<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>');
  }
  b.write('<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    b.write('<row r="${r + 1}">');
    for (var c = 0; c < row.length; c++) {
      final v = row[c];
      if (v == null) continue;
      final ref = '${columnLetters(c)}${r + 1}';
      final style = r == 0 ? ' s="1"' : '';
      if (v is num && v.isFinite) {
        b.write('<c r="$ref"$style><v>$v</v></c>');
      } else if (v is bool) {
        b.write('<c r="$ref"$style t="b"><v>${v ? 1 : 0}</v></c>');
      } else {
        final text = _cellText(v);
        if (text.isEmpty) continue;
        b.write('<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">'
            '${_esc(text)}</t></is></c>');
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

String _cellText(Object v) {
  String s;
  if (v is DateTime) {
    s = v.toIso8601String();
  } else if (v is Map || v is List) {
    s = jsonEncode(v);
  } else {
    s = v.toString();
  }
  // XML 1.0 forbids most control characters; Excel would call the file
  // corrupt. Keep tab, newline and carriage return.
  s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]'), '');
  if (s.length > kXlsxMaxCellChars) {
    s = '${s.substring(0, kXlsxMaxCellChars - 12)} [cut short]';
  }
  return s;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// 0 -> A, 25 -> Z, 26 -> AA, 701 -> ZZ, 702 -> AAA.
String columnLetters(int index) {
  var n = index + 1;
  var out = '';
  while (n > 0) {
    out = String.fromCharCode(65 + (n - 1) % 26) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

/// Excel sheet names: no : \ / ? * [ ], at most 31 chars, unique
/// (case-insensitive), not empty.
List<String> _uniqueSheetNames(List<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in raw) {
    var base = r.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    if (base.isEmpty) base = 'Sheet';
    if (base.length > 31) base = base.substring(0, 31);
    var name = base;
    var k = 2;
    while (seen.contains(name.toLowerCase())) {
      final suffix = ' ($k)';
      name = (base.length + suffix.length > 31
              ? base.substring(0, 31 - suffix.length)
              : base) +
          suffix;
      k++;
    }
    seen.add(name.toLowerCase());
    out.add(name);
  }
  return out;
}
