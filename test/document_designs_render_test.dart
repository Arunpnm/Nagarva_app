// Render harness for the document designs (13 Nov 2026): the six header
// layouts, each in a different colour, on a shared-layout document and
// on the money receipt (the full statutory header). Fixed pages clip
// silently, so these are rendered to be LOOKED AT.
// Run:    flutter test test/document_designs_render_test.dart
// Output: build/designs/*.pdf
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/quote_design.dart';
import 'package:arun_p_k_r_s/components/money_receipt_pdf.dart';
import 'package:arun_p_k_r_s/components/pdf_branding.dart';
import 'package:arun_p_k_r_s/components/simple_document_pdf.dart';

const _org = OrgProfile(
  name: 'TEST Movers Pvt Ltd',
  gstin: '33ABCDE1234F1Z5',
  pan: 'ABCDE1234F',
  tagline: 'Safe hands for every move',
  address: '12 Anna Salai, Chennai 600002',
  phones: ['9000000001', '9000000002'],
  email: 'hello@testmovers.example',
);

void main() {
  final out = Directory('build/designs')..createSync(recursive: true);
  tearDown(() => PdfBranding.designOverride = null);

  for (var i = 0; i < kQuoteThemes.length; i++) {
    final theme = kQuoteThemes[i];
    final color = kDocumentColors[(i * 2 + 1) % kDocumentColors.length];
    test('theme $theme renders', () async {
      PdfBranding.designOverride = QuoteDesign(theme: theme, color: color);
      final a = await SimpleDocumentPdf.generate(
        terms: kDefaultStandardTerms,
        docLabel: 'PROFORMA INVOICE',
        docNo: 'PF/2026-27/0007',
        orgName: _org.name,
        profile: const {
          'tagline': 'Safe hands for every move',
          'address': '12 Anna Salai, Chennai 600002',
          'phone1': '9000000001',
          'email': 'hello@testmovers.example',
          'gstin': '33ABCDE1234F1Z5',
        },
        metaLeft: const [
          MapEntry('Prepared For', 'TEST Customer Lakshmi'),
          MapEntry('Route', 'Chennai to Bengaluru'),
        ],
        metaRight: const [
          MapEntry('No', 'PF/2026-27/0007'),
          MapEntry('Date', '13 Nov 2026'),
        ],
        tableHeaders: const ['DESCRIPTION', 'AMOUNT'],
        tableRows: const [
          ['Estimated moving charges', '₹18,000.00'],
          ['Packing material', '₹2,500.00'],
          ['GST @ 18%', '₹3,690.00'],
        ],
        totalLabel: 'ESTIMATED TOTAL',
        totalValue: '₹24,190.00',
      );
      expect(a.length, greaterThan(3000));
      File('${out.path}/proforma_$theme.pdf').writeAsBytesSync(a);

      final b = await MoneyReceiptPdf.generate(
        org: _org,
        boilerplate: const DocumentBoilerplate(),
        receiptNo: 'MR/2026-27/0012',
        receiptDate: DateTime(2026, 11, 13),
        receivedFrom: 'TEST Customer Lakshmi',
        isFinalPayment: false,
        fromPlace: 'Chennai',
        toPlace: 'Bengaluru',
        paymentMode: 'UPI',
        amount: 5000,
        amountInWords: 'Five thousand rupees only',
      );
      expect(b.length, greaterThan(3000));
      File('${out.path}/receipt_$theme.pdf').writeAsBytesSync(b);
    });
  }
}
