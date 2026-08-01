import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_theme.dart';

/// Shared placeholder for nav destinations that don't have a real screen
/// yet (Users Kickoff Step 2: "Wiring nav once is better than revisiting
/// it six times" — unbuilt modules appear in the nav model now and route
/// here instead of the nav being redesigned again when each one lands).
///
/// One widget, not one stub per destination, so the "still coming" list
/// has exactly one place to update as each module actually ships.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, this.note});

  final String title;

  /// Optional one-line context on what's blocking it / what's coming.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text(title,
            style: GoogleFonts.interTight(
                color: theme.primaryText, fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top_outlined,
                  size: 44, color: theme.secondaryText),
              const SizedBox(height: 14),
              Text(
                '$title is coming soon',
                textAlign: TextAlign.center,
                style: GoogleFonts.interTight(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryText,
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 8),
                Text(
                  note!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: theme.secondaryText, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
