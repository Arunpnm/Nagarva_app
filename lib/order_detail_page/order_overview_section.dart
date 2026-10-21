import 'package:flutter/material.dart';

import '/backend/order_journey.dart';
import '/backend/whatsapp_cloud.dart';
import '/backend/order_stages.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/tracking_service.dart';
import '/backend/vendor_identity.dart';
import '/components/ng_widgets.dart';
import '/config/app_config.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import '/index.dart';
import '/l10n/gen/app_localizations.dart';
import '/permissions.dart';
import 'quick_payment_section.dart';

/// The top half of Order Details, per the Claude Design handoff
/// ("ORDER DETAIL"): journey strip, who and where, Call / WhatsApp / Maps,
/// the 6-step Progress card with its next action, Crew & vehicle, and the
/// Payment card. [OrderActivitySection] is its bottom-of-page partner.
///
/// Everything here reads the same rows the rest of the page does — it
/// adds no new source for any number. Two things in the handoff are left
/// out on purpose:
///  * "Notify customer on WhatsApp" — there is no WhatsApp send path yet
///    (AiSensy is Phase 4), so a switch would promise a message nobody
///    sends.
///  * "Mark as Delivered / Completed" — delivery is recorded by the crew's
///    arrival-code completion and closing by Close Order. A button here
///    would bypass both, so the card points at the field job instead.
class OrderOverviewSection extends StatefulWidget {
  const OrderOverviewSection({
    super.key,
    required this.orderId,
    required this.hideCustomer,
    this.onChanged,
  });

  final String orderId;

  /// Supervisor view of a finished job: no name, no phone.
  final bool hideCustomer;

  /// After a stage change or a payment, so the rest of the page reloads.
  final VoidCallback? onChanged;

  @override
  State<OrderOverviewSection> createState() => OrderOverviewSectionState();
}

