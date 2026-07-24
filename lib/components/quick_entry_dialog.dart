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
              color: theme.secondaryText.withOpacity(0.18),
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
              Row(
                children: [
                  Expanded(
                    child: tile(
                      icon: Icons.person_add_alt_1,
                      label: 'New Inquiry',
                      steps: '3 steps',
                      routeName: NewLeadPageWidget.routeName,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: tile(
                      icon: Icons.fact_check,
                      label: 'Confirm Booking',
                      steps: '4 steps',
                      routeName: NewOrderPageWidget.routeName,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: tile(
                      icon: Icons.payments,
                      label: 'Record Payment',
                      steps: '2 steps',
                      routeName: RecordPaymentPageWidget.routeName,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: tile(
                      icon: Icons.receipt_long,
                      label: 'Quick Expense',
                      steps: '2 steps',
                      routeName: QuickExpensePageWidget.routeName,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
