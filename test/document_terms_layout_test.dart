// Renders every document that now carries the standard terms, so the
// terms block can be LOOKED AT rather than assumed to fit.
//
// Arun, 7 Sept 2026: "i need the basic terms and conditons in all
// documents" / "by deafult".
//
// The reason this exists rather than a unit test: three of these four
// documents are a FIXED `pw.Page`, not a `pw.MultiPage`. A fixed page
// does not flow — content added at the foot either fits or is clipped,
// silently, with no error and no failing test. The LR is the sharp case:
// it already carries a NOTICE, a full freight breakdown and a
// declaration paragraph on one page, and it is the document a consignor
// signs. Adding five terms to it is exactly the kind of change that
// looks correct in the diff and loses the signature line on the page.
//
// So this is a RENDER HARNESS: it asserts only that each document is a
// PDF of plausible size, and writes them all to build/terms_check/ to be
// read. The question it answers ("did the terms fit, and do they sit
// where they belong") has no assertion — only a rendered page.
//
// Run:    flutter test test/document_terms_layout_test.dart
// Output: build/terms_check/*.pdf
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/components/lr_pdf.dart';
import 'package:arun_p_k_r_s/components/money_receipt_pdf.dart';
import 'package:arun_p_k_r_s/components/pdf_branding.dart';
import 'package:arun_p_k_r_s/components/simple_document_pdf.dart';

/// APC as it really is: name and GSTIN, and nothing else. Inventing an
/// address here would review a letterhead they do not have.
const _org = OrgProfile(
  name: 'Arun Packers and Couriers',
  gstin: '33ARLPA3366M1ZO',
);

/// The shipped defaults, deliberately — an org that has written its own
/// terms is not the case at risk. The defaults are the longest thing
/// most vendors will ever print here.
const _boilerplate = DocumentBoilerplate();

Future<void> _write(String name, Uint8List bytes) async {
  expect(bytes.length, greaterThan(1000), reason: '$name produced no PDF');
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  final out = File('build/terms_check/$name.pdf');
  await out.parent.create(recursive: true);
  await out.writeAsBytes(bytes);
  // ignore: avoid_print
  print('wrote ${out.path} (${bytes.length} bytes)');
}

void main() {
  // Fonts come from the asset bundle; without the binding the PDF falls
  // back to a face with no rupee glyph, so the page reviewed would not
  // be the page the app produces.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('the standard terms are non-empty by default', () {
    // The one real assertion in the file. If this is ever empty, every
    // document below renders a blank where the terms should be and the
    // harness still "passes" — so pin it.
    expect(_boilerplate.standardTerms, isNotEmpty);
    expect(kDefaultStandardTerms.length, greaterThanOrEqualTo(4));
  });

  test('LR renders with terms on a fixed page', () async {
    // The densest document in the app, and the only one where the terms
    // compete with an existing NOTICE and declaration for one page.
    final bytes = await LrPdf.generate(
      org: _org,
      boilerplate: _boilerplate,
      copyTypes: const ['consignor'],
      lrNo: 'LR/2026-27/0007',
      lrDate: DateTime(2026, 9, 7),
      consigneeName: 'Meera Krishnan',
      consigneePhone: '9840012345',
      consigneeCity: 'Coimbatore',
      consigneeState: 'Tamil Nadu',
      fromPlace: 'Chennai',
      toPlace: 'Coimbatore',
      vehicleNo: 'TN-01-AB-1234',
      packageCount: 42,
      actualWeightKg: 1250,
      chargedWeightKg: 1250,
      freightAmount: 20000,
      gstAmount: 3600,
      totalAmount: 23600,
    );
    await _write('lr', bytes);
  });

  test('money receipt renders with terms', () async {
    final bytes = await MoneyReceiptPdf.generate(
      org: _org,
      boilerplate: _boilerplate,
      receiptNo: '2026/0011',
      receiptDate: DateTime(2026, 9, 7),
      receivedFrom: 'Meera Krishnan',
      phone: '9840012345',
      invoiceNo: '2026/0003',
      invoiceDate: DateTime(2026, 9, 7),
      isFinalPayment: false,
      fromPlace: 'Chennai',
      toPlace: 'Coimbatore',
      paymentMode: 'UPI',
      referenceNos: '429911003344',
      amount: 10000,
      amountInWords: 'Rupees Ten Thousand Only',
    );
    await _write('money_receipt', bytes);
  });

  test('proforma renders with terms (shared simple layout)', () async {
    // Stands in for all seven documents built on SimpleDocumentPdf — same
    // layout, same insertion point, so if the terms fit here they fit on
    // the packing list and the loading slip too.
    final bytes = await SimpleDocumentPdf.generate(
      docLabel: 'PROFORMA INVOICE',
      docNo: 'PRO/2026-27/0002',
      orgName: _org.name,
      metaLeft: const [
        MapEntry('Customer', 'Meera Krishnan'),
        MapEntry('Phone', '9840012345'),
      ],
      metaRight: const [
        MapEntry('Date', '07 Sep 2026'),
        MapEntry('Route', 'Chennai - Coimbatore'),
      ],
      tableHeaders: const ['Particulars', 'Amount'],
      tableRows: const [
        ['Freight / Transport', '20,000.00'],
        ['Packing Charge', '2,857.14'],
      ],
      totalLabel: 'Total',
      totalValue: '24,000.00',
      terms: kDefaultStandardTerms,
    );
    await _write('proforma', bytes);
  });
}
