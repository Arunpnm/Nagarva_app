import 'package:flutter/material.dart';

import '/backend/detail_navigation.dart';
import '/backend/lead_status.dart';
import '/backend/order_journey.dart';
import '/backend/reminders_service.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/index.dart';
import '/l10n/gen/app_localizations.dart';
import '/permissions.dart';

/// The order journey (Claude Design handoff, screen `jrny`): one lead or
/// order shown as nine stages from enquiry to a closed, paid job.
///
/// Stage state comes from [JourneyData] — evidence from real rows, never
/// position. The screen owns only two small writes of its own, logging a
/// follow-up call (through RemindersService, the app's one follow-up
/// writer) and raising/resolving a ticket (complaints, as Ops Log does).
/// Everything with money or numbering in it — quotes, convert-to-order,
/// supervisor assignment, invoices, payments, the audited close — opens
/// the screen that already owns that logic, so there is still exactly one
/// copy of it.
class OrderJourneyPageWidget extends StatefulWidget {
  const OrderJourneyPageWidget({super.key, this.leadId, this.orderId});

  final String? leadId;
  final String? orderId;

  static String routeName = 'OrderJourneyPage';
  static String routePath = '/order-journey';

  @override
  State<OrderJourneyPageWidget> createState() => _OrderJourneyPageWidgetState();
}

