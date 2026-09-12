import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/lead_stage_evidence.dart';
import 'package:arun_p_k_r_s/backend/lead_status.dart';

/// The regression these pin is not hypothetical: on 12 Sept 2026 the
/// pipeline strip was ticking "Survey" on **two of six confirmed leads**
/// that had no submitted survey, because every stage was derived from the
/// lead's single status ordinal (`done: i < currentIdx`).
void main() {
  int idx(String stage) => kLeadPipeline.indexOf(stage);

  LeadStageState stateOf(String stage, String leadStatus,
          [LeadStageEvidence e = const LeadStageEvidence()]) =>
      leadStageState(
        stage: stage,
        stageIdx: idx(stage),
        currentIdx: leadStageIndex(canonicalLeadStatus(leadStatus)),
        evidence: e,
      );

  group('the bug that started this', () {
    test('a quoted lead with NO survey shows Survey as skipped, never done',
        () {
      expect(
        stateOf(kLeadStatusSurveyDone, kLeadStatusQuoted,
            const LeadStageEvidence(hasQuote: true)),
        LeadStageState.skipped,
      );
    });

    test('a quoted lead WITH a submitted survey shows Survey as done', () {
      expect(
        stateOf(kLeadStatusSurveyDone, kLeadStatusQuoted,
            const LeadStageEvidence(surveySubmitted: true, hasQuote: true)),
        LeadStageState.done,
      );
    });

    test('position alone can never produce done for an evidence-backed stage',
        () {
      // Lead marked all the way to confirmed, no records at all behind it.
      for (final stage in LeadStageEvidence.evidenceBackedStages) {
        expect(stateOf(stage, kLeadStatusConfirmed), isNot(LeadStageState.done),
            reason: '$stage was ticked with no evidence');
      }
    });
  });

  group('evidence beats position in BOTH directions', () {
    test('a survey submitted while the lead still sits at follow_up is done',
        () {
      // The old code could not express this at all: the stage was ahead
      // of the ordinal, so it rendered as pending however real it was.
      expect(
        stateOf(kLeadStatusSurveyDone, kLeadStatusFollowUp,
            const LeadStageEvidence(surveySubmitted: true)),
        LeadStageState.done,
      );
    });

    test('an order on a lead nobody moved past quoted still reads done', () {
      expect(
        stateOf(kLeadStatusConfirmed, kLeadStatusQuoted,
            const LeadStageEvidence(hasOrder: true)),
        LeadStageState.done,
      );
    });
  });

  group('stages with no record stay positional, and say so', () {
    test('follow_up is done by position because nothing records a call', () {
      expect(stateOf(kLeadStatusFollowUp, kLeadStatusQuoted),
          LeadStageState.done);
    });

    test('new is current on a new lead', () {
      expect(stateOf(kLeadStatusNew, kLeadStatusNew), LeadStageState.current);
    });

    test('evidenceBackedStages is exactly survey, quoted and confirmed', () {
      // If a stage gains a record later, it must be added here or it will
      // silently keep inferring from position.
      expect(
        LeadStageEvidence.evidenceBackedStages,
        {kLeadStatusSurveyDone, kLeadStatusQuoted, kLeadStatusConfirmed},
      );
    });
  });

  group('the empty default understates rather than invents', () {
    test('no evidence on a fresh lead leaves later stages pending', () {
      expect(stateOf(kLeadStatusQuoted, kLeadStatusNew),
          LeadStageState.pending);
      expect(stateOf(kLeadStatusConfirmed, kLeadStatusNew),
          LeadStageState.pending);
    });

    test('a caller that forgets to pass evidence never gets a false tick', () {
      // const LeadStageEvidence() is the default on the widget. Passing
      // it must not produce `done` anywhere, at any lead status.
      for (final lead in kLeadPipeline) {
        for (final stage in LeadStageEvidence.evidenceBackedStages) {
          expect(stateOf(stage, lead), isNot(LeadStageState.done),
              reason: '$stage ticked at lead status $lead with no evidence');
        }
      }
    });
  });
}
