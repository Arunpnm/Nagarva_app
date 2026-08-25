/// GST treatment and display — the calculator.
///
/// NAGARVA_GST_SPEC.md build order step 3. Pure arithmetic: no Supabase,
/// no widgets, no formatting. That is deliberate — it is the only way
/// cases 1-9 can be asserted without standing up a session, and the
/// spec requires those tests before any UI work.
///
/// Two rules here are load-bearing and easy to "simplify" into bugs:
///
/// 1. **Compute the tax once, then halve it.** Never compute CGST and
///    SGST independently as `taxable x rate/2` each. On an odd amount
///    that produces a one-paisa discrepancy against the total tax, which
///    is exactly what a GST reconciliation flags. Test case 8 (Rs 3,333
///    at 18%) exists solely to catch this and will fail if anyone
///    changes it.
///
/// 2. **Round once, at the end, and record the adjustment.** Section 170
///    of the CGST Act requires the final amount rounded to the nearest
///    rupee. `roundOff` is stored so the printed document reconciles
///    rather than appearing to be out by a few paise.
///
/// The split is computed in integer paise. Doing it in doubles and
/// subtracting is *almost* right, but `599.94 - 299.97` is
/// `299.96999999999997` in IEEE-754, so the two halves would not sum to
/// the tax when compared exactly. Integers make the invariant true by
/// construction instead of true to within a tolerance.
library;

/// Dimension A — changes the arithmetic. See spec §2.
enum GstTreatment {
  /// GST added on top of the taxable value. Default.
  exclusive,

  /// The stated amount already contains GST; back-compute the component.
  inclusive,

  /// No GST charged. Supply is exempt; requires a stated reason.
  exempt,

  /// No GST in the total. Prints "GST extra as applicable".
  extra,

  /// No GST, no mention anywhere.
  none;

  String get wire => name;

  static GstTreatment fromWire(String? s) => switch (s) {
        'inclusive' => GstTreatment.inclusive,
        'exempt' => GstTreatment.exempt,
        'extra' => GstTreatment.extra,
        'none' => GstTreatment.none,
        _ => GstTreatment.exclusive,
      };

  /// Only these two produce non-zero tax. `exempt`, `extra` and `none`
  /// are arithmetically identical and differ only in what is printed.
  bool get producesTax =>
      this == GstTreatment.exclusive || this == GstTreatment.inclusive;
}

/// Dimension B — changes the PDF only. See spec §2.
enum GstPrint {
  full,
  rateOnly,
  noteOnly,
  hidden;

  String get wire => switch (this) {
        GstPrint.full => 'full',
        GstPrint.rateOnly => 'rate_only',
        GstPrint.noteOnly => 'note_only',
        GstPrint.hidden => 'hidden',
      };

  static GstPrint fromWire(String? s) => switch (s) {
        'rate_only' => GstPrint.rateOnly,
        'note_only' => GstPrint.noteOnly,
        'hidden' => GstPrint.hidden,
        _ => GstPrint.full,
      };
}

/// CGST+SGST vs IGST. Null means "not determined" — never silently
/// treated as intra-state. See spec §6.
enum GstSplit {
  cgstSgst,
  igst;

  String get wire => this == GstSplit.cgstSgst ? 'cgst_sgst' : 'igst';

  static GstSplit? fromWire(String? s) => switch (s) {
        'cgst_sgst' => GstSplit.cgstSgst,
        'igst' => GstSplit.igst,
        _ => null,
      };
}

/// Rates permitted by the CHECK constraint. Enforced here too so the UI
/// cannot offer something Postgres will reject.
const kAllowedGstRates = <num>[0, 5, 12, 18, 28];

/// The six labels the user actually sees. The two-field model is the
/// presenter's job, not theirs — spec §2.
class GstOption {
  const GstOption(this.label, this.treatment, this.print);
  final String label;
  final GstTreatment treatment;
  final GstPrint print;
}

const kGstOptions = <GstOption>[
  GstOption('GST Charge Show In Quotation', GstTreatment.exclusive,
      GstPrint.full),
  GstOption('GST % Show & GST Charge Hide', GstTreatment.exclusive,
      GstPrint.rateOnly),
  GstOption('Without GST Quotation', GstTreatment.none, GstPrint.hidden),
  GstOption('GST Exempted', GstTreatment.exempt, GstPrint.noteOnly),
  GstOption('GST Extra', GstTreatment.extra, GstPrint.noteOnly),
  GstOption('GST Included in Subtotal', GstTreatment.inclusive, GstPrint.full),
];

/// The computed result. Every figure the document or the row needs.
class GstResult {
  const GstResult({
    required this.taxableValue,
    required this.taxTotal,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.total,
    required this.roundOff,
    required this.finalTotal,
  });

  /// Value tax is charged on: gross less discount (exclusive), or the
  /// back-computed net (inclusive).
  final double taxableValue;

  /// Total tax. Always equals cgst + sgst + igst, exactly.
  final double taxTotal;

  final double cgst;
  final double sgst;
  final double igst;

