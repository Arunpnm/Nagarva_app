import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every locale ARB carries every message of app_en.arb, with the same
/// placeholders. gen_l10n only WARNS about a missing translation and falls
/// back to English, so without this a new English string would quietly
/// stay English in five languages; and a dropped `{amount}` would render
/// a sentence with the number missing.
void main() {
  Map<String, dynamic> read(String lang) => jsonDecode(
          File('lib/l10n/app_$lang.arb').readAsStringSync())
      as Map<String, dynamic>;
  final en = read('en');
  final keys = en.keys.where((k) => !k.startsWith('@')).toList();
  final ph = RegExp(r'\{(\w+)\}');
  Set<String> holes(String s) =>
      ph.allMatches(s).map((m) => m.group(1)!).toSet();

  for (final lang in ['hi', 'ta', 'kn', 'te', 'ml']) {
    test('$lang has every English message with the same placeholders', () {
      final t = read(lang);
      final missing = keys.where((k) => !t.containsKey(k)).toList();
      expect(missing, isEmpty, reason: 'missing in app_$lang.arb');
      for (final k in keys) {
        expect(holes(t[k] as String), holes(en[k] as String),
            reason: '$lang:$k placeholders differ');
      }
    });
  }
}
