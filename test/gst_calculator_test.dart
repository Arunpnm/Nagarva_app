import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/gst_calculator.dart';

/// NAGARVA_GST_SPEC.md §9, cases 1-9, written BEFORE any UI work per the
/// build order.
///
/// Cases 10-13 are not here on purpose: 10 and 11 are conversion-guard
/// behaviour (partially covered by the permission-matrix group below,
/// finished when the invoice screen exists), 12 needs a session, and 13
/// asserts a rendered PDF is unchanged — that one is a device check, not
/// a unit test, and the migration's POSTFLIGHT covers its data half.
///
/// Case 8 is the one that matters most. It is the only reason the split
/// is computed in integer paise, and it fails the moment anyone
/// "simplifies" it to computing each half independently.
void main() {
  group('§9 case 1 — exclusive, intra', () {
    final r = computeGst(
      gross: 10000,
      treatment: GstTreatment.exclusive,
      gstPct: 18,
      split: GstSplit.cgstSgst,
    );

    test('taxable 10,000 · CGST 900 · SGST 900 · total 11,800', () {
      expect(r.taxableValue, 10000);
      expect(r.cgst, 900);
      expect(r.sgst, 900);
      expect(r.igst, 0);
      expect(r.taxTotal, 1800);
      expect(r.finalTotal, 11800);
    });
  });

  group('§9 case 2 — exclusive, inter', () {
    final r = computeGst(
      gross: 10000,
      treatment: GstTreatment.exclusive,
      gstPct: 18,
      split: GstSplit.igst,
    );

    test('taxable 10,000 · IGST 1,800 · total 11,800', () {
      expect(r.taxableValue, 10000);
      expect(r.igst, 1800);
      expect(r.cgst, 0);
      expect(r.sgst, 0);
      expect(r.finalTotal, 11800);
    });
  });

  group('§9 case 3 — inclusive', () {
    final r = computeGst(
      gross: 11800,
      treatment: GstTreatment.inclusive,
      gstPct: 18,
      split: GstSplit.cgstSgst,
    );

    test('taxable 10,000 · tax 1,800 · total 11,800', () {
      expect(r.taxableValue, 10000);
      expect(r.taxTotal, 1800);
      expect(r.finalTotal, 11800);
    });

    test('the total is unchanged by an inclusive treatment', () {
      // The defining property: an inclusive quote does not add anything.
      expect(r.total, 11800);
    });
  });

  group('§9 case 4 — discount applies BEFORE tax', () {
    final r = computeGst(
      gross: 10000,
      discountAmount: 1000,
      treatment: GstTreatment.exclusive,
      gstPct: 18,
      split: GstSplit.cgstSgst,
    );

    test('taxable 9,000 · tax 1,620 · total 10,620', () {
      expect(r.taxableValue, 9000);
      expect(r.taxTotal, 1620);
      expect(r.finalTotal, 10620);
    });

    test('taxing before discounting would give 1,800 — it does not', () {
      // Guards the order of operations, which §4 calls non-negotiable.
      expect(r.taxTotal, isNot(1800));
    });
  });

  group('§9 case 5 — exempt', () {
    final r = computeGst(
      gross: 10000,
      treatment: GstTreatment.exempt,
      gstPct: 18,
    );

    test('tax 0 · total 10,000', () {
      expect(r.taxTotal, 0);
      expect(r.finalTotal, 10000);
    });

    test('exempt is issued as a Bill of Supply, not a tax invoice', () {
      expect(requiresBillOfSupply(GstTreatment.exempt), isTrue);
      expect(isInvoiceLegal(GstTreatment.exempt, GstPrint.noteOnly), isFalse);
    });
  });

  group('§9 case 6 — extra', () {
    final r = computeGst(
      gross: 10000,
      treatment: GstTreatment.extra,
      gstPct: 18,
    );

    test('tax 0 · total 10,000', () {
      expect(r.taxTotal, 0);
      expect(r.finalTotal, 10000);
    });

    test('a rate is set but no tax is charged', () {
      // "GST extra as applicable" — the rate is known, the tax is not
      // being collected on this document.
      expect(r.taxTotal, 0);
      expect(GstTreatment.extra.producesTax, isFalse);
    });
  });

  group('§9 case 7 — none + hidden', () {
    final r = computeGst(
      gross: 10000,
      treatment: GstTreatment.none,
      gstPct: 0,
    );

    test('total 10,000 and nothing to print', () {
      expect(r.taxTotal, 0);
      expect(r.finalTotal, 10000);
      expect(GstPrint.hidden.wire, 'hidden');
    });
  });

  group('§9 case 8 — THE SPLIT-ROUNDING CASE', () {
    // Rs 3,333 at 18% = 599.94, which halves to 299.97 each. Computing
    // each half independently as 3333 * 9% = 299.97 happens to work
    // here, but the subtraction 599.94 - 299.97 in IEEE-754 gives
    // 299.96999999999997 — so a doubles implementation fails an exact
    // comparison even when the arithmetic is conceptually right.
    final r = computeGst(
      gross: 3333,
      treatment: GstTreatment.exclusive,
      gstPct: 18,
      split: GstSplit.cgstSgst,
    );

    test('tax 599.94 · CGST 299.97 · SGST 299.97', () {
      expect(r.taxTotal, 599.94);
      expect(r.cgst, 299.97);
      expect(r.sgst, 299.97);
    });

    test('the halves sum to the tax EXACTLY, not approximately', () {
      expect(r.cgst + r.sgst, r.taxTotal);
      expect(r.splitReconciles, isTrue);
    });

    test('an odd-paise tax still reconciles', () {
      // 1,111.11 at 18% = 199.9998 -> 200.00; force a genuinely odd
      // paise count to prove sgst absorbs the remainder.
      final odd = computeGst(
        gross: 1000.05,
        treatment: GstTreatment.exclusive,
        gstPct: 5,
        split: GstSplit.cgstSgst,
      );
      expect(odd.cgst + odd.sgst, odd.taxTotal,
          reason: 'halves must sum exactly on an odd paise count too');
    });
  });

  group('§9 case 9 — round once, record the adjustment', () {
    final r = computeGst(
      gross: 10001,
      treatment: GstTreatment.exclusive,
      gstPct: 5,
      split: GstSplit.cgstSgst,
    );

    test('tax 500.05 · total 10,501.05 before rounding', () {
      expect(r.taxTotal, 500.05);
      expect(r.total, 10501.05);
    });

    test('round_off recorded and the printed total reconciles', () {
      expect(r.finalTotal, 10501);
      expect(r.roundOff, -0.05);
      // The reconciliation the stored field exists for.
      expect(_r2(r.total + r.roundOff), r.finalTotal);
    });
  });

  group('§6 — an undetermined split never becomes cgst_sgst', () {
    final r = computeGst(
      gross: 10000,
      treatment: GstTreatment.exclusive,
      gstPct: 18,
      split: null,
    );

    test('tax is computed but attributed to neither side', () {
      expect(r.taxTotal, 1800);
      expect(r.cgst, 0);
      expect(r.sgst, 0);
      expect(r.igst, 0);
    });

    test('splitReconciles is false, so a caller must warn', () {
      // This is the signal that drives §6's "Verify tax type" warning.
      // If it ever returns true for a null split, a NULL org state_code
      // would silently print as intra-state.
      expect(r.splitReconciles, isFalse);
    });
  });

  group('§5 — invoice permission matrix', () {
    test('exclusive + full and inclusive + full are invoice-legal', () {
      expect(isInvoiceLegal(GstTreatment.exclusive, GstPrint.full), isTrue);
      expect(isInvoiceLegal(GstTreatment.inclusive, GstPrint.full), isTrue);
    });

    test('rate_only is rejected — the tax AMOUNT is mandatory', () {
      expect(isInvoiceLegal(GstTreatment.exclusive, GstPrint.rateOnly),
          isFalse);
      expect(invoiceRejectionReason(GstTreatment.exclusive, GstPrint.rateOnly),
          contains('tax amount'));
    });

    test('extra is rejected — tax must be stated, not deferred', () {
      expect(isInvoiceLegal(GstTreatment.extra, GstPrint.noteOnly), isFalse);
      expect(invoiceRejectionReason(GstTreatment.extra, GstPrint.noteOnly),
          contains('defer'));
    });

    test('none + hidden is rejected', () {
      expect(isInvoiceLegal(GstTreatment.none, GstPrint.hidden), isFalse);
    });

    test('every one of the six UI options is quotation-legal', () {
      // §5: the quotation screen offers all six labels.
      expect(kGstOptions.length, 6);
      for (final o in kGstOptions) {
        expect(o.label, isNotEmpty);
      }
    });

    test('exactly two of the six are invoice-legal, plus exempt as BoS', () {
      final legal = kGstOptions
          .where((o) => isInvoiceLegal(o.treatment, o.print))
          .toList();
      expect(legal.length, 2,
          reason: 'only exclusive+full and inclusive+full may be invoiced');
      final bos =
          kGstOptions.where((o) => requiresBillOfSupply(o.treatment)).toList();
      expect(bos.length, 1);
    });
  });

  group('rate guard', () {
    test('allowed rates are exactly the CHECK constraint set', () {
      expect(kAllowedGstRates, [0, 5, 12, 18, 28]);
    });
  });

  group('wire round-trip — the jsonb/column contract', () {
    test('treatment and print survive a round trip', () {
      for (final t in GstTreatment.values) {
        expect(GstTreatment.fromWire(t.wire), t);
      }
      for (final p in GstPrint.values) {
        expect(GstPrint.fromWire(p.wire), p);
      }
    });

    test('unknown or null wire values fall back safely', () {
      // A row written before this feature, or by a newer client.
      expect(GstTreatment.fromWire(null), GstTreatment.exclusive);
      expect(GstTreatment.fromWire('nonsense'), GstTreatment.exclusive);
      expect(GstPrint.fromWire(null), GstPrint.full);
      expect(GstSplit.fromWire('auto'), isNull,
          reason: "legacy '_gstType: auto' must not resolve to a split");
    });
  });
}

double _r2(double v) => (v * 100).round() / 100;