  /// Taxable + tax, before rupee rounding.
  final double total;

  /// finalTotal - total. Negative when rounding down. Store it.
  final double roundOff;

  /// What the customer pays, rounded to the nearest rupee.
  final double finalTotal;

  /// Invariant the split must always satisfy. Test case 8 asserts it;
  /// exposed so callers can assert it too rather than trusting.
  bool get splitReconciles =>
      ((cgst + sgst + igst) - taxTotal).abs() < 0.005;
}

double _round2(double v) => (v * 100).round() / 100;

/// Computes GST for one document.
///
/// [gross] is the sum of the charge lines. [discountAmount] is applied
/// to the taxable value BEFORE tax — the order is non-negotiable and the
/// reference UI confirms it ("Applicable on Sub-Total Amount"), spec §4.
///
/// [split] null means undetermined: the tax is computed but attributed
/// to neither side, so a caller cannot accidentally print CGST/SGST on
/// an interstate move. That is the §6 fail-safe, not an oversight.
GstResult computeGst({
  required double gross,
  required GstTreatment treatment,
  required num gstPct,
  double discountAmount = 0,
  GstSplit? split,
}) {
  final afterDiscount = gross - discountAmount;

  double taxableValue;
  double taxTotal;
  double total;

  switch (treatment) {
    case GstTreatment.exclusive:
      taxableValue = afterDiscount;
      taxTotal = _round2(taxableValue * gstPct / 100);
      total = taxableValue + taxTotal;

    case GstTreatment.inclusive:
      // Back-compute the net from a gross that already contains tax.
      taxableValue = _round2(afterDiscount / (1 + gstPct / 100));
      taxTotal = _round2(afterDiscount - taxableValue);
      total = afterDiscount;

    case GstTreatment.exempt:
    case GstTreatment.extra:
    case GstTreatment.none:
      // Arithmetically identical; they differ only in what is printed.
      taxableValue = afterDiscount;
      taxTotal = 0;
      total = taxableValue;
  }

  // ---- the split: compute once, then halve ----------------------------
  //
  // In paise, so the halves sum to the tax exactly rather than to within
  // a tolerance. `sgst` absorbs the odd paisa by taking the remainder.
  double cgst = 0, sgst = 0, igst = 0;
  final taxPaise = (taxTotal * 100).round();
  if (taxPaise != 0) {
    switch (split) {
      case GstSplit.cgstSgst:
        final cgstPaise = (taxPaise / 2).round();
        cgst = cgstPaise / 100;
        sgst = (taxPaise - cgstPaise) / 100;
      case GstSplit.igst:
        igst = taxPaise / 100;
      case null:
        // Undetermined. Tax is real and sits in the total, but it is
        // attributed to neither side so nothing can print a wrong
        // CGST/SGST line. splitReconciles is deliberately false here,
        // which is the signal a caller should surface as §6's "Verify
        // tax type" warning rather than quietly render.
        break;
    }
  }

  final finalTotal = total.roundToDouble();
  final roundOff = _round2(finalTotal - total);

  return GstResult(
    taxableValue: _round2(taxableValue),
    taxTotal: _round2(taxTotal),
    cgst: _round2(cgst),
    sgst: _round2(sgst),
    igst: _round2(igst),
    total: _round2(total),
    roundOff: roundOff,
    finalTotal: finalTotal,
  );
}

// ---------------------------------------------------------------------
// Document-type permission matrix — spec §5.
//
// This is not cosmetic validation. Rule 46 of the CGST Rules requires a
// tax invoice to state the taxable value, the rate and the amount of
// tax. Several treatments make that impossible, and shipping the
// quotation's control set unchanged onto an invoice would let a tenant
// issue a non-compliant one. They would not find out until an audit,
// and it would be Nagarva's defect rather than theirs.
// ---------------------------------------------------------------------

/// Why a combination cannot be used on a tax invoice, or null if it can.
String? invoiceRejectionReason(GstTreatment treatment, GstPrint print) {
  if (treatment == GstTreatment.exempt) {
    // Not a rejection — a document-type change. Caller issues a Bill of
    // Supply and suppresses the tax columns.
    return null;
  }
  if (!treatment.producesTax) {
    return treatment == GstTreatment.extra
        ? 'A tax invoice must state the tax, not defer it. '
            '"GST Extra" cannot be invoiced.'
        : 'A tax invoice must show GST. "Without GST" cannot be invoiced.';
  }
  if (print != GstPrint.full) {
    return 'A tax invoice must show the tax amount, not the rate alone.';
  }
  return null;
}

/// True when this combination may be issued as a tax invoice.
bool isInvoiceLegal(GstTreatment treatment, GstPrint print) =>
    treatment != GstTreatment.exempt &&
    invoiceRejectionReason(treatment, print) == null;

/// `exempt` is issued as a Bill of Supply, not a tax invoice. This is a
/// document-type change, not a print flag — spec §5.4.
bool requiresBillOfSupply(GstTreatment treatment) =>
    treatment == GstTreatment.exempt;
