import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Finger/stylus signature pad (live-test fix brief #2, item 3).
///
/// Deliberately hand-rolled on `CustomPaint` rather than pulling in the
/// `signature` pub package: the Flutter SDK here is pinned at 3.35.5 and
/// pubspec pins exact versions FlutterFlow-style (see CLAUDE.md's
/// environment rules — a casual dependency add is how the
/// font_awesome_flutter / page_transition `IconData` breakage happens).
/// A signature pad is a few dozen lines of gesture + path painting, so
/// the dependency isn't worth the version risk.
///
/// [toPngBase64] rasterises the strokes to a PNG and returns it base64
/// encoded, matching `document_signatures.signature_data`'s format.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    this.height = 200,
    this.strokeWidth = 2.5,
    this.penColor = const Color(0xFF0F172A),
    this.backgroundColor = Colors.white,
    this.onChanged,
  });

  final double height;
  final double strokeWidth;
  final Color penColor;
  final Color backgroundColor;

  /// Fires with `true` once at least one stroke exists, `false` when
  /// cleared — lets the parent enable/disable its submit button.
  final ValueChanged<bool>? onChanged;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  /// Each entry is one continuous stroke (pen down → pen up). Storing
  /// strokes separately rather than one flat point list is what stops
  /// separate strokes being joined by a stray connecting line.
  final List<List<Offset>> _strokes = [];
  final GlobalKey _boundaryKey = GlobalKey();
  Size _size = Size.zero;

  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void clear() {
    setState(_strokes.clear);
    widget.onChanged?.call(false);
  }

  void _start(Offset p) {
    _strokes.add([p]);
    setState(() {});
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) return;
    // Clamp inside the pad so a drag that leaves the box doesn't paint
    // outside the captured bounds.
    final clamped = Offset(
      p.dx.clamp(0.0, _size.width == 0 ? p.dx : _size.width),
      p.dy.clamp(0.0, _size.height == 0 ? p.dy : _size.height),
    );
    setState(() => _strokes.last.add(clamped));
  }

  void _end() {
    if (!isEmpty) widget.onChanged?.call(true);
  }

  /// Rasterises the pad to a base64 PNG. Returns null if nothing was
  /// drawn, so callers can treat "empty" and "failed" the same way.
  Future<String?> toPngBase64() async {
    if (isEmpty) return null;
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // 2x for a crisp signature in the PDF without a huge payload.
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    return base64Encode(bytes.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: Container(
        height: widget.height,
        width: double.infinity,
        color: widget.backgroundColor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              // onPanX gives us local coordinates already relative to
              // this box, so no global-to-local conversion is needed.
              onPanStart: (d) => _start(d.localPosition),
              onPanUpdate: (d) => _extend(d.localPosition),
              onPanEnd: (_) => _end(),
              child: CustomPaint(
                size: Size.infinite,
                painter: _SignaturePainter(
                  strokes: _strokes,
                  color: widget.penColor,
                  strokeWidth: widget.strokeWidth,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({
    required this.strokes,
    required this.color,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) {
        // A tap with no drag still deserves a dot.
        if (stroke.length == 1) {
          canvas.drawCircle(
            stroke.first,
            strokeWidth / 2,
            Paint()..color = color,
          );
        }
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
