import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/xlsx_writer.dart';

/// The data export is a vendor's only full copy of their business. A file
/// Excel calls "corrupt" is worse than no button, so these cases open the
/// zip and check the exact parts Excel is strict about.
void main() {
  Map<String, String> parts(List<int> bytes) {
    final a = ZipDecoder().decodeBytes(bytes);
    return {
      for (final f in a.files)
        if (f.isFile) f.name: utf8.decode(f.content as List<int>),
    };
  }

  test('has every part Excel needs, one worksheet per sheet', () {
    final p = parts(buildXlsx([
      XlsxSheet('About', [['a']]),
      XlsxSheet('Orders', [['b']]),
    ]));
    expect(
        p.keys,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet2.xml',
        ]));
    // Excel warns "no default style" without cellStyles.
    expect(p['xl/styles.xml'], contains('<cellStyles count="1">'));
  });

  test('escapes markup and drops control characters', () {
    final s = parts(buildXlsx([
      XlsxSheet('X', [
        ['h'],
        ['A <&> "B"\u0007'],
      ]),
    ]))['xl/worksheets/sheet1.xml']!;
    expect(s, contains('A &lt;&amp;&gt; &quot;B&quot;</t>'));
    expect(s.contains('\u0007'), isFalse);
  });

  test('numbers stay numbers, bools are booleans, header is bold', () {
    final s = parts(buildXlsx([
      XlsxSheet('X', [
        ['amount', 'paid'],
        [25000, true],
      ]),
    ]))['xl/worksheets/sheet1.xml']!;
    expect(s, contains('<c r="A1" s="1" t="inlineStr">'));
    expect(s, contains('<c r="A2"><v>25000</v></c>'));
    expect(s, contains('<c r="B2" t="b"><v>1</v></c>'));
  });

  test('cells longer than Excel allows are cut, not refused', () {
    final s = parts(buildXlsx([
      XlsxSheet('X', [
        ['x' * 40000],
      ]),
    ]))['xl/worksheets/sheet1.xml']!;
    final text = RegExp(r'<t xml:space="preserve">(.*)</t>').firstMatch(s)!;
    expect(text.group(1)!.length, kXlsxMaxCellChars);
    expect(text.group(1), endsWith('[cut short]'));
  });

  test('sheet names: illegal characters, 31 chars, duplicates', () {
    final w = parts(buildXlsx([
      XlsxSheet('Orders', [['a']]),
      XlsxSheet('Orders', [['b']]),
      XlsxSheet('bad:/?*[]name', [['c']]),
      XlsxSheet('A very long sheet name that exceeds thirty one chars', [['d']]),
    ]))['xl/workbook.xml']!;
    expect(w, contains('name="Orders"'));
    expect(w, contains('name="Orders (2)"'));
    expect(w, contains('name="bad      name"'));
    expect(w, contains('name="A very long sheet name that exc"'));
  });

  test('column letters past Z', () {
    expect(columnLetters(0), 'A');
    expect(columnLetters(25), 'Z');
    expect(columnLetters(26), 'AA');
    expect(columnLetters(701), 'ZZ');
    expect(columnLetters(702), 'AAA');
  });

  test('a workbook with no sheets is refused', () {
    expect(() => buildXlsx([]), throwsArgumentError);
  });
}