class _OrderJourneyPageWidgetState extends State<OrderJourneyPageWidget>
    with RefreshOnPopMixin<OrderJourneyPageWidget> {
  JourneyData? _data;
  bool _loading = true;
  bool _failed = false;

  /// Stages the user expanded by hand. The current stage is always open.
  final _open = <JourneyStage>{};

  // Follow-up form.
  String? _outcome;
  DateTime? _next;
  final _callNotes = TextEditingController();
  bool _savingCall = false;

  // Ticket form.
  final _ticketCtrl = TextEditingController();
  bool _savingTicket = false;

  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Every screen this one opens can change what it shows (a payment, a
  /// supervisor, an invoice), so re-read on return.
  @override
  void onPageRefresh() => _load();

  @override
  void dispose() {
    _callNotes.dispose();
    _ticketCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _failed = false;
    });
    try {
      final d = await JourneyLoader.load(
          leadId: widget.leadId, orderId: widget.orderId);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ---- Actions -----------------------------------------------------------

  /// Design outcome chips → the app's follow_up_logs vocabulary.
  static const _outcomes = <String>[
    'no_answer',
    'callback_requested',
    'connected',
    'not_interested',
  ];

  String _outcomeLabel(AppLocalizations l, String o) => switch (o) {
        'no_answer' => l.jrOutNoAnswer,
        'callback_requested' => l.jrOutCallback,
        'connected' => l.jrOutInterested,
        _ => l.jrOutNotInterested,
      };

  Future<void> _logCall(JourneyData d) async {
    final l = AppLocalizations.of(context);
    final leadId = d.lead?.id;
    if (leadId == null) return;
    if (_outcome == null) {
      _toast(l.jrPickOutcome);
      return;
    }
    setState(() => _savingCall = true);
    try {
      await RemindersService.logFollowUp(
        entityType: kEntityLead,
        entityId: leadId,
        channel: 'call',
        outcome: _outcome,
        notes: _callNotes.text.trim().isEmpty ? null : _callNotes.text.trim(),
        nextActionAt: _next,
      );
      // Logging a call is evidence the lead has been followed up. The
      // never-downgrade rule decides whether that moves the status.
      final next = advanceLeadStatus(d.lead?.status, kLeadStatusFollowUp);
      if (next != canonicalLeadStatus(d.lead?.status)) {
        await LeadsTable().update(
          data: {'status': next},
          matchingRows: (q) => OrgScope.write(q).eq('id', leadId),
        );
      }
      _callNotes.clear();
      _outcome = null;
      _next = null;
      if (mounted) _toast(l.jrCallLogged);
      await _load();
    } catch (e) {
      if (mounted) _toast(l.jrCouldNotSave('$e'));
    } finally {
      if (mounted) setState(() => _savingCall = false);
    }
  }

  Future<void> _raiseTicket(JourneyData d) async {
    final l = AppLocalizations.of(context);
    final text = _ticketCtrl.text.trim();
    if (text.isEmpty || d.order?.id == null) return;
    setState(() => _savingTicket = true);
    try {
      await ComplaintsTable().insert({
        ...OrgScope.stamp(),
        'order_id': d.order!.id,
        'description': text,
        'status': 'open',
        'reported_at': DateTime.now().toIso8601String(),
      });
      _ticketCtrl.clear();
      if (mounted) _toast(l.jrTicketRaised);
      await _load();
    } catch (e) {
      if (mounted) _toast(l.jrCouldNotSave('$e'));
    } finally {
      if (mounted) setState(() => _savingTicket = false);
    }
  }

  Future<void> _resolveTicket(ComplaintsRow t) async {
    final l = AppLocalizations.of(context);
    if (t.id == null) return;
    try {
      await ComplaintsTable().update(
        data: {'status': 'resolved'},
        matchingRows: (q) => OrgScope.write(q).eq('id', t.id!),
      );
      if (mounted) _toast(l.jrTicketResolved);
      await _load();
    } catch (e) {
      if (mounted) _toast(l.jrCouldNotSave('$e'));
    }
  }

  void _openLead(JourneyData d) {
    if (d.lead != null) openLeadDetail(context, d.lead!);
  }

  void _openOrder(JourneyData d) {
    if (d.order != null) openOrderDetail(context, d.order!);
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final d = _data;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgTopBar(showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_failed || d == null)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.jrCouldNotLoad,
                          style: NgFonts.geist(fontSize: 14, color: c.mute)),
                      const SizedBox(height: 12),
                      NgSecondaryButton(label: l.jrRetry, onPressed: _load),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: _content(context, d),
                  ),
                ),
    );
  }

  List<Widget> _content(BuildContext context, JourneyData d) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final states = d.states;
    final ids = [
      if (d.lead?.id != null) d.lead!.id!.substring(0, 8).toUpperCase(),
      if (d.order?.id != null) d.order!.id!,
    ].join(' · ');
    final moveDate = d.order?.moveDateOrNull;
    final phone = (d.phone ?? '').trim();

    return [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.customer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.42,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(ids, style: NgFonts.mono(fontSize: 12.5, color: c.mute)),
              ],
            ),
          ),
          if (phone.isNotEmpty)
            NgHeaderButton(
              onTap: () => launchURL('tel:$phone'),
              child: Icon(Icons.call_rounded, size: 20, color: c.green),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final (k, v) in [
            (
              l.jrMoveDate,
              moveDate == null
                  ? (d.lead?.approxDate ?? l.jrNotSet)
                  : DateFormat('d MMM').format(moveDate)
            ),
            (l.jrRoute, '${d.fromCity ?? '-'} → ${d.toCity ?? '-'}'),
            (
              l.jrOrderValue,
              d.order == null ? l.jrNotSet : _money.format(d.orderValue)
            ),
          ]) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                decoration: BoxDecoration(
                  color: c.s1,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k, style: NgFonts.geist(fontSize: 11, color: c.mute)),
                    const SizedBox(height: 3),
                    Text(
                      v,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NgFonts.geist(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: c.text),
                    ),
                  ],
                ),
              ),
            ),
            if (k != l.jrOrderValue) const SizedBox(width: 6),
          ],
        ],
      ),
      const SizedBox(height: 12),
      // Nine-segment progress bar.
      Row(
        children: [
          for (final s in JourneyStage.values) ...[
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: switch (states[s]!) {
                    JourneyState.done => c.green,
                    JourneyState.current => c.accBtn,
                    JourneyState.skipped => c.w15,
                    JourneyState.pending => c.w07,
                  },
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            if (s != JourneyStage.closed) const SizedBox(width: 3),
          ],
        ],
      ),
      if (d.isLost) ...[
        const SizedBox(height: 12),
        NgPill(l.jrLeadLost, status: NgStatus.red, icon: Icons.block_rounded),
      ],
      const SizedBox(height: 12),
      _documents(context, d, states),
      const SizedBox(height: 12),
      for (final s in JourneyStage.values) ...[
        _stageCard(context, d, s, states[s]!),
        const SizedBox(height: 8),
      ],
    ];
  }

  String _stageName(AppLocalizations l, JourneyStage s) => switch (s) {
        JourneyStage.lead => l.jrStageLead,
        JourneyStage.followUp => l.jrStageFollowUp,
        JourneyStage.survey => l.jrStageSurvey,
        JourneyStage.quote => l.jrStageQuote,
        JourneyStage.supervisor => l.jrStageSupervisor,
        JourneyStage.moveDay => l.jrStageMoveDay,
        JourneyStage.invoice => l.jrStageInvoice,
        JourneyStage.payment => l.jrStagePayment,
        JourneyStage.closed => l.jrStageClosed,
      };

  static const _stageIcons = <JourneyStage, IconData>{
    JourneyStage.lead: Icons.person_search_rounded,
    JourneyStage.followUp: Icons.phone_in_talk_rounded,
    JourneyStage.survey: Icons.checklist_rounded,
    JourneyStage.quote: Icons.request_quote_rounded,
    JourneyStage.supervisor: Icons.engineering_rounded,
    JourneyStage.moveDay: Icons.local_shipping_rounded,
    JourneyStage.invoice: Icons.receipt_long_rounded,
    JourneyStage.payment: Icons.payments_rounded,
    JourneyStage.closed: Icons.task_alt_rounded,
  };

  /// The handoff's Documents panel. Each card points at the screen whose
  /// existing generator renders that document — quotation PDFs live on
  /// Lead Details, invoice/receipt/LR on Order Details — rather than a
  /// second copy of any PDF builder.
  Widget _documents(BuildContext context, JourneyData d,
      Map<JourneyStage, JourneyState> states) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final docs = <(IconData, String, bool, String, VoidCallback?)>[
      (
        Icons.request_quote_rounded,
        l.jrDocQuote,
        d.quotes.isNotEmpty,
        l.jrStageQuote,
        d.lead == null ? null : () => _openLead(d),
      ),
      (
        Icons.receipt_long_rounded,
        l.jrDocInvoice,
        (d.order?.invoiceNo ?? '').isNotEmpty,
        l.jrStageInvoice,
        () => _openOrder(d),
      ),
      (
        Icons.receipt_rounded,
        l.jrDocReceipts,
        d.payments.isNotEmpty,
        l.jrStagePayment,
        () => _openOrder(d),
      ),
      (
        Icons.local_shipping_rounded,
        l.jrDocLr,
        (d.order?.lrId ?? '').isNotEmpty,
        l.jrStageMoveDay,
        () => _openOrder(d),
      ),
    ];
    return NgCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Text(l.jrDocuments,
                style: NgFonts.geist(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.9,
            children: [
              for (final (icon, name, ready, after, onTap) in docs)
                Material(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: ready ? onTap : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Icon(icon, size: 18, color: ready ? c.acc : c.faint),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: NgFonts.geist(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: ready ? c.text : c.mute)),
                                Text(
                                    ready ? l.jrDocReady : l.jrDocAfter(after),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: NgFonts.geist(
                                        fontSize: 11,
                                        color: ready ? c.green : c.faint)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Summary under a stage's title, and the history lines shown when the
  /// card is expanded.
  (String, List<(IconData, String, String)>) _summary(
      AppLocalizations l, JourneyData d, JourneyStage s, JourneyState st) {
    String date(DateTime? t) =>
        t == null ? '' : DateFormat('d MMM, h:mm a').format(t.toLocal());
    if (st == JourneyState.skipped &&
        d.isDirect &&
        s.index <= JourneyStage.survey.index) {
      return (l.jrDirectOrder, const []);
    }
    switch (s) {
      case JourneyStage.lead:
        final lead = d.lead;
        if (lead == null) return (l.jrDirectOrder, const []);
        return (
          leadStatusLabel(lead.status),
          [
            if (lead.createdAt != null)
              (Icons.schedule_rounded, l.jrCreated(date(lead.createdAt)), ''),
            if ((lead.source ?? '').isNotEmpty)
              (Icons.campaign_rounded, l.jrSource(lead.source!), ''),
            if ((lead.service ?? '').isNotEmpty)
              (Icons.home_work_rounded, l.jrService(lead.service!), ''),
          ]
        );
      case JourneyStage.followUp:
        return (
          d.followUps.isEmpty
              ? l.jrNoCalls
              : l.jrCallsLogged('${d.followUps.length}'),
          [
            for (final f in d.followUps)
              (
                Icons.call_rounded,
                followUpOutcomeLabel(f.outcome),
                [
                  date(f.loggedAt),
                  RemindersService.actorLabel(f.loggedBy),
                  if ((f.notes ?? '').isNotEmpty) f.notes!,
                ].where((x) => x.isNotEmpty).join(' · '),
              ),
          ]
        );
      case JourneyStage.survey:
        final sv = d.survey;
        if (sv == null) return (l.jrNoSurvey, const []);
        final done = sv.status.toLowerCase() == 'submitted';
        return (
          done ? l.jrSurveyDone : l.jrSurveyWaiting,
          [
            if (done && sv.submittedAt != null)
              (Icons.task_alt_rounded, l.jrSurveyDone, date(sv.submittedAt)),
          ]
        );
      case JourneyStage.quote:
        final summary = d.hasLiveOrder
            ? l.jrOrderConfirmed(d.order!.id ?? '')
            : d.quotes.isEmpty
                ? l.jrNoQuote
                : l.jrQuoteLine(_money.format(d.quotes.first.total ?? 0));
        return (
          summary,
          [
            for (final q in d.quotes)
              (
                Icons.request_quote_rounded,
                l.jrQuoteLine(_money.format(q.total ?? 0)),
                [
                  if (q.version != null) 'v${q.version}',
                  q.status ?? '',
                  date(q.createdAt),
                ].where((x) => x.isNotEmpty).join(' · '),
              ),
          ]
        );
      case JourneyStage.supervisor:
        return (
          d.supervisorName == null
              ? l.jrNoSupervisor
              : l.jrSupervisorIs(d.supervisorName!),
          [
            if (d.crew.isNotEmpty)
              (Icons.groups_rounded, l.jrCrew('${d.crew.length}'), ''),
          ]
        );
      case JourneyStage.moveDay:
        final o = d.order;
        return (
          o?.jobEndTime != null
              ? l.jrMoveFinished(date(o!.jobEndTime))
              : o?.jobStartTime != null
                  ? l.jrMoveStarted(date(o!.jobStartTime))
                  : l.jrNotStarted,
          [
            if ((o?.vehicleNo ?? '').isNotEmpty)
              (Icons.local_shipping_rounded, o!.vehicleNo!, ''),
          ]
        );
      case JourneyStage.invoice:
        final no = d.order?.invoiceNo ?? '';
        final signed = d.invoiceSignature?.isSigned ?? false;
        return (
          no.isEmpty ? l.jrNoInvoice : l.jrInvoiceNo(no),
          [
            if (no.isNotEmpty)
              (
                signed ? Icons.draw_rounded : Icons.edit_off_rounded,
                signed ? l.jrSigned : l.jrNotSigned,
                signed ? date(d.invoiceSignature?.signedAt) : '',
              ),
          ]
        );
      case JourneyStage.payment:
        return (
          d.order == null
              ? '—'
              : '${l.jrPaid} ${_money.format(d.paid)} · ${l.jrBalance} ${_money.format(d.balance)}',
          [
            for (final p in d.payments)
              (
                Icons.payments_rounded,
                l.jrPaymentLine(_money.format(p.amount), p.mode),
                date(p.receivedAt),
              ),
            for (final t in d.tickets)
              (
                t.status.toLowerCase() == 'resolved'
                    ? Icons.check_circle_rounded
                    : Icons.confirmation_number_rounded,
                t.description ?? '',
                date(t.reportedAt),
              ),
          ]
        );
      case JourneyStage.closed:
        return (
          d.isClosed
              ? l.jrClosedOn(date(d.order?.closedAt))
              : l.jrNotClosed,
          const []
        );
    }
  }

  Widget _stageCard(BuildContext context, JourneyData d, JourneyStage s,
      JourneyState st) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final (summary, lines) = _summary(l, d, s, st);
    final isCur = st == JourneyState.current;
    final open = isCur || _open.contains(s);
    final tone = switch (st) {
      JourneyState.done => NgStatus.green,
      JourneyState.current => NgStatus.accent,
      _ => NgStatus.neutral,
    };
    final pill = switch (st) {
      JourneyState.done => l.jrStateDone,
      JourneyState.current => l.jrStateCurrent,
      JourneyState.skipped => l.jrStateSkipped,
      JourneyState.pending => l.jrStatePending,
    };
    final dim = st == JourneyState.pending;
    return Material(
      color: c.s1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NgRadius.card),
        side: BorderSide(color: isCur ? c.acc : c.w06),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: isCur || lines.isEmpty
                ? null
                : () => setState(
                    () => _open.contains(s) ? _open.remove(s) : _open.add(s)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Opacity(
                opacity: dim ? 0.55 : 1,
                child: Row(
                  children: [
                    NgIconTile(
                      icon: st == JourneyState.done
                          ? Icons.check_rounded
                          : _stageIcons[s]!,
                      status: tone,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_stageName(l, s),
                              style: NgFonts.geist(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.text)),
                          const SizedBox(height: 2),
                          Text(summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  NgFonts.geist(fontSize: 12.5, color: c.mute)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    NgPill(pill, status: tone),
                  ],
                ),
              ),
            ),
          ),
          if (open && lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: [
                  for (final (icon, t, sub) in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 36,
                            child: Icon(icon, size: 16, color: c.faint),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t,
                                    style: NgFonts.geist(
                                        fontSize: 13, color: c.soft)),
                                if (sub.isNotEmpty)
                                  Text(sub,
                                      style: NgFonts.geist(
                                          fontSize: 11.5, color: c.faint)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (isCur)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.w06)),
              ),
              child: _actions(context, d, s),
            ),
        ],
      ),
    );
  }

  /// What can be done at the current stage.
  Widget _actions(BuildContext context, JourneyData d, JourneyStage s) {
    final l = AppLocalizations.of(context);
    final canEditOrders = StaffPermissions.canActive('orders', 'edit');
    switch (s) {
      case JourneyStage.lead:
      case JourneyStage.survey:
      case JourneyStage.quote:
        return NgPrimaryButton(
          label: l.jrOpenSurveyQuote,
          icon: Icons.request_quote_rounded,
          onPressed: d.lead == null ? null : () => _openLead(d),
        );
      case JourneyStage.followUp:
        return _followUpForm(context, d);
      case JourneyStage.supervisor:
        return NgPrimaryButton(
          label: l.jrAssignInOrder,
          icon: Icons.engineering_rounded,
          onPressed: canEditOrders ? () => _openOrder(d) : null,
        );
      case JourneyStage.moveDay:
        return Row(
          children: [
            Expanded(
              child: NgPrimaryButton(
                label: l.jrOpenFieldJob,
                icon: Icons.local_shipping_rounded,
                onPressed: d.order?.id == null
                    ? null
                    : () => context.pushNamed(
                          SupervisorJobPageWidget.routeName,
                          queryParameters: {
                            'orderId':
                                serializeParam(d.order!.id, ParamType.String),
                          }.withoutNulls,
                        ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NgSecondaryButton(
                label: l.jrOpenOrder,
                height: 50,
                onPressed: () => _openOrder(d),
              ),
            ),
          ],
        );
      case JourneyStage.invoice:
        return NgPrimaryButton(
          label: l.jrOpenOrder,
          icon: Icons.receipt_long_rounded,
          onPressed: () => _openOrder(d),
        );
      case JourneyStage.payment:
      case JourneyStage.closed:
        return _paymentPanel(context, d);
    }
  }

  Widget _followUpForm(BuildContext context, JourneyData d) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    DateTime at10(int days) =>
        DateTime(now.year, now.month, now.day + days, 10);
    final quick = <(String, DateTime?)>[
      (l.jrNoNext, null),
      (l.jrToday, DateTime(now.year, now.month, now.day, 18)),
      (l.jrTomorrow, at10(1)),
      (l.jrIn2Days, at10(2)),
      (l.jrNextWeek, at10(7)),
    ];
    bool sameDay(DateTime? a, DateTime? b) =>
        a == null || b == null
            ? a == b
            : a.year == b.year && a.month == b.month && a.day == b.day;
    final pickedCustom = _next != null && !quick.any((q) => sameDay(q.$2, _next));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.jrOutcomeQ,
            style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in _outcomes)
              NgChip(
                label: _outcomeLabel(l, o),
                selected: _outcome == o,
                onTap: () => setState(() => _outcome = o),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _callNotes,
          style: NgFonts.geist(fontSize: 14, color: c.text),
          decoration: _fieldDecoration(c, l.jrCallNotes),
        ),
        const SizedBox(height: 12),
        Text(l.jrNextFollowUp,
            style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, at) in quick)
              NgChip(
                label: label,
                selected: !pickedCustom && sameDay(_next, at),
                onTap: () => setState(() => _next = at),
              ),
            NgChip(
              label: pickedCustom
                  ? DateFormat('d MMM').format(_next!)
                  : l.jrPickDate,
              selected: pickedCustom,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: now.add(const Duration(days: 3)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _next = DateTime(
                      picked.year, picked.month, picked.day, 10));
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: NgPrimaryButton(
                label: l.jrLogCall,
                icon: Icons.call_rounded,
                onPressed: _savingCall ? null : () => _logCall(d),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NgSecondaryButton(
                label: l.jrOpenSurveyQuote,
                height: 50,
                onPressed: () => _openLead(d),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(NgPalette c, String hint) =>
      InputDecoration(
        isDense: true,
        filled: true,
        fillColor: c.inset,
        hintText: hint,
        hintStyle: NgFonts.geist(fontSize: 14, color: c.faint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NgRadius.field),
          borderSide: BorderSide(color: c.w1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NgRadius.field),
          borderSide: BorderSide(color: c.w1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NgRadius.field),
          borderSide: BorderSide(color: c.acc),
        ),
      );

  Widget _paymentPanel(BuildContext context, JourneyData d) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final blockers = d.closeBlockers;
    Widget tile(String k, String v, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.inset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: NgFonts.geist(fontSize: 11, color: c.mute)),
                const SizedBox(height: 3),
                Text(v,
                    style: NgFonts.geist(
                        fontSize: 14, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            tile(l.jrTotal, _money.format(d.orderValue), c.text),
            const SizedBox(width: 6),
            tile(l.jrPaid, _money.format(d.paid), c.green),
            const SizedBox(width: 6),
            tile(l.jrBalance, _money.format(d.balance),
                d.balance > 0 ? c.amber : c.text),
          ],
        ),
        const SizedBox(height: 10),
        if (d.balance > 0)
          NgPrimaryButton(
            label: l.jrRecordPayment,
            icon: Icons.payments_rounded,
            onPressed: d.order?.id == null
                ? null
                : () => context.pushNamed(
                      RecordPaymentPageWidget.routeName,
                      queryParameters: {
                        'orderId':
                            serializeParam(d.order!.id, ParamType.String),
                      }.withoutNulls,
                    ),
          ),
        const SizedBox(height: 14),
        Text(l.jrTickets, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
        const SizedBox(height: 6),
        if (d.openTickets.isEmpty)
          Text(l.jrNoTickets, style: NgFonts.geist(fontSize: 13, color: c.faint))
        else
          for (final t in d.openTickets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.confirmation_number_rounded,
                      size: 18, color: c.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t.description ?? '',
                        style: NgFonts.geist(fontSize: 13, color: c.text)),
                  ),
                  TextButton(
                    onPressed: () => _resolveTicket(t),
                    child: Text(l.jrResolve,
                        style: NgFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.acc)),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ticketCtrl,
                style: NgFonts.geist(fontSize: 14, color: c.text),
                decoration: _fieldDecoration(c, l.jrTicketHint),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 132,
              child: NgSecondaryButton(
                label: l.jrRaiseTicket,
                icon: Icons.confirmation_number_rounded,
                height: 46,
                onPressed: _savingTicket ? null : () => _raiseTicket(d),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // The close gate: why the order cannot close yet. Closing itself
        // happens on Order Details, whose close is audited and refreshes
        // the approval queue — not duplicated here.
        for (final b in blockers)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.lock_rounded, size: 16, color: c.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    switch (b) {
                      CloseBlocker.openTicket => l.jrBlockTicket,
                      CloseBlocker.balanceDue =>
                        l.jrBlockBalance(_money.format(d.balance)),
                      CloseBlocker.noSignature => l.jrNotSigned,
                      CloseBlocker.noInvoice => l.jrNoInvoice,
                    },
                    style: NgFonts.geist(fontSize: 12.5, color: c.red),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        NgSecondaryButton(
          label: l.jrCloseOrder,
          icon: Icons.task_alt_rounded,
          iconColor: blockers.isEmpty ? c.green : c.faint,
          height: 46,
          onPressed: () => _openOrder(d),
        ),
      ],
    );
  }
}

