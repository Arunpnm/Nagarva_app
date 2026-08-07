import '/app_session.dart';
import '/permissions.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Quick Entry as a bottom sheet (NG-FIX brief, bug 1 — 7 Aug 2026).
///
/// Was a centered `Dialog` via `showDialog` (matching the React web app's
/// centered modal). Device testing found it read as a full-screen box
/// rather than the sheet it was meant to evoke, and the bottom row of
/// tiles (Record Payment / Quick Expense) was tap-dead — most likely
/// because a content-sized `Dialog` with no scroll affordance can push its
/// lower content out of comfortable/reachable bounds on a real phone
/// viewport, not because of a permission gate (see [_canSee] below, which
/// already grants an owner session every tile with no gate at all).
///
/// Now a real `showModalBottomSheet`: [show] owns the whole
/// open-sheet-then-navigate sequence from the FAB's own live context, and
/// each tile's `onTap` only pops the sheet with its route name — it never
/// calls `context.pushNamed`/`GoRouter.of(context)` itself. This is a
/// structurally safer pattern than the old sheet-navigates-itself
/// approach regardless of the exact cause of the old dead-tap bug: there
/// is no window where navigation is attempted against a context that may
/// already be mid-deactivation.
///
/// The full-screen QuickEntryPage and its /quick-entry route are kept for
/// deep links; the FAB calls [QuickEntryDialog.show] instead.
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

/// NG-FIX brief, bug 1c hard stop: on an OWNER session
/// (`currentStaffId == null`) this returns true unconditionally for every
/// tile — no permission key is consulted at all. Read directly off this
/// function, not guessed: an owner session has no permission gate here to
/// be missing a key from. See the bug-1c finding in the fix commit for the
/// full readout of what this means for the "only 2 of 4 tiles" report.
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

  /// Opens the sheet and, if a tile was picked, navigates from this
  /// (live, caller-owned) context once the sheet has fully closed.
  /// `context.mounted` is the guard that makes this safe across the
  /// await — the FAB's HomePage context can only be unmounted here if the
  /// user navigated away by some other means while the sheet was open.
  static Future<void> show(BuildContext context) async {
    final routeName = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const QuickEntryDialog(),
    );
    if (routeName == null) return;
    if (!context.mounted) return;
    context.pushNamed(routeName);
  }

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
        // Only pops the sheet with the chosen route name — [show] does
        // the actual navigation, from a context that is never at risk of
        // having just been deactivated by this same tap.
        onTap: () => Navigator.of(context).pop(routeName),
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

    // Item 8 (still honoured): filter first, then lay out only what
    // survived — no placeholder widget for a hidden tile anywhere here.
    final tiles = [
      for (final t in _kQuickTiles)
        if (_canSee(t.routeName))
          tile(
            icon: t.icon,
            label: t.label,
            steps: t.steps,
            routeName: t.routeName,
          ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Quick Entry',
                    style: GoogleFonts.interTight(
                      color: theme.primaryText,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: theme.secondaryText),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (tiles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No quick actions available for your role.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: theme.secondaryText,
                  ),
                ),
              )
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: tiles,
              ),
          ],
        ),
      ),
    );
  }
}
