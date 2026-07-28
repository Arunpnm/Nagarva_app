import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_theme.dart';

/// Shared label/value row for detail screens (live-test fix brief #2,
/// item 4).
///
/// The FlutterFlow-generated detail pages each hand-rolled this row, so
/// padding, alignment and overflow behaviour drifted between cards: some
/// rows used `MainAxisAlignment.spaceBetween` with two unconstrained
/// `Text`s (which overflows rather than wraps once the value is long),
/// some centred vertically and some didn't, and empty values rendered as
/// a bare `-` or crashed on a null-assert.
///
/// Rules this enforces everywhere it's used:
///  * label left, fixed style, never wraps past 2 lines
///  * value right-aligned, [Flexible] so it wraps instead of overflowing
///  * consistent 6px vertical padding, values on one vertical grid
///  * null/empty value renders [placeholder] ("—") instead of throwing
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.placeholder = '—',
    this.hideWhenEmpty = false,
    this.valueColor,
    this.maxValueLines = 3,
    this.onTap,
  });

  final String label;
  final String? value;

  /// Shown when [value] is null/blank and [hideWhenEmpty] is false.
  final String placeholder;

  /// Item 4.3: some rows (e.g. Email) are better hidden entirely than
  /// shown as an empty dash.
  final bool hideWhenEmpty;

  final Color? valueColor;
  final int maxValueLines;
  final VoidCallback? onTap;

  bool get _isEmpty => value == null || value!.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isEmpty && hideWhenEmpty) return const SizedBox.shrink();
    final theme = FlutterFlowTheme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              maxLines: 2,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.3,
                color: theme.secondaryText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              _isEmpty ? placeholder : value!.trim(),
              textAlign: TextAlign.right,
              maxLines: maxValueLines,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: _isEmpty
                    ? theme.secondaryText
                    : (valueColor ?? theme.primaryText),
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: row,
    );
  }
}

/// Card wrapper matching the detail pages' existing surface treatment, so
/// a group of [DetailRow]s sits on the same grid as the rest of the page.
class DetailCard extends StatelessWidget {
  const DetailCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.interTight(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: theme.primary,
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

/// Free-text block (notes, instructions) — a [DetailRow] would squeeze a
/// paragraph into a right-aligned column, which is what made the Notes
/// card look broken.
class DetailNote extends StatelessWidget {
  const DetailNote({
    super.key,
    required this.text,
    this.emptyLabel = 'No notes yet',
  });

  final String? text;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final empty = text == null || text!.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        empty ? emptyLabel : text!.trim(),
        style: GoogleFonts.inter(
          fontSize: 13.5,
          height: 1.4,
          fontStyle: empty ? FontStyle.italic : FontStyle.normal,
          color: empty ? theme.secondaryText : theme.primaryText,
        ),
      ),
    );
  }
}
