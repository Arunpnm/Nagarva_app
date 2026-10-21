/// The order journey (Claude Design handoff, 20 Oct 2026, screen `jrny`):
/// one record per lead or order, read as nine stages from first enquiry
/// to a closed, paid job.
///
/// **This is a read model, not a second workflow.** Every stage is
/// derived from rows the app already writes — follow_up_logs, surveys,
/// quotations, orders, payment_entries, complaints, document_signatures —
/// and the journey screen sends each action to the code that already owns
/// it (quote revision and convert-to-order on Lead Details, invoice
/// numbering and the audited close on Order Details, Record Payment).
/// Re-implementing invoice numbering or the close gate here would give
/// the app two copies of its money logic, which is exactly the drift
/// CLAUDE.md records again and again.
///
/// Stage state follows lead_stage_evidence.dart's rule: **evidence, not
/// position**. A stage is done because its record exists, never because
/// a later status says it must have happened. Where there is no record
/// and a later stage has evidence, the stage reads as skipped.
library;

import '/backend/lead_status.dart';
import '/backend/order_stages.dart';
import '/backend/reminders_service.dart';
import '/backend/signature_service.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';

enum JourneyStage {
  lead,
  followUp,
  survey,
  quote,
  supervisor,
  moveDay,
  invoice,
  payment,
  closed,
}

enum JourneyState { done, skipped, current, pending }

/// Why an order cannot be closed yet. The handoff's close gate, minus the
/// end-odometer rule: orders carry no odometer column, so that one is not
/// enforced here rather than invented.
enum CloseBlocker { openTicket, balanceDue, noSignature, noInvoice }

class JourneyData {
  JourneyData({
    this.lead,
    this.order,
    this.followUps = const [],
    this.survey,
    this.quotes = const [],
    this.crew = const [],
    this.supervisorName,
    this.payments = const [],
    this.tickets = const [],
    this.invoiceSignature,
  });

  final LeadsRow? lead;
  final OrdersRow? order;
  final List<FollowUpLogsRow> followUps;
  final SurveysRow? survey;

  /// Newest first.
  final List<QuotationsRow> quotes;
  final List<OrderStaffRow> crew;
  final String? supervisorName;

  /// Oldest first.
  final List<PaymentEntriesRow> payments;
  final List<ComplaintsRow> tickets;
  final SignatureRequest? invoiceSignature;

  /// An order booked straight in, with no lead behind it. Follow-up and
  /// survey read "Skipped · direct order" (handoff rule).
  bool get isDirect => lead == null && order != null;

  String get customer => order?.customer ?? lead?.customer ?? '';
  String? get phone => order?.phone ?? lead?.phone;
  String? get fromCity => order?.fromCity ?? lead?.fromCity;
  String? get toCity => order?.toCity ?? lead?.toCity;

  bool get hasLiveOrder =>
      order != null && (order!.status ?? '').toLowerCase() != 'cancelled';

  bool get isLost => canonicalLeadStatus(lead?.status) == kLeadStatusLost;

  bool get isClosed => (order?.status ?? '').toLowerCase() == 'closed';

  double get orderValue => order?.amount ?? 0;
  double get paid => order?.paidTotal ?? 0;
  double get balance => orderValue - paid;

  List<ComplaintsRow> get openTickets => tickets
      .where((t) => t.status.toLowerCase() != 'resolved')
      .toList();

  /// Order stage index on the existing 6-step operations ladder.
  int get opsIndex => order == null
      ? -1
      : orderStageIndex(order!.trackingStatus, order!.status);

  bool get moveStarted =>
      order?.jobStartTime != null || opsIndex >= kOrderStages.indexOf(kStagePacking);

  bool get moveFinished =>
      order?.jobEndTime != null ||
      opsIndex >= kOrderStages.indexOf(kStageDelivered) ||
      isClosed;

  List<CloseBlocker> get closeBlockers => [
        if (openTickets.isNotEmpty) CloseBlocker.openTicket,
        if (balance > 0) CloseBlocker.balanceDue,
        if (!(invoiceSignature?.isSigned ?? false)) CloseBlocker.noSignature,
        if ((order?.invoiceNo ?? '').isEmpty) CloseBlocker.noInvoice,
      ];

  /// Evidence per stage — true when the stage's own record exists.
  bool _evidence(JourneyStage s) {
    switch (s) {
      case JourneyStage.lead:
        return lead != null;
      case JourneyStage.followUp:
        return followUps.isNotEmpty;
      case JourneyStage.survey:
        return (survey?.status ?? '').toLowerCase() == 'submitted';
      case JourneyStage.quote:
        return hasLiveOrder ||
            canonicalLeadStatus(lead?.status) == kLeadStatusConfirmed;
      case JourneyStage.supervisor:
        return (order?.supervisorId ?? '').isNotEmpty;
      case JourneyStage.moveDay:
        return moveFinished;
      case JourneyStage.invoice:
        return (order?.invoiceNo ?? '').isNotEmpty;
      case JourneyStage.payment:
        return order != null && balance <= 0 && openTickets.isEmpty;
      case JourneyStage.closed:
        return isClosed;
    }
  }