/// The strip on Lead Details and Order Details that opens the journey
/// (handoff: "It opens from the strip on Lead detail or Order detail").
class JourneyEntryCard extends StatelessWidget {
  const JourneyEntryCard({super.key, this.leadId, this.orderId, this.data});

  final String? leadId;
  final String? orderId;

  /// When given, the card shows "Stage N of 9 · name" and a segmented bar
  /// (handoff "stage strip"); without it, just the title.
  final JourneyData? data;

  static String stageName(AppLocalizations l, JourneyStage s) => switch (s) {
        JourneyStage.lead => l.jrStageLead,
        JourneyStage.followUp => l.jrStageFollowUp,
        JourneyStage.survey => l.jrStageSurvey,
        JourneyStage.quote => l.jrStageQuote,
        JourneyStage.supervisor => l.jrStageSupervisor,
        JourneyStage.moveDay => l.jrStageMoveDay,
        JourneyStage.invoice => l.jrStageInvoice,
        JourneyStage.payment => l.jrStagePayment,
        JourneyStage.closed => l.jrStageClosed,
      };

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final d = data;
    final total = JourneyStage.values.length;
    final states = d?.states;
    final current = d?.current;
    final title = d == null
        ? l.jrTitle
        : current == null
            ? (d.isClosed ? l.odJourneyDone : l.jrTitle)
            : l.odStageOf(current.index + 1, total, stageName(l, current));
    return NgCard(
      onTap: () => context.pushNamed(
        OrderJourneyPageWidget.routeName,
        queryParameters: {
          'leadId': serializeParam(leadId, ParamType.String),
          'orderId': serializeParam(orderId, ParamType.String),
        }.withoutNulls,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.route_rounded, size: 24, color: c.acc),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
                if (states != null) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      for (final s in JourneyStage.values) ...[
                        if (s.index > 0) const SizedBox(width: 3),
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: switch (states[s]) {
                                JourneyState.done => c.green,
                                JourneyState.current => c.acc,
                                _ => c.w07,
                              },
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: c.faint),
        ],
      ),
    );
  }
}
