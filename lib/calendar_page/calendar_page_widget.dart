import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/reminders_service.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/components/keyboard_scroll_view.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'calendar_page_model.dart';
export 'calendar_page_model.dart';

/// Calendar with reminders and follow-up tracking.
class CalendarPageWidget extends StatefulWidget {
  const CalendarPageWidget({super.key});

  static String routeName = 'CalendarPage';
  static String routePath = '/calendar';

  @override
  State<CalendarPageWidget> createState() => _CalendarPageWidgetState();
}

class _CalendarPageWidgetState extends State<CalendarPageWidget>
    with RefreshOnPopMixin<CalendarPageWidget> {
  late CalendarPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => CalendarPageModel());

    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadCalendarData());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1).
  @override
  void onPageRefresh() => _loadCalendarData();

  Future<void> _loadCalendarData() async {
    // Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
    _model.remindersViewOut = await RemindersViewTable().queryRows(
      queryFn: (q) => OrgScope.read(q),
    );
    _model.remindersViewList =
        (_model.remindersViewOut ?? []).toList().cast<RemindersViewRow>();
    safeSetState(() {});
    // Orders double as calendar events on their move_date (reference-app
    // behaviour): dots on the grid, details in the day panel on tap.
    final orders = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q).order('move_date'),
    );
    _model.ordersList = orders.toList().cast<OrdersRow>();
    safeSetState(() {});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  /// "Add Reminder" — was a FlutterFlow stub (`print('AddReminderBtn
  /// pressed ...')`, no action). This reminder isn't tied to a lead/quote/
  /// order (CalendarPage shows every org reminder, not one entity's), so
  /// it goes through `RemindersService.add` with entityType/entityId left
  /// null — the table's original, pre-polymorphic shape.
  Future<void> _addReminder() async {
    final titleController = TextEditingController();
    final noteController = TextEditingController();
    final selected = _model.selectedDay;
    // Default to the tapped day at 10am; if no day is selected, tomorrow
    // at 10am — a reminder due at the current time of day is rarely what
    // anyone means (same convention as reminders_section.dart's sheet).
    final defaultDay = selected ?? DateTime.now().add(const Duration(days: 1));
    DateTime due =
        DateTime(defaultDay.year, defaultDay.month, defaultDay.day, 10, 0);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).addReminder),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: due,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 1)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        due = DateTime(
                            picked.year, picked.month, picked.day, 10, 0);
                      });
                    }
                  },
                  icon: const Icon(Icons.event, size: 17),
                  label: Text('${due.day}/${due.month}/${due.year}'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final title = titleController.text.trim();
    final note = noteController.text.trim();
    titleController.dispose();
    noteController.dispose();

    if (saved != true) return;
    try {
      await RemindersService.add(
        title: title,
        dueAt: due,
        note: note.isEmpty ? null : note,
      );
      if (mounted) await _loadCalendarData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save reminder: $e')),
        );
      }
    }
  }

  // ---- Month grid helpers -------------------------------------------------

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Days (in the visible month) that have at least one reminder due.
  Set<int> _reminderDays() {
    final out = <int>{};
    for (final r in _model.remindersViewList) {
      final d = DateTime.tryParse(r.dueDate ?? '');
      if (d != null &&
          d.year == _model.visibleMonth.year &&
          d.month == _model.visibleMonth.month) {
        out.add(d.day);
      }
    }
    return out;
  }

  // OrdersRow.moveDate does getField<DateTime>('move_date')! — a
  // non-null assert that throws (blanking the whole page, item 5 in
  // NAGARVA_STATUS.md) for any order whose move_date is actually null in
  // the DB. move_date is a required field on the New Order form, but
  // other insert paths (e.g. LeadDetailPage's convert-to-order, or old
  // pre-validation rows) aren't guaranteed to have set it. Read the raw
  // nullable field here instead of the throwing getter.
  DateTime? _safeMoveDate(OrdersRow o) => o.getField<DateTime>('move_date');

  /// Days (in the visible month) that have at least one order moving.
  Set<int> _orderDays() {
    final out = <int>{};
    for (final o in _model.ordersList) {
      final d = _safeMoveDate(o);
      if (d != null &&
          d.year == _model.visibleMonth.year &&
          d.month == _model.visibleMonth.month) {
        out.add(d.day);
      }
    }
    return out;
  }

  List<OrdersRow> _ordersOn(DateTime day) => _model.ordersList.where((o) {
        final d = _safeMoveDate(o);
        return d != null && _sameDay(d, day);
      }).toList();

  Widget _monthGrid(BuildContext context) {
    final ng = NgPalette.of(context);
    final month = _model.visibleMonth;
    final today = DateTime.now();
    final monthName = DateFormat('MMMM yyyy').format(month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday-first offset: DateTime.weekday is 1 (Mon) … 7 (Sun).
    final leadingBlanks = DateTime(month.year, month.month, 1).weekday - 1;
    final reminderDays = _reminderDays();
    final orderDays = _orderDays();

    Widget dayCell(int? day) {
      if (day == null) return const Expanded(child: SizedBox(height: 44));
      final date = DateTime(month.year, month.month, day);
      final isToday = _sameDay(date, today);
      final isSelected =
          _model.selectedDay != null && _sameDay(date, _model.selectedDay!);
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => safeSetState(() {
            _model.selectedDay = isSelected ? null : date;
          }),
          child: SizedBox(
            height: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? ng.acc
                        : isToday
                            ? ng.acc.withOpacity(0.25)
                            : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$day',
                    style: NgFonts.geist(
                      fontSize: 13,
                      fontWeight: isToday || isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? ng.bg
                          : ng.text,
                    ),
                  ),
                ),
                SizedBox(
                  height: 5,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (orderDays.contains(day))
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: ng.acc,
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (reminderDays.contains(day))
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: NgPalette.of(context).amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Build week rows: leading blanks, then 1..daysInMonth, pad the tail.
    final cells = <int?>[
      ...List<int?>.filled(leadingBlanks, null),
      ...List<int?>.generate(daysInMonth, (i) => i + 1),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final weeks = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      weeks.add(Row(
        children: [for (final c in cells.sublist(i, i + 7)) dayCell(c)],
      ));
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ng.s1,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left, color: ng.acc),
                  onPressed: () => safeSetState(() {
                    _model.visibleMonth = DateTime(month.year, month.month - 1);
                    _model.selectedDay = null;
                  }),
                ),
                Text(
                  monthName,
                  style: NgFonts.geist(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ng.text,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right, color: ng.acc),
                  onPressed: () => safeSetState(() {
                    _model.visibleMonth = DateTime(month.year, month.month + 1);
                    _model.selectedDay = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final d in [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun'
                ])
                  Expanded(
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: NgFonts.geist(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: ng.mute,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ...weeks,
          ],
        ),
      ),
    );
  }

  Widget _dayEventsCard(BuildContext context) {
    final ng = NgPalette.of(context);
    final day = _model.selectedDay!;
    final orders = _ordersOn(day);
    Color statusColor(String st) {
      switch (st.toLowerCase()) {
        case 'delivered':
        case 'closed':
        case 'done':
          return NgPalette.of(context).green;
        case 'cancelled':
          return ng.red;
        case 'transit':
          return NgPalette.of(context).blue;
        default:
          return ng.acc;
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ng.s1,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, d MMMM').format(day),
              style: NgFonts.geist(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ng.text,
              ),
            ),
            Text(
              '${orders.length} order(s)',
              style:
                  NgFonts.geist(fontSize: 11.5, color: ng.mute),
            ),
            const SizedBox(height: 10),
            if (orders.isEmpty)
              Text(
                'No orders moving this day. Reminders for this day are '
                'listed below.',
                style: NgFonts.geist(
                    fontSize: 12.5, color: ng.mute),
              )
            else
              ...orders.map((o) {
                final st = o.status ?? '—';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      context.pushNamed(
                        OrderDetailPageWidget.routeName,
                        queryParameters: {
                          'orderId': serializeParam(o.id, ParamType.String),
                          'orderCustomer':
                              serializeParam(o.customer, ParamType.String),
                          'orderPhone':
                              serializeParam(o.phone, ParamType.String),
                          'orderFromCity':
                              serializeParam(o.fromCity, ParamType.String),
                          'orderToCity':
                              serializeParam(o.toCity, ParamType.String),
                          'orderAmount': serializeParam(
                              o.amount?.toString(), ParamType.String),
                          'orderStatus':
                              serializeParam(o.status, ParamType.String),
                          'orderMoveDate': serializeParam(
                              o.moveDate.toString(), ParamType.String),
                        }.withoutNulls,
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ng.bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  o.customer,
                                  overflow: TextOverflow.ellipsis,
                                  style: NgFonts.geist(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: ng.text,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: statusColor(st).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  st.toUpperCase(),
                                  style: NgFonts.geist(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor(st),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              if ((o.phone ?? '').isNotEmpty) o.phone!,
                              '${o.fromCity ?? ''} → ${o.toCity ?? ''}',
                            ].join('  ·  '),
                            style: NgFonts.geist(
                                fontSize: 11.5, color: ng.mute),
                          ),
                          if (o.amount != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              '₹${o.amount!.toStringAsFixed(0)}',
                              style: NgFonts.geist(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ng.acc,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            Row(
              children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: ng.acc, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('Order',
                    style: NgFonts.geist(
                        fontSize: 10.5, color: ng.mute)),
                const SizedBox(width: 12),
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: NgPalette.of(context).amber,
                        shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('Follow-up',
                    style: NgFonts.geist(
                        fontSize: 10.5, color: ng.mute)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: NgPalette.of(context).bg,
        appBar: NgTopBar(onRefresh: _loadCalendarData),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              color: NgPalette.of(context).bg,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: KeyboardScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Real month grid — replaces ~2,000 lines of hardcoded
                    // FlutterFlow decoration (static "May 2025", six
                    // left-clustered week Rows). Month nav works, today is
                    // highlighted, days with reminders get a dot, and
                    // tapping a day filters the reminders list below.
                    NgModuleHeader(
                      AppLocalizations.of(context).calendarPageCalendar,
                      actions: [
                        NgPrimaryButton(
                          compact: true,
                          height: 40,
                          icon: Icons.alarm_add_outlined,
                          label: AppLocalizations.of(context).addReminder,
                          onPressed: _addReminder,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _monthGrid(context),
                    // Day panel — reference-app behaviour: tap a date to see
                    // what its dots mean (orders moving that day, tappable
                    // through to Order Details, plus that day's reminders
                    // filtered in the list below).
                    if (_model.selectedDay != null) _dayEventsCard(context),
                    // Dropped ~470 lines of hardcoded FlutterFlow mockup
                    // reminder cards (Ravi Menon, ORD-047, TN-01-AB-1234,
                    // May Expenses) that used to render here, presented as
                    // if real. The "Reminders & Follow-ups" heading that
                    // sat above them is gone too — redundant with the live
                    // list's own heading right below.
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          AppLocalizations.of(context).activeRemindersLive,
                          style: NgFonts.geist(fontSize: 17, fontWeight: FontWeight.w600, 
                                color: NgPalette.of(context).text,
                                ),
                        ),
                        Builder(
                          builder: (context) {
                            final remindersViewListItem =
                                // Tapping a day in the grid filters this
                                // list; tap the day again to clear.
                                _model.selectedDay == null
                                    ? _model.remindersViewList.toList()
                                    : _model.remindersViewList.where((r) {
                                        final d =
                                            DateTime.tryParse(r.dueDate ?? '');
                                        return d != null &&
                                            _sameDay(d, _model.selectedDay!);
                                      }).toList();

                            return ListView.separated(
                              padding: EdgeInsets.zero,
                              primary: false,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              scrollDirection: Axis.vertical,
                              itemCount: remindersViewListItem.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8.0),
                              itemBuilder:
                                  (context, remindersViewListItemIndex) {
                                final remindersViewListItemItem =
                                    remindersViewListItem[
                                        remindersViewListItemIndex];
                                return Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: NgPalette.of(context).s1,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14.0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.max,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 4.0,
                                          decoration: BoxDecoration(
                                            color: NgPalette.of(context).acc,
                                            borderRadius:
                                                BorderRadius.circular(2.0),
                                          ),
                                          child: Container(
                                            height: 44.0,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 1,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                remindersViewListItemItem
                                                        .title ??
                                                    '-',
                                                style:
                                                    NgFonts.geist(fontSize: 15, fontWeight: FontWeight.w600, 
                                                          color: NgPalette.of(context).text,
                                                          ),
                                              ),
                                              Text(
                                                remindersViewListItemItem
                                                        .description ??
                                                    '-',
                                                style: NgFonts.geist(fontSize: 12.5, 
                                                      color:
                                                          NgPalette.of(context).mute,
                                                      ),
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.max,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    remindersViewListItemItem
                                                            .dueDate ??
                                                        '-',
                                                    style: NgFonts.geist(fontSize: 11, fontWeight: FontWeight.w500, 
                                                          color: NgPalette.of(context).acc,
                                                          ),
                                                  ),
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: NgPalette.of(context).bg,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6.0),
                                                    ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional
                                                              .fromSTEB(6.0,
                                                              2.0, 6.0, 2.0),
                                                      child: Text(
                                                        remindersViewListItemItem
                                                                .reminderType ??
                                                            '-',
                                                        style:
                                                            NgFonts.geist(fontSize: 11, fontWeight: FontWeight.w500, 
                                                                  color: NgPalette.of(context).mute,
                                                                  ),
                                                      ),
                                                    ),
                                                  ),
                                                ].divide(
                                                    const SizedBox(width: 8.0)),
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.max,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.person_outline,
                                                    color: NgPalette.of(context).mute,
                                                    size: 12.0,
                                                  ),
                                                  Text(
                                                    remindersViewListItemItem
                                                            .leadCustomer ??
                                                        '-',
                                                    style: NgFonts.geist(fontSize: 11, fontWeight: FontWeight.w500, 
                                                          color: NgPalette.of(context).mute,
                                                          ),
                                                  ),
                                                  Text(
                                                    remindersViewListItemItem
                                                            .orderCustomer ??
                                                        '-',
                                                    style: NgFonts.geist(fontSize: 11, fontWeight: FontWeight.w500, 
                                                          color: NgPalette.of(context).mute,
                                                          ),
                                                  ),
                                                ].divide(
                                                    const SizedBox(width: 4.0)),
                                              ),
                                            ].divide(
                                                const SizedBox(height: 3.0)),
                                          ),
                                        ),
                                      ].divide(const SizedBox(width: 12.0)),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ].divide(const SizedBox(height: 10.0)),
                    ),

                  ].divide(const SizedBox(height: 16.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