class OrderOverviewSectionState extends State<OrderOverviewSection> {
  JourneyData? _data;
  Map<String, String> _staffNames = const {};
  Map<String, DateTime> _stageDates = const {};
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final d = await JourneyLoader.load(orderId: widget.orderId);
      final ids = d.crew.map((r) => r.staffId).whereType<String>().toSet();
      var names = <String, String>{};
      if (ids.isNotEmpty) {
        final staff = await StaffTable().queryRows(
            queryFn: (q) => OrgScope.read(q).inFilter('id', ids.toList()));
        names = {
          for (final s in staff)
            if (s.id != null) s.id!: s.name,
        };
      }
      final dates = <String, DateTime>{};
      try {
        final hist = await OrgScope.read(SupaFlow.client
                .from('order_status_history')
                .select('status, changed_at'))
            .eq('order_id', widget.orderId)
            .order('changed_at', ascending: true);
        for (final h in (hist as List)) {
          final st = canonicalOrderStage(h['status'] as String?);
          final at = DateTime.tryParse('${h['changed_at']}');
          if (st != null && at != null) dates.putIfAbsent(st, () => at);
        }
      } catch (_) {
        // Dates are a nicety on the Progress card; the steps still render.
      }
      if (!mounted) return;
      setState(() {
        _data = d;
        _staffNames = names;
        _stageDates = dates;
      });
    } catch (_) {
      // The rest of Order Details still renders without this block.
    }
  }

  // ---- derived -----------------------------------------------------------

  OrdersRow? get _order => _data?.order;

  bool get _cancelled =>
      (_order?.status ?? '').toLowerCase() == 'cancelled';

  /// Same revenue base as the Payments screen and Close Order: the quote
  /// when there is one, else the booked amount.
  double get _total {
    final q = _order?.quoteTotal ?? 0;
    return q > 0 ? q : (_order?.amount ?? 0);
  }

  double get _paid => _order?.paidTotal ?? 0;
  double get _balance => (_total - _paid) < 0 ? 0 : _total - _paid;

  String _stageLabel(AppLocalizations l, String stage) => switch (stage) {
        kStagePacking => l.odStPacking,
        kStageInTransit => l.odStInTransit,
        kStageArrived => l.odStArrived,
        kStageDelivered => l.odStDelivered,
        kStageCompleted => l.odStCompleted,
        _ => l.odStConfirmed,
      };

  String? _moveLine() {
    final o = _order;
    if (o == null) return null;
    final parts = <String>[];
    final raw = o.moveDateOrNull;
    if (raw != null) {
      parts.add(DateFormat('d MMM').format(raw));
    }
    if ((o.service ?? '').trim().isNotEmpty) parts.add(o.service!.trim());
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // ---- actions -----------------------------------------------------------

  Future<void> _advance(String next) async {
    setState(() => _advancing = true);
    try {
      await TrackingService.setStatus(
        orderId: widget.orderId,
        trackingStatus: next,
        // The crew's own Start Shifting writes 'transit' to status too;
        // mirror it so the order sits in the same OrdersPage tab either
        // way. Packing and Arrived are customer-facing only.
        status: next == kStageInTransit ? 'transit' : null,
      );
      await reload();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  void _openMaps() {
    final o = _order;
    if (o == null) return;
    String place(String? addr, String? city) =>
        [addr, city].where((x) => (x ?? '').trim().isNotEmpty).join(', ');
    final from = place(o.fromAddress, o.fromCity);
    final to = place(o.toAddress, o.toCity);
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (from.isNotEmpty) 'origin': from,
      if (to.isNotEmpty) 'destination': to,
    });
    launchURL(uri.toString());
  }

  /// From the vendor's own WhatsApp number when the reminder template is
  /// approved; otherwise WhatsApp on this phone, as before.
  Future<void> _remind() async {
    final o = _order;
    if (o == null) return;
    final l = AppLocalizations.of(context);
    try {
      if (await WhatsAppCloud.remindBalance(
          orderId: o.id, customer: o.customer, phone: o.phone, balance: _balance)) {
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
    if (!mounted) return;
    launchURL(buildWhatsAppLink(
      phone: o.phone,
      message: l.odRemindMsg(o.customer, functions.inrFull(_balance),
          o.id ?? '', VendorIdentity.forSentence),
    ));
  }

  Future<void> _recordPayment() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NgPalette.of(context).sheet,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(NgRadius.sheet))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: QuickPaymentSection(
            orderId: widget.orderId,
            onSaved: () {
              Navigator.of(ctx).maybePop();
              reload();
              widget.onChanged?.call();
            },
          ),
        ),
      ),
    );
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final o = _order;
    if (d == null || o == null) {
      return JourneyEntryCard(orderId: widget.orderId);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JourneyEntryCard(orderId: widget.orderId, data: d),
        const SizedBox(height: 18),
        _identity(context, o),
        const SizedBox(height: 14),
        _quickActions(context, o),
        const SizedBox(height: 14),
        if (!_cancelled) ...[
          _progress(context, d),
          const SizedBox(height: 14),
        ],
        _crew(context, d, o),
        const SizedBox(height: 14),
        _payment(context),
      ],
    );
  }

  Widget _identity(BuildContext context, OrdersRow o) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final idx = orderStageIndex(o.trackingStatus, o.status);
    final tone = _cancelled ? NgStatus.red : orderStageTone(idx);
    final fg = c.status(tone).fg;
    final moveLine = _moveLine();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              _cancelled
                  ? l.odCancelled
                  : '${_stageLabel(l, kOrderStages[idx])} · ${idx + 1}/${kOrderStages.length}',
              style: NgFonts.geist(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: fg),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            widget.hideCustomer ? 'Customer (hidden)' : o.customer,
            style: NgFonts.geist(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: c.text),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Flexible(
              child: Text(o.fromCity ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(fontSize: 15, color: c.soft)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 16, color: c.mute),
            ),
            Flexible(
              child: Text(o.toCity ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(fontSize: 15, color: c.soft)),
            ),
          ]),
          if (moveLine != null) ...[
            const SizedBox(height: 2),
            Text(moveLine,
                style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
          ],
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context, OrdersRow o) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final phone = widget.hideCustomer ? '' : (o.phone ?? '').trim();
    Widget btn(String label, IconData icon, Color color, VoidCallback? tap) =>
        Expanded(
          child: NgQuickAction(
              label: label, icon: icon, iconColor: color, onTap: tap),
        );
    return Row(children: [
      btn(l.ngCall, Icons.call_outlined, c.green,
          phone.isEmpty ? null : () => launchURL('tel:$phone')),
      const SizedBox(width: 8),
      btn(
          l.ngWhatsApp,
          Icons.chat_outlined,
          c.green,
          phone.isEmpty
              ? null
              : () => launchURL(buildWhatsAppLink(
                  phone: phone, message: 'Hi ${o.customer},'))),
      const SizedBox(width: 8),
      btn(l.odMaps, Icons.navigation_outlined, c.blue, _openMaps),
    ]);
  }

  Widget _progress(BuildContext context, JourneyData d) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final o = d.order!;
    final idx = orderStageIndex(o.trackingStatus, o.status);
    final next =
        idx + 1 < kOrderStages.length ? kOrderStages[idx + 1] : null;
    final canEdit = StaffPermissions.canActive('orders', 'edit');
    // Only the customer-facing steps before delivery are a tap here; see
    // the class comment for why Delivered and Completed are not.
    final tappable = next != null &&
        kOrderStages.indexOf(next) <= kOrderStages.indexOf(kStageArrived);
    return NgCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(l.odProgress,
                  style: NgFonts.geist(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
            ),
            Text('${idx + 1}/${kOrderStages.length}',
                style: NgFonts.mono(fontSize: 14, color: c.mute)),
          ]),
          const SizedBox(height: 10),
          for (var i = 0; i < kOrderStages.length; i++)
            _step(context, kOrderStages[i], i < idx, i == idx,
                isLastDone: i == idx && idx == kOrderStages.length - 1),
          if (canEdit && next != null) ...[
            const SizedBox(height: 12),
            if (tappable)
              NgPrimaryButton(
                label: l.odMarkAs(_stageLabel(l, next)),
                icon: Icons.check_circle_outline_rounded,
                onPressed: _advancing ? null : () => _advance(next),
              )
            else if (next == kStageDelivered) ...[
              Text(l.odDeliveredHint,
                  style: NgFonts.geist(
                      fontSize: 12.5, height: 1.4, color: c.mute)),
              const SizedBox(height: 10),
              NgSecondaryButton(
                label: l.odOpenFieldJob,
                icon: Icons.local_shipping_outlined,
                iconColor: c.acc,
                onPressed: () => context.pushNamed(
                  SupervisorJobPageWidget.routeName,
                  queryParameters: {
                    'orderId': serializeParam(o.id, ParamType.String),
                  }.withoutNulls,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _step(BuildContext context, String stage, bool done, bool current,
      {bool isLastDone = false}) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final date = _stageDates[stage];
    final finished = done || isLastDone;
    Widget dot;
    if (finished) {
      dot = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: c.green, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
      );
    } else if (current) {
      dot = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: c.acc, shape: BoxShape.circle),
      );
    } else {
      dot = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
            shape: BoxShape.circle, border: Border.all(color: c.w15, width: 1.5)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        dot,
        const SizedBox(width: 14),
        Expanded(
          child: Text(_stageLabel(l, stage),
              style: NgFonts.geist(
                  fontSize: 15,
                  fontWeight: current && !finished
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: finished || current ? c.text : c.mute)),
        ),
        if (current && !finished)
          Text(l.odInProgress,
              style: NgFonts.geist(fontSize: 12.5, color: c.mute))
        else if (finished && date != null)
          Text(DateFormat('d MMM').format(date.toLocal()),
              style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
      ]),
    );
  }

  Widget _crew(BuildContext context, JourneyData d, OrdersRow o) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final names = [
      for (final r in d.crew)
        if ((_staffNames[r.staffId] ?? '').isNotEmpty) _staffNames[r.staffId]!,
    ];
    final vehicleNo = (o.vehicleNo ?? '').trim();
    final vehicleType =
        [o.vehicleType, o.chosenVehicle].firstWhere(
            (v) => (v ?? '').trim().isNotEmpty,
            orElse: () => null);
    final sub = (d.supervisorName ?? '').isNotEmpty
        ? l.odSupervisorCrew(d.supervisorName!, names.length)
        : l.odCrewCount(names.length);
    return NgCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.odCrewVehicle,
              style: NgFonts.geist(
                  fontSize: 16.5, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 12),
          if (names.isEmpty)
            Text(l.odNoCrew,
                style: NgFonts.geist(fontSize: 13.5, color: c.mute))
          else
            Row(children: [
              SizedBox(
                width: 22.0 * (names.length.clamp(1, 4) - 1) + 30,
                height: 30,
                child: Stack(children: [
                  for (var i = 0; i < names.length.clamp(0, 4); i++)
                    Positioned(
                      left: 22.0 * i,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c.s1, width: 2),
                        ),
                        child: NgAvatar(names[i],
                            status: NgStatus.neutral, size: 26),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(names.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: c.text)),
                    Text(sub,
                        style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                  ],
                ),
              ),
            ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: c.w07),
          ),
          Row(children: [
            Icon(Icons.local_shipping_outlined, size: 22, color: c.mute),
            const SizedBox(width: 12),
            Expanded(
              child: vehicleNo.isEmpty
                  ? Text(l.odNoVehicle,
                      style: NgFonts.geist(fontSize: 13.5, color: c.mute))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vehicleNo,
                            style: NgFonts.mono(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: c.text)),
                        if (vehicleType != null)
                          Text(vehicleType,
                              style: NgFonts.geist(
                                  fontSize: 12.5, color: c.mute)),
                      ],
                    ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _payment(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final total = _total;
    final paid = _paid;
    final bal = _balance;
    final (label, tone) = total <= 0
        ? (null, NgStatus.neutral)
        : bal <= 0
            ? (l.odFullyPaid, NgStatus.green)
            : paid > 0
                ? (l.odPartPaid, NgStatus.amber)
                : (l.odUnpaid, NgStatus.red);
    final canEdit = StaffPermissions.canActive('orders', 'edit');
    Widget fig(String cap, double v, Color col) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cap, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(functions.inrFull(v),
                    style: NgFonts.geist(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        color: col)),
              ),
            ],
          ),
        );
    return NgCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(l.odPayment,
                  style: NgFonts.geist(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
            ),
            if (label != null) NgPill(label, status: tone),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            fig(l.odTotal, total, c.text),
            fig(l.odPaid, paid, c.green),
            fig(l.odBalance, bal, bal > 0 ? c.acc : c.text),
          ]),
          const SizedBox(height: 12),
          NgProgressBar(
              value: total <= 0 ? 0 : (paid / total).clamp(0.0, 1.0),
              color: c.green,
              height: 5),
          if (bal > 0 && (canEdit || !widget.hideCustomer)) ...[
            const SizedBox(height: 12),
            Row(children: [
              if (!widget.hideCustomer && (_order?.phone ?? '').isNotEmpty)
                Expanded(
                  child: NgSecondaryButton(
                    label: l.odRemind,
                    icon: Icons.chat_outlined,
                    iconColor: c.green,
                    onPressed: _remind,
                  ),
                ),
              if (!widget.hideCustomer &&
                  (_order?.phone ?? '').isNotEmpty &&
                  canEdit)
                const SizedBox(width: 8),
              if (canEdit)
                Expanded(
                  child: NgSecondaryButton(
                    label: l.odRecordPayment,
                    icon: Icons.currency_rupee_rounded,
                    iconColor: c.acc,
                    onPressed: _recordPayment,
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Activity timeline at the foot of Order Details: stage changes from
/// `order_status_history` and money from `payment_entries`, newest first.
class OrderActivitySection extends StatefulWidget {
  const OrderActivitySection({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderActivitySection> createState() => OrderActivitySectionState();
}

class _Event {
  _Event(this.at, this.title, this.sub, this.icon, this.tone, {this.amount});
  final DateTime at;

  /// Set on a payment row; null on a stage change.
  final double? amount;
  final String title;
  final String? sub;
  final IconData icon;
  final NgStatus tone;
}

class OrderActivitySectionState extends State<OrderActivitySection> {
  List<_Event>? _events;
  bool _all = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final out = <_Event>[];
    try {
      final hist = await OrgScope.read(SupaFlow.client
              .from('order_status_history')
              .select('status, note, changed_at'))
          .eq('order_id', widget.orderId)
          .order('changed_at', ascending: false)
          .limit(100);
      for (final h in (hist as List)) {
        final at = DateTime.tryParse('${h['changed_at']}');
        if (at == null) continue;
        out.add(_Event(at, '${h['status'] ?? ''}', h['note'] as String?,
            Icons.swap_horiz_rounded, NgStatus.amber));
      }
    } catch (_) {}
    try {
      final pays = await PaymentEntriesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId),
      );
      for (final p in pays) {
        final at = p.receivedAt ?? p.createdAt;
        if (at == null) continue;
        out.add(_Event(at, '', p.mode, Icons.payments_outlined, NgStatus.green,
            amount: p.amount));
      }
    } catch (_) {}
    out.sort((a, b) => b.at.compareTo(a.at));
    if (mounted) setState(() => _events = out);
  }

  String _stageText(AppLocalizations l, String raw) {
    final st = canonicalOrderStage(raw);
    final label = switch (st) {
      kStageConfirmed => l.odStConfirmed,
      kStagePacking => l.odStPacking,
      kStageInTransit => l.odStInTransit,
      kStageArrived => l.odStArrived,
      kStageDelivered => l.odStDelivered,
      kStageCompleted => l.odStCompleted,
      _ => raw,
    };
    return '${l.odStageChanged} · $label';
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final ev = _events;
    if (ev == null) return const SizedBox.shrink();
    final shown = _all ? ev : ev.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Row(children: [
            Expanded(
              child: Text(l.odActivity,
                  style: NgFonts.geist(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
            ),
            if (ev.length > 6 && !_all)
              InkWell(
                onTap: () => setState(() => _all = true),
                child: Row(children: [
                  Text(l.odAllN(ev.length),
                      style: NgFonts.geist(fontSize: 14, color: c.acc)),
                  Icon(Icons.chevron_right_rounded, size: 18, color: c.acc),
                ]),
              ),
          ]),
        ),
        if (ev.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(l.odNoActivity,
                style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
          ),
        for (var i = 0; i < shown.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 36,
                  child: Column(children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                          color: c.status(shown[i].tone).bg,
                          shape: BoxShape.circle),
                      child: Icon(shown[i].icon,
                          size: 16, color: c.status(shown[i].tone).fg),
                    ),
                    if (i < shown.length - 1)
                      Expanded(
                          child: Container(width: 2, color: c.w07)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shown[i].amount != null
                              ? l.odPaymentReceived(
                                  functions.inrFull(shown[i].amount!))
                              : _stageText(l, shown[i].title),
                          style: NgFonts.geist(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: c.text),
                        ),
                        Text(
                          [
                            if ((shown[i].sub ?? '').trim().isNotEmpty)
                              shown[i].sub!.trim(),
                            DateFormat('d MMM, h:mm a')
                                .format(shown[i].at.toLocal()),
                          ].join(' · '),
                          style:
                              NgFonts.geist(fontSize: 12.5, color: c.mute),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
