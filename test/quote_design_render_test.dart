// Renders a sample quotation in each Settings › Quote design theme, so the
// headers can be LOOKED AT (CLAUDE.md: a document is verified by rendering
// it). Asserts only that each is a PDF; writes them to build/quote_design/.
//
// Run:    flutter test test/quote_design_render_test.dart
// Output: build/quote_design/*.pdf
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/quote_design.dart';
import 'package:arun_p_k_r_s/components/pdf_branding.dart';
import 'package:arun_p_k_r_s/components/quote_pdf.dart';

const _org = OrgProfile(
  name: 'Arun Packers and Couriers',
  gstin: '33ARLPA3366M1ZO',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  for (final theme in kQuoteThemes) {
    test('quote renders in theme $theme', () async {
      final bytes = await QuotePdf.generate(
        design: QuoteDesign(theme: theme, color: '#D9480F'),
        leadRef: 'SAMPLE',
        org: _org,
        boilerplate: const DocumentBoilerplate(),
        customerName: 'Sample customer',
        fromCity: 'Chennai',
        toCity: 'Bengaluru',
        charges: const {'transport': 12000, 'packing': 3000},
        subtotal: 15000,
        gstPct: 18,
        gstAmount: 2700,
        total: 17700,
        interstate: true,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final out = File('build/quote_design/$theme.pdf');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes);
    });
  }
}
