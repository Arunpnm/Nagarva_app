// Rule 46 invoice guard — one fixture per branch, executed.
//
// The first version of this guard checked `address` alone and therefore
// passed an invoice carrying APC Bengaluru's `29AAAAA0000A1Z5`, the
// specimen GSTIN from GST documentation. That is the case this file
// exists for: a check that reasons correctly about the fields it looks at
// and never looks at the one that matters.
//
// Run: flutter test test/invoice_compliance_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/invoice_compliance.dart';
import 'package:arun_p_k_r_s/components/pdf_branding.dart';

/// A fully compliant org. Every test below breaks exactly one thing in it,
/// so a failure names the field that broke rather than the whole fixture.
OrgProfile good({
  String? name = 'Arun Packers and Couriers',
  String? address = '12 Mount Road',
  String? city = 'Chennai',
  String? state = 'Tamil Nadu',
  int? stateCode = 33,
  String? pincode = '600002',
  String? gstin = '33ARLPA3366M1ZO',
}) =>
    OrgProfile(
      name: name ?? '',
      address: address,
      city: city,
      state: state,
      stateCode: stateCode,
      pincode: pincode,
      gstin: gstin,
    );

Set<InvoiceComplianceKind> kinds(OrgProfile o) =>
    checkInvoiceCompliance(o).map((i) => i.kind).toSet();

InvoiceComplianceIssue only(OrgProfile o, InvoiceComplianceKind k) =>
    checkInvoiceCompliance(o).firstWhere((i) => i.kind == k);

