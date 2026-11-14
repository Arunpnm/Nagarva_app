// One-off rewrite (3 Nov 2026): every user-visible `$e` / `${e}` inside a
// `catch (e)` block becomes `${friendlyError(e)}`, so no screen shows raw
// exception text again. Run from the repo root (run_friendly_errors.bat):
//   dart run _CHECK_BRANCHES/friendly_errors_rewrite.dart
// Writes _CHECK_BRANCHES/friendly_errors_report.txt. Safe to run twice.
import 'dart:io';

final _catchRe = RegExp(r'catch\s*\(\s*([A-Za-z_]\w*)');
const _skipLineMarkers = [
  'debugPrint(',
  'print(',
  'log(',
  'CrashReporting',
  'crashReporting',
  'recordError',
  'console',
];

void main() {
  final report = StringBuffer();
  var filesChanged = 0;
  var total = 0;
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final norm = f.path.replaceAll('\\', '/');
    if (norm.endsWith('backend/edge_function_errors.dart')) continue;
    if (norm.contains('/l10n/')) continue;
    final original = f.readAsStringSync();
    final crlf = original.contains('\r\n');
    final lines = original.replaceAll('\r\n', '\n').split('\n');
    var changed = 0;
    String? catchVar;
    var catchLine = -1000;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      final cm = _catchRe.allMatches(line).toList();
      if (cm.isNotEmpty) {
        catchVar = cm.last.group(1);
        catchLine = i;
      }
      if (catchVar == null || i - catchLine > 40) continue;
      if (_skipLineMarkers.any(line.contains)) continue;
      final v = RegExp.escape(catchVar);
      if (RegExp("['\"]\\\$\\{?$v\\}?['\"]\\s*\\.").hasMatch(line)) continue;
      final bare = RegExp('\\\$$v(?![A-Za-z0-9_])');
      final braced = RegExp('\\\$\\{$v\\}');
      if (!bare.hasMatch(line) && !braced.hasMatch(line)) continue;
      final repl = '\${friendlyError($catchVar)}';
      var out = line.replaceAll(braced, repl);
      out = out.replaceAllMapped(bare, (_) => repl);
      if (out != line) {
        lines[i] = out;
        changed++;
        report.writeln('$norm:${i + 1}: ${out.trim()}');
      }
    }
    if (changed > 0) {
      var src = lines.join('\n');
      if (!src.contains("edge_function_errors.dart'")) {
        final all =
            RegExp(r'^import .*;\s*$', multiLine: true).allMatches(src).toList();
        if (all.isNotEmpty) {
          final end = all.last.end;
          src = '${src.substring(0, end)}\n'
              "import '/backend/edge_function_errors.dart';"
              '${src.substring(end)}';
        }
      }
      if (crlf) src = src.replaceAll('\n', '\r\n');
      f.writeAsStringSync(src);
      filesChanged++;
      total += changed;
    }
  }
  report.writeln('\nFiles changed: $filesChanged, lines: $total');
  File('_CHECK_BRANCHES/friendly_errors_report.txt')
      .writeAsStringSync(report.toString());
  stdout.writeln('Done. Files: $filesChanged, lines: $total');
}
