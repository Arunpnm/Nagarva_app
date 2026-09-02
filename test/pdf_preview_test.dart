// Document preview harness.
//
// Not an assertion test — a way to SEE what the PDF generators actually
// produce. Document layout is the one thing that cannot be reviewed by
// reading Dart: `pw.Row`/`pw.Table` code says nothing about whether a
// signature block lines up or a label column is too wide.
//
// Writes real PDFs to build/pdf_preview/ using representative data, so a
// styling change can be rendered and compared against the reference
// documents rather than guessed at.
//
//   flutter test test/pdf_preview_test.dart
//
// Fonts are fetched by PdfGoogleFonts over the network, so this needs
// connectivity — the same fetch the app performs on every generation.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/components/invoice_pdf.dart';
import 'package:arun_p_k_r_s/components/money_receipt_pdf.dart';
import 'package:arun_p_k_r_s/components/pdf_branding.dart';

/// Mirrors the live APC profile closely enough that the header renders
/// with every band populated — affiliation strip, phones, branch list and
/// the bank block all have to be present to judge the layout.
const _org = OrgProfile(
  name: 'ARUN PACKERS AND COURIERS',
  tagline: 'Moving You Towards Your Future',
  address: 'Mangammanapalya Main Rd, Munireddy Layout, Hosapalya, '
      'Garvebhavi Palya, Bangalore, Karnataka 560068',
  gstin: '33ARLPA3366M1ZO',
  pan: 'ARLPA3366M',
  phones: ['7411628282', '7483643243', '7411028282', '7411328282'],
  landline: '08049722698',
  udyamNo: 'UDYAM-TN-06-0000647',
  affiliationText: 'Affiliated By: Govt Of Karnataka',
  branchListText: 'Chennai, Coimbatore, Hyderabad & Bengaluru',
  website: 'https://www.arunpackersandcouriers.com/',
  email: 'arunpackersandcouriers@gmail.com',
  signatoryName: 'Arun Kumar Sellamuthu',
  beneficiaryName: 'Arun Kumar Sellamuthu',
  bankName: 'HDFC',
  bankAccountNo: '50100332455673',
  bankIfsc: 'HDFC0002228',
  upiId: '7411628282@ibl',
  upiDisplayNumber: '7411628282',
);

const _boilerplate = DocumentBoilerplate();

Future<void> _write(String name, List<int> bytes) async {
  final dir = Directory('build/pdf_preview');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes);
  // ignore: avoid_print
  print('WROTE ${f.path} (${bytes.length} bytes)');
}

void main() {
  test('tax invoice renders', () async {
    final bytes = await InvoicePdf.generate(
      invoiceNo: '2026/0001',
      org: _org,
      boilerplate: _boilerplate,
      customerName: 'Priya Raghavan',
      customerPhone: '9445067890',
      fromCity: 'Chennai',
      toCity: 'Bengaluru',
      fromAddress: '12/4 Anna Nagar West, 2nd Floor, Chennai 600040',
      toAddress: 'No 7 HSR Layout Sector 2, Ground Floor, Bengaluru 560102',
      baseAmount: 36000,
      interstate: false,
      igst: 0,
      cgst: 900,
      sgst: 900,
      total: 37800,
      billingDate: DateTime(2026, 9, 2),
      deliveryDate: DateTime(2026, 9, 16),
      vehicleNo: 'TN 01 AB 4521',
      packageCount: 9,
      actualWeightKg: 1450,
      chargedWeightKg: 1500,
      remark: 'Moving Used House Hold Items',
      paymentRemark: 'Advance received by UPI',
      gstPayableBy: 'Consignee',
      lrNo: 'LR0001',
      // The real charge heads a quotation carries — without these the
      // renderer falls back to a single freight line, which is a harness
      // artefact and not what a real order produces.
      particulars: const [
        MapEntry('Freight', 22000),
        MapEntry('Packing Charge', 2500),
        MapEntry('Loading Charge', 3500),
        MapEntry('Un Loading Charge', 3000),
        MapEntry('Packing Material Charge', 3000),
        MapEntry('Advance Paid', 2000),
      ],
      amountInWords: 'Thirty Seven Thousand Eight Hundred Rupees Only',
      isPaid: true,
    );
    await _write('invoice.pdf', bytes);
    expect(bytes.length, greaterThan(1000));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('money receipt renders', () async {
    final bytes = await MoneyReceiptPdf.generate(
      org: _org,
      boilerplate: _boilerplate,
      receiptNo: '2026/0001',
      receiptDate: DateTime(2026, 9, 2),
      receivedFrom: 'Priya Raghavan',
      isFinalPayment: true,
      paymentMode: 'CASH',
      amount: 37800,
    );
    await _write('money_receipt.pdf', bytes);
    expect(bytes.length, greaterThan(1000));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
