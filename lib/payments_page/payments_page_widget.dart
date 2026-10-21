import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/whatsapp_cloud.dart';
import '/index.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/backend/detail_navigation.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/config/app_config.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'payments_page_model.dart';
export 'payments_page_model.dart';

/// Outstanding and received payment tracking.
class PaymentsPageWidget extends StatefulWidget {
  const PaymentsPageWidget({super.key});

  static String routeName = 'PaymentsPage';
  static String routePath = '/payments';

  @override
  State<PaymentsPageWidget> createState() => _PaymentsPageWidgetState();
}

class _PaymentsPageWidgetState extends State<PaymentsPageWidget>
    with RefreshOnPopMixin<PaymentsPageWidget> {
  late PaymentsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PaymentsPageModel());

    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadPayments());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1): re-run when a pushed
  // route (Record Payment) is popped back to this list.
  @override
  void onPageRefresh() => _loadPayments();

  // LEAK_AUDIT.md leak #1 (Stage 1 fix): this query had no org_id filter
  // at all — every org's pending-payment orders were returned. This page
  // is a live bottom-nav tab (see main.dart's NavBarPage tabs map), not
  // dead code, so it's fixed in place rather than removed.
  Future<void> _loadPayments() async {
    final orders = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q),
    );
    _ordersById = {
      for (final o in orders)
        if (o.id != null) o.id!: o
    };
    _model.pendingList = orders
        .where((o) =>
            (o.status ?? '').toLowerCase() != 'cancelled' &&
            o.paymentStatus != 'paid' &&
            _due(o) > 0)
        .toList();
    safeSetState(() {});
    final now = DateTime.now();
    final entries = await PaymentEntriesTable().queryRows(
      queryFn: (q) => OrgScope.read(q).order('received_at'),
    );
    _received = entries;
    _model.receivedThisMonth = entries
        .where((e) =>
            e.receivedAt != null &&
            e.receivedAt!.year == now.year &&
            e.receivedAt!.month == now.month)
        .fold(0.0, (s, e) => s + e.amount);
    safeSetState(() {});
  }

  Map<String, OrdersRow> _ordersById = const {};
  List<PaymentEntriesRow> _received = const [];

  /// 0 = Due, 1 = Received (the handoff's segmented control).
  int _tab = 0;

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  /// Quote total when one exists, else the order amount — the same base
  /// `dashboard_kpis_view.outstanding` uses, so this screen and the
  /// dashboard tile agree.
  static double _due(OrdersRow o) =>
      ((o.quoteTotal ?? 0) > 0 ? o.quoteTotal! : (o.amount ?? 0)) -
      o.paidTotal;

  void _record(OrdersRow o) => context.pushNamed(
        RecordPaymentPageWidget.routeName,
        queryParameters: {
          'orderId': serializeParam(o.id, ParamType.String),
        }.withoutNulls,
      );

  /// WhatsApp reminder with a ready-made message. buildWhatsAppLink adds
  /// the India country code to a bare 10-digit number.
  /// From the vendor's own WhatsApp number when the reminder template is
  /// approved; otherwise WhatsApp on this phone, as before.
  Future<void> _remind(OrdersRow o) async {
    final phone = (o.phone ?? '').trim();
    if (phone.isEmpty) return;
    try {
      if (await WhatsAppCloud.remindBalance(
          orderId: o.id, customer: o.customer, phone: phone, balance: _due(o))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Reminder sent from your WhatsApp number.')));
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    launchURL(buildWhatsAppLink(
      phone: phone,
      message: 'Dear ${o.customer}, '
          'greetings from ${AppSession.instance.currentOrgName ?? 'us'}! '
          'A payment of Rs.${_due(o).toStringAsFixed(0)} '
          'is pending for your shifting (${o.fromCity ?? ''} to ${o.toCity ?? ''}). '
          'Kindly arrange the payment. Thank you!',
    ));
  }

  Widget _summaryCard(BuildContext context) {
    final c = NgPalette.of(context);
    final outstanding =
        _model.pendingList.fold<double>(0.0, (s, o) => s + _due(o));
    final received = _model.receivedThisMonth;
    final total = outstanding + received;
    final colShare = total <= 0 ? 0.0 : received / total;
    Widget legend(Color dot, String label, String value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: dot, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 7),
            Text(label, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
            const SizedBox(width: 6),
            Text(value,
                style: NgFonts.geist(
                    fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
          ],
        );
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).paymentsPageOutstanding,
              style: NgFonts.geist(fontSize: 13, color: c.mute)),
          const SizedBox(height: 4),
          // Live: Σ balance due across the pending list below.
          Text(
            functions.inrFull(outstanding),
            style: NgFonts.geist(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
              color: c.text,
            ),
          ),
          const SizedBox(height: 14),
          // Collected this month (green) against what is still owed
          // (accent), the handoff's split bar.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (colShare > 0)
                    Expanded(
                      flex: (colShare * 1000).round(),
                      child: ColoredBox(color: c.green),
                    ),
                  if (colShare > 0 && colShare < 1) const SizedBox(width: 2),
                  if (colShare < 1)
                    Expanded(
                      flex: ((1 - colShare) * 1000).round(),
                      child: ColoredBox(color: c.accBtn),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              legend(c.green, AppLocalizations.of(context).receivedMonth,
                  functions.inrFull(received)),
              legend(c.accBtn, AppLocalizations.of(context).ngToCollect,
                  functions.inrFull(outstanding)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dueCard(BuildContext context, OrdersRow o) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final partial = o.paidTotal > 0;
    final tone = partial ? NgStatus.amber : NgStatus.red;
    final now = DateTime.now();
    final d = o.moveDateOrNull;
    final late = d == null
        ? 0
        : DateTime(now.year, now.month, now.day)
            .difference(DateTime(d.year, d.month, d.day))
            .inDays;
    final tag = late > 0
        ? l.ngDaysLate(late)
        : late == 0 && d != null
            ? l.ngToday
            : (partial ? l.ngPartPaid : l.ngUnpaid);
    final tagColor = late > 0
        ? c.red
        : late == 0 && d != null
            ? c.amber
            : c.status(tone).fg;
    final hasPhone = (o.phone ?? '').trim().isNotEmpty;
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        children: [
          InkWell(
            onTap: () => openOrderDetail(context, o),
            child: Row(
              children: [
                NgAvatar(o.customer, status: tone, size: 40),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.customer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.text),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${o.id} · ${o.fromCity ?? '-'} → ${o.toCity ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(fontSize: 12.5, color: c.mute),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Balance due, not gross amount: amount - collected.
                    Text(
                      functions.inrFull(_due(o)),
                      style: NgFonts.geist(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.text),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      tag,
                      style: NgFonts.geist(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tagColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NgSecondaryButton(
                  label: AppLocalizations.of(context).ngRemind,
                  icon: Icons.chat_rounded,
                  iconColor: c.green,
                  height: 40,
                  onPressed: hasPhone ? () => _remind(o) : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NgSecondaryButton(
                  label: AppLocalizations.of(context).ngRecord,
                  icon: Icons.price_check_rounded,
                  iconColor: c.acc,
                  height: 40,
                  onPressed: () => _record(o),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _receivedList(BuildContext context) {
    final c = NgPalette.of(context);
    final rows = _received.reversed.toList();
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(AppLocalizations.of(context).ngNoPaymentsYet,
              style: NgFonts.geist(fontSize: 14, color: c.mute)),
        ),
      );
    }
    return NgCardList(children: [
      for (final e in rows)
        InkWell(
          onTap: _ordersById[e.orderId] == null
              ? null
              : () => openOrderDetail(context, _ordersById[e.orderId]!),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                const NgIconTile(
                    icon: Icons.payments_outlined, status: NgStatus.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_ordersById[e.orderId]?.customer ?? e.orderId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NgFonts.geist(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: c.text)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          e.mode.toUpperCase(),
                          e.orderId,
                          if ((e.receiptNo ?? '').isNotEmpty) e.receiptNo!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(fontSize: 12.5, color: c.mute),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(functions.inrFull(e.amount),
                        style: NgFonts.geist(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: c.text)),
                    const SizedBox(height: 2),
                    Text(
                        e.receivedAt == null
                            ? ''
                            : DateFormat('d MMM')
                                .format(e.receivedAt!.toLocal()),
                        style: NgFonts.geist(fontSize: 12, color: c.faint)),
                  ],
                ),
              ],
            ),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    // The handoff groups what is owed by urgency: moves already done
    // (move date before today) are overdue; the rest are upcoming.
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final overdue = <OrdersRow>[];
    final dueToday = <OrdersRow>[];
    final upcoming = <OrdersRow>[];
    for (final o in _model.pendingList) {
      final d = o.moveDateOrNull;
      if (d != null && d.isBefore(t0)) {
        overdue.add(o);
      } else if (d != null && DateTime(d.year, d.month, d.day) == t0) {
        dueToday.add(o);
      } else {
        upcoming.add(o);
      }
    }
    final groups = [
      (AppLocalizations.of(context).ngOverdue, c.red, overdue),
      (AppLocalizations.of(context).ngToday, c.amber, dueToday),
      (AppLocalizations.of(context).ngUpcoming, c.blue, upcoming),
    ];
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: c.bg,
        appBar: const NgTopBar(),
        body: RefreshIndicator(
          onRefresh: _loadPayments,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              NgScreenTitle(
                AppLocalizations.of(context).payments,
                large: true,
                action: NgPrimaryButton(
                  compact: true,
                  icon: Icons.add_rounded,
                  label: AppLocalizations.of(context).ngRecord,
                  onPressed: () =>
                      context.pushNamed(RecordPaymentPageWidget.routeName),
                ),
              ),
              const SizedBox(height: 14),
              _summaryCard(context),
              const SizedBox(height: 14),
              NgSegmented(
                labels: [
                  AppLocalizations.of(context).ngDue,
                  AppLocalizations.of(context).ngReceived,
                ],
                counts: [_model.pendingList.length, _received.length],
                selected: _tab,
                onSelect: (i) => safeSetState(() => _tab = i),
              ),
              const SizedBox(height: 14),
              if (_tab == 1)
                _receivedList(context)
              else if (_model.pendingList.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      Icon(Icons.task_alt_rounded, size: 42, color: c.green),
                      const SizedBox(height: 12),
                      Text(
                        AppLocalizations.of(context).ngNothingToCollect,
                        style: NgFonts.geist(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.text),
                      ),
                    ],
                  ),
                )
              else
                for (final (title, dot, rows) in groups)
                  if (rows.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: dot, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(title,
                                style: NgFonts.geist(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.text)),
                          ),
                          Text(
                            functions.inrFull(rows.fold<double>(
                                0, (s, o) => s + _due(o))),
                            style: NgFonts.geist(fontSize: 13, color: c.mute),
                          ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _dueCard(context, rows[i]),
                    ],
                    const SizedBox(height: 14),
                  ],
              // The 'Pending Invoices' block that used to sit here was
              // FlutterFlow placeholder decoration (INV-045…048) — fake
              // data that made recorded payments look ignored. Removed;
              // the live list above is the real one.
            ],
          ),
        ),
      ),
    );
  }
}