void main() {
  test('a complete, real profile raises nothing', () {
    expect(checkInvoiceCompliance(good()), isEmpty);
  });

  group('Rule 46 required fields — one at a time', () {
    final cases = <String, OrgProfile>{
      'business name': good(name: null),
      'address': good(address: null),
      'city': good(city: null),
      'state': good(state: null),
      'state code': good(stateCode: null),
      'PIN code': good(pincode: null),
      'GSTIN': good(gstin: null),
    };

    cases.forEach((field, org) {
      test('missing $field is reported', () {
        final issue = only(org, InvoiceComplianceKind.incompleteProfile);
        expect(issue.fields, contains(field));
        expect(issue.fields, hasLength(1),
            reason: 'only $field was removed, so only $field should be named');
        expect(issue.message, contains(field));
      });
    });
  });

  group('blank is missing, not present', () {
    test('whitespace-only address counts as missing', () {
      // nullif(trim(x),'') semantics. A field of spaces prints as an empty
      // line on the invoice, which is exactly as non-compliant as a null.
      final issue = only(good(address: '   '),
          InvoiceComplianceKind.incompleteProfile);
      expect(issue.fields, ['address']);
    });

    test('whitespace-only GSTIN is missing, NOT malformed', () {
      final k = kinds(good(gstin: '  '));
      expect(k, contains(InvoiceComplianceKind.incompleteProfile));
      expect(k, isNot(contains(InvoiceComplianceKind.gstinMalformed)),
          reason: 'an absent GSTIN is unfinished paperwork, not a false one');
    });
  });

  group('a false GSTIN is not an incomplete one', () {
    test('the live APC Bengaluru value is caught as a SPECIMEN', () {
      // 29AAAAA0000A1Z5 — well-formed, passes the pattern, and is the
      // documentation example. The whole reason a format check alone is
      // not enough.
      final org = good(gstin: '29AAAAA0000A1Z5', stateCode: 29);
      final k = kinds(org);
      expect(k, contains(InvoiceComplianceKind.gstinSpecimen));
      expect(k, isNot(contains(InvoiceComplianceKind.gstinMalformed)),
          reason: 'it is perfectly well-formed, which is the problem');
      expect(k, isNot(contains(InvoiceComplianceKind.incompleteProfile)),
          reason: 'nothing is missing — the value present is false');

      final issue = only(org, InvoiceComplianceKind.gstinSpecimen);
      expect(issue.isFalseDocument, isTrue);
      expect(issue.title, isNot(contains('missing')));
      expect(issue.title.toLowerCase(), contains('specimen'));
      // The body has to say what is actually wrong, not just that
      // something is: it names the documentation example and what issuing
      // it asserts.
      expect(issue.message.toLowerCase(), contains('documentation'));
      expect(issue.message, contains(kSpecimenPanSegment));
    });

    test('malformed GSTIN gets its own wording, not the missing-field text',
        () {
      final org = good(gstin: 'NOT-A-GSTIN');
      final issue = only(org, InvoiceComplianceKind.gstinMalformed);
      expect(issue.isFalseDocument, isTrue);
      expect(kinds(org), isNot(contains(InvoiceComplianceKind.gstinSpecimen)));
      // The two texts must never converge; that is the point of the split.
      final incomplete =
          only(good(address: null), InvoiceComplianceKind.incompleteProfile);
      expect(issue.message, isNot(equals(incomplete.message)));
      expect(issue.title, isNot(equals(incomplete.title)));
    });

    test('a malformed GSTIN does not also raise a state-code mismatch', () {
      // Its leading characters are not a state code, so comparing them
      // would produce a second complaint about the same broken field.
      expect(kinds(good(gstin: 'XX', stateCode: 33)),
          isNot(contains(InvoiceComplianceKind.stateCodeMismatch)));
    });

    test('lowercase is normalised before judging', () {
      expect(checkInvoiceCompliance(good(gstin: '33arlpa3366m1zo')), isEmpty);
    });
  });

  group('state code vs the state inside the GSTIN', () {
    test('mismatch is reported with its own message', () {
      final org = good(gstin: '33ARLPA3366M1ZO', stateCode: 29);
      final issue = only(org, InvoiceComplianceKind.stateCodeMismatch);
      expect(issue.message, contains('29'));
      expect(issue.message, contains('33'));
      expect(issue.kind, isNot(InvoiceComplianceKind.incompleteProfile));
    });

    test('matching state code is silent', () {
      expect(kinds(good(gstin: '33ARLPA3366M1ZO', stateCode: 33)),
          isNot(contains(InvoiceComplianceKind.stateCodeMismatch)));
    });

    test('no state code means missing, not mismatched', () {
      final k = kinds(good(stateCode: null));
      expect(k, contains(InvoiceComplianceKind.incompleteProfile));
      expect(k, isNot(contains(InvoiceComplianceKind.stateCodeMismatch)));
    });
  });

  test('the three live orgs, exactly as the database holds them today', () {
    // address/city/state/state_code/pincode are NULL on all three.
    final apc = good(
        address: null, city: null, state: null, stateCode: null,
        pincode: null, gstin: '33ARLPA3366M1ZO');
    expect(kinds(apc), {InvoiceComplianceKind.incompleteProfile});

    final blr = good(
        name: 'APC Bengaluru',
        address: null, city: null, state: null, stateCode: null,
        pincode: null, gstin: '29AAAAA0000A1Z5');
    expect(kinds(blr), {
      InvoiceComplianceKind.gstinSpecimen,
      InvoiceComplianceKind.incompleteProfile,
    }, reason: 'a fabricated GSTIN AND an empty address are both true');

    // Coimbatore shares its parent's GSTIN, and that is CORRECT — one
    // registration covers multiple places of business within a state, so
    // two orgs under the same GSTIN is lawful and needs no warning. An
    // earlier version of this file asserted the shared number as a
    // "known gap"; it was not a gap, and detecting it would have fired
    // on a legitimate setup. The real error of this shape is a Bengaluru
    // org carrying a 33 (Tamil Nadu) number, which the state-code check
    // above catches once state_code is filled in.
    final cbe = good(
        name: 'APC Coimbatore',
        address: null, city: null, state: null, stateCode: null,
        pincode: null, gstin: '33ARLPA3366M1ZO');
    expect(kinds(cbe), {InvoiceComplianceKind.incompleteProfile});
  });

  test('the most serious issue is first', () {
    final issues = checkInvoiceCompliance(good(
        gstin: '29AAAAA0000A1Z5', address: null, stateCode: 29));
    expect(issues.first.kind, InvoiceComplianceKind.gstinSpecimen,
        reason: 'a false document outranks an unfinished one');
  });
}
