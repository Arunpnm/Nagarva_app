// Renders a REAL invoice PDF so the signature block can be looked at.
//
// Arun, 7 Sept 2026, after saving APC's logo and signature: "check in
// real document and check whther it is properly align right above where
// it should be".
//
// The app can only be driven with a live Supabase session, and this
// session's had expired — so rather than report the layout unverified,
// this drives `InvoicePdf.generate` directly with APC's ACTUAL branding
// (the logo and signature fetched from their real storage URLs, the real
// name and GSTIN, and the real absence of everything else) and writes the
// PDF to disk to be read.
//
// It is a RENDER HARNESS, not an assertion test: there is no correct
// pixel position to assert against, and the question being asked is
// "does this look right", which only a human or a rendered page can
// answer. It asserts only that the bytes are a PDF, so it cannot pass
// while producing nothing.
//
// Run: flutter test test/invoice_signature_layout_test.dart
// Output: build/invoice_layout_check.pdf
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/components/invoice_pdf.dart';
import 'package:arun_p_k_r_s/components/pdf_branding.dart';

/// APC's real files. Fetched rather than committed: a checked-in copy
/// would go stale the moment the vendor redraws their signature, and
/// this harness exists precisely to look at what is live.
const _logoUrl =
    'https://hqqcapifefsaqvotqvlt.supabase.co/storage/v1/object/public/'
    'org-logos/b2c0c816-f282-44db-a8b4-9c0fc7478aee/logo.png';
const _signUrl =
    'https://hqqcapifefsaqvotqvlt.supabase.co/storage/v1/object/public/'
    'org-logos/b2c0c816-f282-44db-a8b4-9c0fc7478aee/signature.png';

Future<Uint8List?> _fetch(String url) async {
  try {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final b = <int>[];
    await for (final chunk in res) {
      b.addAll(chunk);
    }
    client.close();
    return Uint8List.fromList(b);
  } catch (_) {
    return null;
  }
}

void main() {
  // Without this, PdfBranding.loadFonts() cannot reach the asset bundle
  // and the PDF silently falls back to a font with no rupee glyph - so
  // the copy being reviewed would differ from the one the app produces,
  // in exactly the place (money) where that matters.
  TestWidgetsFlutterBinding.ensureInitialized();
  // ...and then hand real networking back. ensureInitialized installs an
  // HttpOverrides that refuses every request, which is right for a unit
  // test and wrong for this one: it silently returned null for both
  // images, so the run "passed" having rendered the very blank boxes it
  // exists to check. Nulling the override restores the real client.
  HttpOverrides.global = null;

  test('renders APC invoice with both signatures for layout review',
      () async {
    final logo = await _fetch(_logoUrl);
    final vendorSig = await _fetch(_signUrl);

    // Reported, not silently skipped: a null here means the layout was
    // reviewed WITHOUT the thing being reviewed.
    // ignore: avoid_print
    print('logo bytes: ${logo?.length}, vendor signature bytes: '
        '${vendorSig?.length}');

    // The org exactly as it really is: name and GSTIN, and nothing else.
    // Filling in a plausible address here would review a letterhead APC
    // does not have.
    const org = OrgProfile(
      name: 'Arun Packers and Couriers',
      gstin: '33ARLPA3366M1ZO',
    );

    final bytes = await InvoicePdf.generate(
      invoiceNo: '2026/0003',
      org: org,
      boilerplate: const DocumentBoilerplate(),
      customerName: 'Meera Krishnan',
      customerPhone: '9840012345',
      fromCity: 'Chennai',
      toCity: 'Coimbatore',
      baseAmount: 22857.14,
      interstate: false,
      igst: 0,
      cgst: 571.43,
      sgst: 571.43,
      total: 24000,
      logoBytes: logo,
      signatureBytes: vendorSig,
      // The CUSTOMER slot deliberately reuses the same image. This is a
      // layout check: what matters is whether two filled boxes sit level
      // and under the right captions, and reusing one known-good image
      // means any difference on the page is the LAYOUT's doing and not
      // the picture's.
      customerSignatureBytes: vendorSig,
      customerSignedByName: 'Meera Krishnan',
      customerSignedByPhone: '9840012345',
      customerSignedAt: DateTime(2026, 9, 7, 14, 30),
      particulars: const [
        MapEntry('Freight / Transport', 20000),
        MapEntry('Packing Charge', 2857.14),
      ],
      amountInWords: 'Rupees Twenty Four Thousand Only',
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    final out = File('build/invoice_layout_check.pdf');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes);
    // ignore: avoid_print
    print('wrote ${out.path} (${bytes.length} bytes)');
  });
}
