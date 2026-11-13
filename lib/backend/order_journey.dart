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

import '/backend/business_modules.dart';
import '/backend/lead_status.dart';
import '/backend/order_money.dart';
import '/backend/order_stages.dart';
import '/backend/reminders_service.dart';
import '/backend/signature_service.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';

/// Lead → Survey → Quote → Order (supervisor … closed) / Cancelled.
/// Arun, 3 Nov 2026: follow-up is not a stage of its own — it happens
/// INSIDE the Lead, Survey and Quote stages, each with its own call
/// history (see [JourneyData.followUpsIn]). Creating a quote moves the
/// journey to Quote; logging a call never moves it.
enum JourneyStage {
  lead,
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
    this.addonRows = const [],
    this.podMethod,
  });

  /// How the field job was handed over (pod_records.completion_method):
  /// 'signature' = the customer signed in person at handover. That counts
  /// as the customer's signature for closing (BUG-040, 3 Nov 2026) —
  /// before, only the ONLINE invoice signature did, so a customer who
  /// never opened the link kept the order open forever.
  final String? podMethod;

  bool get signedInPerson => podMethod == 'signature';
  bool get customerSigned =>
      (invoiceSignature?.isSigned ?? false) || signedInPerson;

  /// Raw `addons` rows of the order (extra charges) — part of what the
  /// customer owes (BUG-036).
  final List<dynamic> addonRows;

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

  /// When the Survey stage began: the first survey row (link sent or
  /// visit booked). Null when no survey was ever started.
  DateTime? get surveyStartedAt => survey?.createdAt;

  /// When the Quote stage began: the FIRST quote's creation.
  DateTime? get quoteStartedAt {
    DateTime? first;
    for (final q in quotes) {
      final t = q.createdAt;
      if (t != null && (first == null || t.isBefore(first))) first = t;
    }
    return first;
  }

  /// The follow-ups logged while the journey was in [stage], newest first
  /// — each stage keeps its own history (Arun, 3 Nov 2026). Calls are
  /// placed by WHEN they were logged against when the survey and the first
  /// quote began; nothing has to be tagged at write time.
  List<FollowUpLogsRow> followUpsIn(JourneyStage stage) {
    final s = surveyStartedAt;
    final q = quoteStartedAt;
    JourneyStage stageAt(DateTime? t) {
      if (t == null) return JourneyStage.lead;
      if (q != null && !t.isBefore(q)) return JourneyStage.quote;
      if (s != null && !t.isBefore(s)) return JourneyStage.survey;
      return JourneyStage.lead;
    }

    return followUps.where((f) => stageAt(f.loggedAt) == stage).toList()
      ..sort((a, b) => (b.loggedAt ?? DateTime(0))
          .compareTo(a.loggedAt ?? DateTime(0)));
  }

  bool get isClosed => (order?.status ?? '').toLowerCase() == 'closed';

  /// Shared money rule (lib/backend/order_money.dart): base + GST only when
  /// billed + extra charges. Before 3 Nov this was `order.amount - paid`,
  /// so extras never showed as due (BUG-036).
  OrderMoney? get money =>
      order == null ? null : OrderMoney.from(order!, addonRows);
  double get orderValue => money?.total ?? 0;
  double get paid => order?.paidTotal ?? 0;
  double get balance => money?.balance ?? 0;

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
        if (!customerSigned) CloseBlocker.noSignature,
        if ((order?.invoiceNo ?? '').isEmpty) CloseBlocker.noInvoice,
      ];

  /// Evidence per stage — true when the stage's own record exists.
  bool _evidence(JourneyStage s) {
    switch (s) {
      case JourneyStage.lead:
        // The Lead stage (enquiry, requirements, follow-up) is complete
        // once a survey is under way or a quote exists. A logged call is
        // NOT evidence of moving on (Arun, 3 Nov 2026).
        return lead != null &&
            (survey != null || quotes.isNotEmpty || hasLiveOrder);
      case JourneyStage.survey:
        return (survey?.status ?? '').toLowerCase() == 'submitted';
      case JourneyStage.quote:
        return hasLiveOrder ||
            canonicalLeadStatus(lead?.status) == kLeadStatusConfirmed;
      case JourneyStage.supervisor:
        // A supervisor assigned, OR the field job was run by someone (the
        // owner) — crew saved / job accepted. Before, an owner-run job
        // read "No supervisor yet · Skipped" (3 Nov 2026).
        return (order?.supervisorId ?? '').isNotEmpty ||
            (order?.supervisorStatus ?? '').isNotEmpty ||
            crew.isNotEmpty;
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
    final billingOnly = BusinessModules.instance.billingActive;
    final ev = {for (final s in JourneyStage.values) s: _evidence(s)};
    if (isDirect) {
      ev[JourneyStage.lead] = false;
      ev[JourneyStage.survey] = false;
    }
    var lastEvidence = JourneyStage.values
        .lastWhere((s) => ev[s]!, orElse: () => JourneyStage.lead);
    // A quote exists → the journey is in Quote (until there is an order),
    // whether or not a survey was done: creating the quote is the trigger.
    // Below, stages before `lastEvidence` with no record read "skipped"
    // (an unsubmitted survey was passed by), and Quote itself — having no
    // order yet — becomes the current stage.
    if (quotes.isNotEmpty && lastEvidence.index < JourneyStage.quote.index) {
      lastEvidence = JourneyStage.quote;
    }
    final out = <JourneyStage, JourneyState>{};
    var currentSet = false;
    for (final s in JourneyStage.values) {
      if (ev[s]!) {
        out[s] = JourneyState.done;
      } else if (isDirect && s.index <= JourneyStage.survey.index) {
        out[s] = JourneyState.skipped;
      } else if (s.index < lastEvidence.index) {
        out[s] = JourneyState.skipped;
      } else if (billingOnly &&
          hasLiveOrder &&
          (s == JourneyStage.supervisor || s == JourneyStage.moveDay)) {
        // Billing only (13 Nov 2026): the company uses the app for its
        // paperwork and runs no field job here, so a confirmed order goes
        // straight to Invoice. Found by test: the invoice stayed "Later"
        // behind a Move day nobody was ever going to run. A stage that
        // HAS a record still reads done; only the empty ones are passed.
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
      if (oid != null)
        _safe<List<dynamic>>(() async => await SupaFlow.client
            .from('addons')
            .select('description,amount,status')
            .eq('order_id', oid)
            .eq('org_id', OrgScope.currentOrgId ?? ''))
      else
        Future.value(null),
      if (oid != null)
        _safe<List<dynamic>>(() async => await SupaFlow.client
            .from('pod_records')
            .select('completion_method')
            .eq('order_id', oid)
            .eq('org_id', OrgScope.currentOrgId ?? ''))
      else
        Future.value(null),
    ]);
    final pods = (results[8] as List<dynamic>?) ?? const [];
    final podMethods = [
      for (final p in pods) '${(p as Map)['completion_method'] ?? ''}'
    ];

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
      addonRows: (results[7] as List<dynamic>?) ?? const [],
      podMethod: podMethods.contains('signature')
          ? 'signature'
          : podMethods.firstOrNull,
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
