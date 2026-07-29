import '/app_session.dart';
import '/permissions.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Quick Entry as a popup (matches the React web app: FAB opens a centered
/// modal on the same screen instead of navigating to /quick-entry).
///
/// The full-screen QuickEntryPage and its /quick-entry route are kept for
/// deep links; the FAB now calls [QuickEntryDialog.show] instead.
/// The quick-entry tiles, as data rather than hardcoded layout — so they
/// can be filtered before anything is rendered (item 8).
// `final`, not `const`, so the routeName can reference each page widget's
// own static routeName. A string literal here would silently break on a
// route rename; this fails at compile time instead.
final List<({IconData icon, String label, String steps, String routeName})>
    _kQuickTiles = [
  (
    icon: Icons.person_add_alt_1,
    label: 'New Inquiry',
    steps: '3 steps',
    routeName: NewLeadPageWidget.routeName
  ),
  (
    icon: Icons.fact_check,
    label: 'Confirm Booking',
    steps: '4 steps',
    routeName: NewOrderPageWidget.routeName
  ),
  (
    icon: Icons.payments,
    label: 'Record Payment',
    steps: '2 steps',
    routeName: RecordPaymentPageWidget.routeName
  ),
  (
    icon: Icons.receipt_long,
    label: 'Quick Expense',
    steps: '2 steps',
    routeName: QuickExpensePageWidget.routeName
  ),
];

/// Which destination page each tile needs permission for. Mirrors
/// NavBarPage's `_navItems` gate so the FAB can't offer a shortcut into a
/// page the sidebar hides.
final Map<String, String> _kTilePermissionPage = {
  NewLeadPageWidget.routeName: 'LeadsPage',
  NewOrderPageWidget.routeName: 'OrdersPage',
  RecordPaymentPageWidget.routeName: 'PaymentsPage',
  QuickExpensePageWidget.routeName: 'ExpensePage',
};

bool _canSee(String routeName) {
  // Owner (no staff id) sees everything.
  if (AppSession.instance.currentStaffId == null) return true;
  final allowed = StaffPermissions.activeStaffPages ??
      const {'HomePage', 'OrdersPage', 'OperationsPage'};
  final page = _kTilePermissionPage[routeName];
  return page == null || allowed.contains(page);
}

class QuickEntryDialog extends StatelessWidget {
  const QuickEntryDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => const QuickEntryDialog(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    Widget tile({
      required IconData icon,
      required String label,
      required String steps,
      required String routeName,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // Capture the router BEFORE popping — after pop this dialog's
          // context is deactivated and context.pushNamed would throw.
          final router = GoRouter.of(context);
          Navigator.of(context).pop(); // close the popup first
          router.pushNamed(routeName);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            color: theme.primaryBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.secondaryText.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.primary, size: 26),
              const SizedBox(height: 10),
              Text(
                label,
                style: GoogleFonts.interTight(
                  color: theme.primaryText,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                steps,
                style: GoogleFonts.inter(
                  color: theme.secondaryText,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: theme.secondaryBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Quick Entry',
                    style: GoogleFonts.interTight(
                      color: theme.primaryText,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.secondaryText),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Item 8: was a hardcoded 2x2 of
              //   Row(Expanded(tile), SizedBox(12), Expanded(tile))
              // with no permission gate at all — so staff saw all four
              // tiles and tapped into owner-only pages, and the moment a
              // gate was added the fixed Row left the separator and the
              // vertical spacer behind as a blank slot that never
              // reflowed. Now: filter first, then lay out only what
              // survived. There is no placeholder widget for a hidden
              // tile anywhere in this build.
              _QuickGrid(tiles: [
                for (final t in _kQuickTiles)
                  if (_canSee(t.routeName))
                    tile(
                      icon: t.icon,
                      label: t.label,
                      steps: t.steps,
                      routeName: t.routeName,
                    ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays out however many tiles survived filtering, two per row, with the
/// separator built from the list rather than hardcoded — so an odd count
/// leaves no dangling gap and an empty list renders nothing at all.
class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'No quick actions available for your role.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: FlutterFlowTheme.of(context).secondaryText,
          ),
        ),
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final left = tiles[i];
      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          if (right != null) ...[
            const SizedBox(width: 12),
            Expanded(child: right),
          ] else
            // A lone tile on the last row keeps the grid's column width
            // instead of stretching full-bleed and looking like a
            // different component.
            const Expanded(child: SizedBox()),
        ],
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}
