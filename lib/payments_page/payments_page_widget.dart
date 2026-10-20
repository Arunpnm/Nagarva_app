import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/index.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/backend/detail_navigation.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/config/app_config.dart';
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
    // Arun's bug report: after a part-payment the trigger flips
    // payment_status to 'partial' and the order VANISHED from this list
    // (it only matched 'pending'). Correct definition of "pending
    // payment" = anything with a balance still due, whatever the status
    // label — so fetch non-paid and filter on the actual balance.
    _model.pendingOut = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q).neqOrNull(
        'payment_status',
        'paid',
      ),
    );
    _model.pendingList = (_model.pendingOut ?? [])
        .toList()
        .cast<OrdersRow>()
        .where(
            (o) => ((o.amount ?? 0) - o.paidTotal) > 0)
        .toList();
    safeSetState(() {});
    // Live 'Received (Month)' tile — the old one was a hardcoded
    // FlutterFlow string (₹1,24,000), same disease as the fake invoices.
    final now = DateTime.now();
    final entries = await PaymentEntriesTable().queryRows(
      queryFn: (q) => OrgScope.read(q),
    );
    _model.receivedThisMonth = entries
        .where((e) =>
            e.receivedAt != null &&
            e.receivedAt!.year == now.year &&
            e.receivedAt!.month == now.month)
        .fold(0.0, (s, e) => s + e.amount);
    safeSetState(() {});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  static double _due(OrdersRow o) => (o.amount ?? 0) - o.paidTotal;

  void _record(OrdersRow o) => context.pushNamed(
        RecordPaymentPageWidget.routeName,
        queryParameters: {
          'orderId': serializeParam(o.id, ParamType.String),
        }.withoutNulls,
      );

  /// WhatsApp reminder with a ready-made message. buildWhatsAppLink adds
  /// the India country code to a bare 10-digit number.
  void _remind(OrdersRow o) {
    final phone = (o.phone ?? '').trim();
    if (phone.isEmpty) return;
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
            '₹${outstanding.toStringAsFixed(0)}',
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
                  '₹${received.toStringAsFixed(0)}'),
              legend(c.accBtn, AppLocalizations.of(context).ngToCollect, '₹${outstanding.toStringAsFixed(0)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dueCard(BuildContext context, OrdersRow o) {
    final c = NgPalette.of(context);
    final partial = o.paidTotal > 0;
    final tone = partial ? NgStatus.amber : NgStatus.red;
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
                        '${o.fromCity ?? '-'} → ${o.toCity ?? '-'}',
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
                      '₹${_due(o).toStringAsFixed(0)}',
                      style: NgFonts.geist(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.text),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      partial
                          ? AppLocalizations.of(context).ngPartPaid
                          : AppLocalizations.of(context).ngUnpaid,
                      style: NgFonts.geist(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: c.status(tone).fg),
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

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    // The handoff groups what is owed by urgency: moves already done
    // (move date before today) are overdue; the rest are upcoming.
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final overdue = <OrdersRow>[];
    final upcoming = <OrdersRow>[];
    for (final o in _model.pendingList) {
      final d = o.moveDateOrNull;
      (d != null && d.isBefore(t0) ? overdue : upcoming).add(o);
    }
    final groups = [
      (AppLocalizations.of(context).ngOverdue, c.red, overdue),
      (AppLocalizations.of(context).ngUpcoming, c.amber, upcoming),
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
              NgScreenTitle(AppLocalizations.of(context).payments),
              const SizedBox(height: 14),
              _summaryCard(context),
              const SizedBox(height: 14),
              if (_model.pendingList.isEmpty)
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
                            '₹${rows.fold<double>(0, (s, o) => s + _due(o)).toStringAsFixed(0)}',
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
