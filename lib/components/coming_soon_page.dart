import '/components/ng_widgets.dart';
import 'package:flutter/material.dart';

import '/flutter_flow/ng_tokens.dart';

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
    final ng = NgPalette.of(context);
    return Scaffold(
      backgroundColor: ng.bg,
      appBar: NgSimpleBar(title: title),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top_outlined,
                  size: 44, color: ng.mute),
              const SizedBox(height: 14),
              Text(
                '$title is coming soon',
                textAlign: TextAlign.center,
                style: NgFonts.geist(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ng.text,
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 8),
                Text(
                  note!,
                  textAlign: TextAlign.center,
                  style: NgFonts.geist(
                      fontSize: 13, color: ng.mute, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
