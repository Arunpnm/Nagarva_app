import 'lead_status.dart';

/// Per-stage state for the lead pipeline, computed from EVIDENCE rather
/// than inferred from the lead's status ordinal.
///
/// THE BUG THIS EXISTS TO KILL (12 Sept 2026). `LeadStatusStrip` rendered
/// every stage with `done: i < currentIdx`, where `currentIdx` came from
/// the lead's single `status` column. So advancing a lead to `quoted` —
/// which `_reconcileStatusFromProgress` does automatically the moment a
/// quote is saved — retroactively ticked SURVEY, whether or not a survey
/// had ever been submitted.
///
/// It was not one lead. **Two of the six confirmed leads had no submitted
/// survey**, so the strip had been claiming "Survey ✓" on completed jobs
/// that were never surveyed, next to an affordance on the same screen
/// correctly saying "awaiting customer response". Two sources, one fact,
/// disagreeing in front of the vendor.
///
/// FIXING THE TICK STYLE ALONE WOULD NOT HAVE FIXED IT (Arun's call). The
/// root cause is that each step's state came from the ordinal instead of
/// from its own record; restyling leaves that inference in place and it
/// drifts again the next time a stage is skipped. So each stage now reads
/// ITS OWN evidence, and the ordinal goes back to meaning only what it
/// says: where the lead currently sits.
///
///   Survey   a submitted `customer_surveys` row
///   Quoted   a live `quotations` row
///   Order    a live `orders` row
///
/// `new` and `follow_up` have no separate record to read — there is no
/// "a follow-up happened" table — so they stay positional, and that is
/// stated here rather than left to be discovered as an inconsistency.
enum LeadStageState {
  /// Evidence exists. This genuinely happened.
  done,

  /// The lead has advanced PAST this stage and there is no evidence it
  /// happened. Legitimate and common — a vendor who measures the job
  /// themselves never sends a survey — so it is rendered as a distinct
  /// "skipped" mark, neither a tick (a lie) nor a gap (reads as broken).
  skipped,

  /// Where the lead is now.
  current,

  /// Not reached yet.
  pending,
}

/// What each stage can point at as proof it happened.
///
/// Nullable on purpose: a caller that has not loaded a given record
/// passes null and gets `skipped`/`pending` rather than a false `done`.
/// Failing towards "we cannot show this happened" is the safe direction —
/// the opposite is the bug above.
class LeadStageEvidence {
  const LeadStageEvidence({
    this.surveySubmitted = false,
    this.hasQuote = false,
    this.hasOrder = false,
  });

  /// `customer_surveys.submitted_at is not null`. NOT `status == 'submitted'`
  /// — the timestamp is the fact, the status is a label on it, and where
  /// two columns describe one event the one carrying data wins.
  final bool surveySubmitted;

  /// A live (non-deleted) quotation on this lead.
  final bool hasQuote;

  /// A live order converted from this lead's quote.
  final bool hasOrder;

  bool evidenceFor(String stage) {
    switch (stage) {
      case kLeadStatusSurveyDone:
        return surveySubmitted;
      case kLeadStatusQuoted:
        return hasQuote;
      case kLeadStatusConfirmed:
        return hasOrder;
      default:
        // `new` and `follow_up` — no record to read. See the class doc.
        return false;
    }
  }

  /// Stages that have a record behind them. The rest stay positional.
  static const Set<String> evidenceBackedStages = {
    kLeadStatusSurveyDone,
    kLeadStatusQuoted,
    kLeadStatusConfirmed,
  };
}

/// Computes one stage's state.
///
/// [stageIdx] and [currentIdx] are positions in [kLeadPipeline].
LeadStageState leadStageState({
  required String stage,
  required int stageIdx,
  required int currentIdx,
  required LeadStageEvidence evidence,
}) {
  if (!LeadStageEvidence.evidenceBackedStages.contains(stage)) {
    // Positional, and honestly so: nothing records that a follow-up call
    // happened, so there is nothing to contradict.
    if (stageIdx < currentIdx) return LeadStageState.done;
    if (stageIdx == currentIdx) return LeadStageState.current;
    return LeadStageState.pending;
  }

  // Evidence wins over position, in BOTH directions. A survey submitted
  // on a lead still sitting at `follow_up` shows done — which is right,
  // and is the case the old code could not express at all.
  if (evidence.evidenceFor(stage)) return LeadStageState.done;

  if (stageIdx < currentIdx) return LeadStageState.skipped;
  if (stageIdx == currentIdx) return LeadStageState.current;
  return LeadStageState.pending;
}
