import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/order_journey.dart';
import 'package:arun_p_k_r_s/backend/supabase/supabase.dart';

/// The journey reads its nine stages from evidence, the same rule as
/// lead_stage_evidence.dart: a stage is done because its record exists,
/// and a stage with no record that a later stage has passed is SKIPPED,
/// never ticked. These pin that rule on the shapes the app really holds.
void main() {
  LeadsRow lead([String status = 'new']) =>
      LeadsRow({'id': 'lead-1', 'customer': 'Ravi', 'status': status});

  OrdersRow order(Map<String, dynamic> extra) => OrdersRow({
        'id': 'ORD-1',
        'customer': 'Ravi',
        'status': 'confirmed',
        'amount': 20000.0,
        'paid_total': 0.0,
        ...extra,
      });

  Map<JourneyStage, JourneyState> states(JourneyData d) => d.states;

  test('a fresh lead is on follow-up, everything after waits', () {
    final s = states(JourneyData(lead: lead()));
    expect(s[JourneyStage.lead], JourneyState.done);
    expect(s[JourneyStage.followUp], JourneyState.current);
    for (final st in JourneyStage.values.skip(2)) {
      expect(s[st], JourneyState.pending, reason: '$st');
    }
  });

  test('a confirmed order with no calls or survey skips them, not ticks them',
      () {
    final s = states(JourneyData(lead: lead('confirmed'), order: order({})));
    expect(s[JourneyStage.followUp], JourneyState.skipped);
    expect(s[JourneyStage.survey], JourneyState.skipped);
    expect(s[JourneyStage.quote], JourneyState.done);
    expect(s[JourneyStage.supervisor], JourneyState.current);
  });

  test('a direct order starts at supervisor with the lead stages skipped', () {
    final d = JourneyData(order: order({'supervisor_id': 'st-1'}));
    final s = states(d);
    expect(d.isDirect, isTrue);
    expect(s[JourneyStage.lead], JourneyState.skipped);
    expect(s[JourneyStage.followUp], JourneyState.skipped);
    expect(s[JourneyStage.survey], JourneyState.skipped);
    expect(s[JourneyStage.supervisor], JourneyState.done);
    expect(s[JourneyStage.moveDay], JourneyState.current);
  });

  test('a lost lead has no current stage', () {
    final d = JourneyData(lead: lead('lost'));
    expect(d.current, isNull);
  });

  test('close is blocked by balance, an open ticket, no invoice, no signature',
      () {
    final d = JourneyData(
      order: order({'paid_total': 5000.0}),
      tickets: [
        ComplaintsRow({'id': 't1', 'status': 'open', 'description': 'AC'})
      ],
    );
    expect(d.balance, 15000);
    expect(
        d.closeBlockers,
        containsAll([
          CloseBlocker.balanceDue,
          CloseBlocker.openTicket,
          CloseBlocker.noInvoice,
          CloseBlocker.noSignature,
        ]));
  });

  test('a closed, paid order reads closed with nothing current', () {
    final d = JourneyData(
      lead: lead('confirmed'),
      order: order({
        'status': 'closed',
        'paid_total': 20000.0,
        'supervisor_id': 'st-1',
        'invoice_no': '0001',
        'job_end_time': '2026-10-01T10:00:00Z',
      }),
    );
    final s = states(d);
    expect(s[JourneyStage.closed], JourneyState.done);
    expect(s[JourneyStage.payment], JourneyState.done);
    expect(d.current, isNull);
  });
}
