import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'quick_entry_page_model.dart';
export 'quick_entry_page_model.dart';

/// Quick entry launcher with 4 common action shortcuts.
class QuickEntryPageWidget extends StatefulWidget {
  const QuickEntryPageWidget({super.key});

  static String routeName = 'QuickEntryPage';
  static String routePath = '/quick-entry';

  @override
  State<QuickEntryPageWidget> createState() => _QuickEntryPageWidgetState();
}

class _QuickEntryPageWidgetState extends State<QuickEntryPageWidget> {
  late QuickEntryPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => QuickEntryPageModel());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final tiles = <(IconData, NgStatus, String, String)>[
      (Icons.person_add_alt_1_rounded, NgStatus.accent, l.newInquiry,
          NewLeadPageWidget.routeName),
      (Icons.assignment_turned_in_outlined, NgStatus.blue, l.confirmBooking,
          NewOrderPageWidget.routeName),
      (Icons.payments_outlined, NgStatus.green, l.recordPayment,
          RecordPaymentPageWidget.routeName),
      (Icons.receipt_long_outlined, NgStatus.amber, l.quickExpense,
          QuickExpensePageWidget.routeName),
    ];
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: c.bg,
      appBar: NgSimpleBar(title: l.quickEntry),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Text(l.whatWouldYouLikeToDo,
                style: NgFonts.geist(fontSize: 14, color: c.mute)),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: [
              for (final t in tiles)
                NgCard(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  onTap: () => context.pushNamed(t.$4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NgIconTile(
                          icon: t.$1, status: t.$2, size: 44, iconSize: 22),
                      const Spacer(),
                      Text(t.$3,
                          style: NgFonts.geist(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.text)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