  /// Every stage's state. The current stage is the first one with no
  /// evidence that is not skipped; a stage with no evidence BEFORE a stage
  /// that has evidence is skipped (it was passed by, not done).
  Map<JourneyStage, JourneyState> get states {
    final ev = {for (final s in JourneyStage.values) s: _evidence(s)};
    if (isDirect) {
      ev[JourneyStage.lead] = false;
      ev[JourneyStage.followUp] = false;
      ev[JourneyStage.survey] = false;
    }
    final lastEvidence = JourneyStage.values
        .lastWhere((s) => ev[s]!, orElse: () => JourneyStage.lead);
    final out = <JourneyStage, JourneyState>{};
    var currentSet = false;
    for (final s in JourneyStage.values) {
      if (ev[s]!) {
        out[s] = JourneyState.done;
      } else if (isDirect && s.index <= JourneyStage.survey.index) {
        out[s] = JourneyState.skipped;
      } else if (s.index < lastEvidence.index) {
        out[s] = JourneyState.skipped;
      } else if (!currentSet && !isLost) {
        out[s] = JourneyState.current;
        currentSet = true;
      } else {
        out[s] = JourneyState.pending;
      }
    }
    return out;
  }

  JourneyStage? get current => states.entries
      .where((e) => e.value == JourneyState.current)
      .map((e) => e.key)
      .firstOrNull;
}

class JourneyLoader {
  /// Loads the journey for a lead, an order, or both. Either id is enough:
  /// an order finds its lead through `orders.lead_id`; a lead finds its
  /// order through `leads.order_id`, then `orders.lead_id`, then any order
  /// on one of its quotations — the same link Lead Details checks.
  ///
  /// Supplemental reads (logs, crew, signature) never fail the whole load;
  /// a journey with a missing panel beats a blank screen.
  static Future<JourneyData> load({String? leadId, String? orderId}) async {
    OrdersRow? order;
    LeadsRow? lead;

    if (orderId != null && orderId.isNotEmpty) {
      final rows = await OrdersTable()
          .queryRows(queryFn: (q) => OrgScope.read(q).eq('id', orderId));
      order = rows.firstOrNull;
      leadId ??= order?.leadId;
    }
    final lid = leadId;
    if (lid != null && lid.isNotEmpty) {
      final rows = await LeadsTable()
          .queryRows(queryFn: (q) => OrgScope.read(q).eq('id', lid));
      lead = rows.firstOrNull;
    }

    var quotes = <QuotationsRow>[];
    if (lead?.id != null) {
      quotes = await _safe(() => QuotationsTable().queryRows(
                queryFn: (q) => OrgScope.read(q)
                    .eq('lead_id', lead!.id!)
                    .order('created_at', ascending: false),
              )) ??
          [];
    }

    if (order == null && lead != null) {
      order = await _findOrderForLead(lead, quotes);
    }

    final oid = order?.id;
    final results = await Future.wait<Object?>([
      if (lead?.id != null)
        _safe(() => RemindersService.logsFor(
            entityType: kEntityLead, entityId: lead!.id!))
      else
        Future.value(null),
      if (lead?.id != null)
        _safe(() => SurveysTable().queryRows(
              queryFn: (q) => OrgScope.read(q)
                  .eq('lead_id', lead!.id!)
                  .order('created_at', ascending: false),
            ))
      else
        Future.value(null),
      if (oid != null)
        _safe(() => OrderStaffTable().queryRows(
            queryFn: (q) => OrgScope.read(q).eq('order_id', oid)))
      else
        Future.value(null),
      if (oid != null)
        _safe(() => PaymentEntriesTable().queryRows(
              queryFn: (q) => OrgScope.read(q)
                  .eq('order_id', oid)
                  .order('received_at', ascending: true),
            ))
      else
        Future.value(null),
      if (oid != null)
        _safe(() => ComplaintsTable().queryRows(
              queryFn: (q) => OrgScope.read(q)
                  .eq('order_id', oid)
                  .order('reported_at', ascending: false),
            ))
      else
        Future.value(null),
      if (oid != null)
        _safe<SignatureRequest?>(() => SignatureService.find(
            documentType: 'invoice', documentId: oid))
      else
        Future.value(null),
      if ((order?.supervisorId ?? '').isNotEmpty)
        _safe(() => StaffTable().queryRows(
            queryFn: (q) =>
                OrgScope.read(q).eq('id', order!.supervisorId!)))
      else
        Future.value(null),
    ]);

    final surveys = (results[1] as List<SurveysRow>?) ?? const [];
    final sup = (results[6] as List<StaffRow>?) ?? const [];
    return JourneyData(
      lead: lead,
      order: order,
      followUps: (results[0] as List<FollowUpLogsRow>?) ?? const [],
      survey: surveys.firstOrNull,
      quotes: quotes,
      crew: (results[2] as List<OrderStaffRow>?) ?? const [],
      payments: (results[3] as List<PaymentEntriesRow>?) ?? const [],
      tickets: (results[4] as List<ComplaintsRow>?) ?? const [],
      invoiceSignature: results[5] as SignatureRequest?,
      supervisorName: sup.firstOrNull?.name,
    );
  }

  static Future<OrdersRow?> _findOrderForLead(
      LeadsRow lead, List<QuotationsRow> quotes) async {
    Future<OrdersRow?> one(dynamic Function(dynamic q) f) async {
      final rows = await _safe(() => OrdersTable().queryRows(
          queryFn: (q) => f(OrgScope.read(q)).order('created_at',
              ascending: false)));
      return rows
          ?.where((o) => (o.status ?? '').toLowerCase() != 'cancelled')
          .firstOrNull;
    }

    if ((lead.orderId ?? '').isNotEmpty) {
      final o = await one((q) => q.eq('id', lead.orderId!));
      if (o != null) return o;
    }
    final byLead = await one((q) => q.eq('lead_id', lead.id!));
    if (byLead != null) return byLead;
    final quoteIds = quotes.map((q) => q.id).whereType<String>().toList();
    if (quoteIds.isEmpty) return null;
    return one((q) => q.inFilter('quotation_id', quoteIds));
  }

  static Future<T?> _safe<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }
}
