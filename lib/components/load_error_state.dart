import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_theme.dart';

/// Shared "this list failed to load" state (Materials/Staff/Fleet hang
/// follow-up, 7 Aug 2026) — an icon, the error message, and a Retry button
/// that re-runs the caller's own load method. Used in place of a
/// permanent "Loading…"/blank list when a page's primary query throws
/// (including the new query timeout in table.dart), so a failed load is
/// recoverable instead of reading as a frozen screen. No existing
/// "list load failed, retry" widget was found elsewhere in the app to
/// match — this is the one shape, meant to be reused by any future page
/// with the same need rather than each page growing its own.
class LoadErrorState extends StatelessWidget {
  const LoadErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 40, color: theme.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12.5, color: theme.error),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
