// Render harness for the three documents added 13 Nov 2026 (customer
// declaration, insurance / owner's risk declaration, credit note). They
// share SimpleDocumentPdf's FIXED page, which clips silently, so the
// only honest check is to render them and look.
// Run:    flutter test test/new_docs_render_test.dart
// Output: build/new_docs/*.pdf
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/components/pdf_branding.dart';
import 'package:arun_p_k_r_s/components/simple_document_pdf.dart';

void main() {
  final out = Directory('build/new_docs')..createSync(recursive: true);
  Future<void> save(String name, Future<List<int>> f) async {
    final b = await f;
    expect(b.length, greaterThan(3000));
    File('${out.path}/$name.pdf').writeAsBytesSync(b);
  }

  test('customer declaration fits one page', () async {
    await save(
        'customer_declaration',
        SimpleDocumentPdf.generate(
          terms: kDefaultStandardTerms,
          docLabel: 'CUSTOMER DECLARATION',
          docNo: 'TEST-MOVERS-PVT-LTD-1004',
          orgName: 'TEST Movers Pvt Ltd',
          metaLeft: const [
            MapEntry('Customer', 'TEST Accepted Journey 2'),
            MapEntry('Phone', '9000000000'),
            MapEntry('Route', 'Coimbatore to Chennai'),
          ],
          metaRight: const [
            MapEntry('Order Ref', 'TEST-MOVERS-PVT-LTD-1004'),
            MapEntry('Date', '13 Nov 2026'),
          ],
          notesBlock: 'I declare that:\n\n'
              '1. The goods handed over for moving are my own household or office goods, and I have the right to move them.\n\n'
              '2. The consignment contains NO cash, jewellery, gold, silver, precious stones, or important original documents.\n\n'
              '3. The consignment contains NO liquor, narcotics, arms, ammunition, explosives, gas cylinders, acids, or any item banned by law.\n\n'
              '4. The consignment contains NO inflammable or perishable goods, live plants or animals.\n\n'
              '5. Fuel has been drained from any vehicle or appliance handed over, as far as possible.\n\n'
              '6. I have checked the packing list and it matches the goods handed over.\n\n'
              'I understand that the mover is not responsible for any '
              'item listed in points 2 to 4 if it is placed in the '
              'consignment, or for any loss, penalty or delay that '
              'results from it.',
        ));
  });

  test('insurance declaration fits one page', () async {
    await save(
        'insurance_declaration',
        SimpleDocumentPdf.generate(
          terms: kDefaultStandardTerms,
          docLabel: 'TRANSIT INSURANCE DECLARATION',
          docNo: 'TEST-MOVERS-PVT-LTD-1004',
          orgName: 'TEST Movers Pvt Ltd',
          metaLeft: const [MapEntry('Customer', 'TEST Accepted Journey 2')],
          metaRight: const [MapEntry('Date', '13 Nov 2026')],
          tableHeaders: const ['PARTICULARS', 'DETAILS'],
          tableRows: const [
            ['Cover chosen', 'Transit insurance'],
            ['Value of goods declared by customer', '₹2,00,000.00'],
          ],
          notesBlock:
              'I declare that the value of my goods stated above is true and '
              'correct, and I have asked for them to be insured in transit '
              'for this value. I understand that a claim is settled by the '
              'insurance company under its own terms, on the documents it '
              'asks for, and that damage or loss must be noted on the '
              'delivery receipt at the time of delivery.',
        ));
  });

  test('credit note fits one page', () async {
    await save(
        'credit_note',
        SimpleDocumentPdf.generate(
          docLabel: 'CREDIT NOTE',
          docNo: 'CN/2026-27/0001',
          orgName: 'TEST Movers Pvt Ltd',
          metaLeft: const [
            MapEntry('Issued To', 'TEST Customer Lakshmi'),
            MapEntry('Against Invoice', 'INV/2026-27/0004'),
          ],
          metaRight: const [
            MapEntry('No', 'CN/2026-27/0001'),
            MapEntry('Date', '13 Nov 2026'),
            MapEntry('Type', 'Invoice reduced'),
          ],
          tableHeaders: const ['DESCRIPTION', 'AMOUNT'],
          tableRows: const [
            ['Damage to one chair, agreed with customer', '₹1,000.00'],
            ['GST @ 18%', '₹180.00'],
          ],
          totalLabel: 'AMOUNT CREDITED',
          totalValue: '₹1,180.00',
          signatureLabel: 'Authorised Signatory',
          notesBlock: 'The invoice named above is reduced by this amount.',
        ));
  });
}
