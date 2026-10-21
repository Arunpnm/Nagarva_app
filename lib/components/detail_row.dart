import 'package:flutter/material.dart';

import '/flutter_flow/ng_tokens.dart';

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

  /// True when this row renders nothing, so [DetailCard] can leave out
  /// the divider that would otherwise sit above it.
  bool get isHidden => _isEmpty && hideWhenEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isEmpty && hideWhenEmpty) return const SizedBox.shrink();
    final c = NgPalette.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 13.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              maxLines: 2,
              style: NgFonts.geist(
                fontSize: 14,
                height: 1.3,
                color: c.mute,
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
              style: NgFonts.geist(
                fontSize: 14.5,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: _isEmpty ? c.mute : (valueColor ?? c.text),
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

/// A titled group of [DetailRow]s (Claude Design handoff "Move
/// details"): the heading sits above the card, and rows are split by
/// hairlines. Rows that hide themselves take their divider with them.
class DetailCard extends StatelessWidget {
  const DetailCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final visible = [
      for (final w in children)
        if (!(w is DetailRow && w.isHidden)) w,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Text(
              title,
              style: NgFonts.geist(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: c.text,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(NgRadius.card),
              border: Border.all(color: c.w06),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: c.w06),
                  visible[i],
                ],
              ],
            ),
          ),
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
    final c = NgPalette.of(context);
    final empty = text == null || text!.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Text(
        empty ? emptyLabel : text!.trim(),
        style: NgFonts.geist(
          fontSize: 14.5,
          height: 1.4,
          fontStyle: empty ? FontStyle.italic : FontStyle.normal,
          color: empty ? c.mute : c.text,
        ),
      ),
    );
  }
}
