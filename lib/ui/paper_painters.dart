import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/notebook.dart';
import 'theme.dart';

/// Draws a sheet of notebook paper: cream stock, ruled or grid lines,
/// a red margin and a soft darkening toward the edges.
class PaperPainter extends CustomPainter {
  PaperPainter({required this.style, required this.bindingOnLeft, this.headerHeight = 72})
    : sheet = Paper.sheet,
      aged = !Paper.plain;

  final PaperStyle style;
  final Color sheet;

  /// Old paper look, with darker edges and a shadow by the coil.
  final bool aged;

  /// Which side the spiral is on, so the margin and shading sit next to it.
  final bool bindingOnLeft;
  final double headerHeight;

  static const lineSpacing = 28.0;
  static const gridSpacing = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = sheet);

    // Plain paper is clean: no lines or squares at all.
    switch (aged ? style : PaperStyle.blank) {
      case PaperStyle.ruled:
        final line = Paint()
          ..color = Paper.ruleLine
          ..strokeWidth = 1;
        for (var y = headerHeight; y < size.height - 8; y += lineSpacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        final marginX = bindingOnLeft ? 44.0 : 36.0;
        canvas.drawLine(
          Offset(marginX, 0),
          Offset(marginX, size.height),
          Paint()
            ..color = Paper.margin
            ..strokeWidth = 1.2,
        );
      case PaperStyle.grid:
        final grid = Paint()
          ..color = Paper.gridLine
          ..strokeWidth = 0.8;
        for (var y = gridSpacing; y < size.height; y += gridSpacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
        }
        for (var x = gridSpacing; x < size.width; x += gridSpacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
        }
      case PaperStyle.blank:
        break;
    }

    if (!aged) return;

    // Age the paper a little toward its outer edges.
    final vignette = RadialGradient(
      center: Alignment(bindingOnLeft ? -0.3 : 0.3, -0.2),
      radius: 1.25,
      colors: const [Color(0x00000000), Color(0x00000000), Color(0x22A07840)],
      stops: const [0, 0.65, 1],
    );
    canvas.drawRect(rect, Paint()..shader = vignette.createShader(rect));

    // A shadow in the gutter where the page curves into the binding.
    final gutter = LinearGradient(
      begin: bindingOnLeft ? Alignment.centerLeft : Alignment.centerRight,
      end: bindingOnLeft ? Alignment.centerRight : Alignment.centerLeft,
      colors: const [Color(0x30000000), Color(0x00000000)],
    );
    final gutterRect = bindingOnLeft
        ? Rect.fromLTWH(0, 0, 26, size.height)
        : Rect.fromLTWH(size.width - 26, 0, 26, size.height);
    canvas.drawRect(gutterRect, Paint()..shader = gutter.createShader(gutterRect));
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.style != style ||
      old.bindingOnLeft != bindingOnLeft ||
      old.headerHeight != headerHeight ||
      old.sheet != sheet ||
      old.aged != aged;
}

/// The metal coil binding, drawn either vertically between two pages
/// or down the left edge of a single page.
class SpiralPainter extends CustomPainter {
  const SpiralPainter({this.ringSpacing = 22});

  final double ringSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = Paint()..color = const Color(0xFF3B3026);
    final cx = size.width / 2;
    final ringW = size.width * 0.9;
    final metal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xCCFFFFFF)
      ..strokeCap = StrokeCap.round;

    for (var y = ringSpacing / 2 + 6; y < size.height - 6; y += ringSpacing) {
      final leftHole = Offset(cx - ringW / 2 + 3, y + 4);
      final rightHole = Offset(cx + ringW / 2 - 3, y + 4);
      canvas.drawCircle(leftHole, 3.2, hole);
      canvas.drawCircle(rightHole, 3.2, hole);

      final ring = Rect.fromCenter(center: Offset(cx, y), width: ringW, height: 11);
      metal.shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEDEDED), Color(0xFF8E8E8E), Color(0xFF4A4A4A)],
      ).createShader(ring);
      canvas.drawArc(ring, math.pi, math.pi, false, metal);
      canvas.drawArc(ring.deflate(1.5), math.pi * 1.25, math.pi * 0.45, false, shine);
    }
  }

  @override
  bool shouldRepaint(SpiralPainter old) => old.ringSpacing != ringSpacing;
}

/// A slightly wobbly underline, like one drawn with a pen.
class PenUnderlinePainter extends CustomPainter {
  const PenUnderlinePainter({this.color = Pen.red});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final path = Path()..moveTo(0, y + 1);
    path.cubicTo(size.width * 0.3, y - 2, size.width * 0.6, y + 2.5, size.width, y - 1);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(PenUnderlinePainter old) => old.color != color;
}

/// A hand-drawn checkbox with a red tick.
class CheckboxPainter extends CustomPainter {
  const CheckboxPainter({required this.checked});
  final bool checked;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTWH(1, 2, size.width - 3, size.height - 3);
    final path = Path()
      ..moveTo(box.left, box.top + 0.5)
      ..lineTo(box.right - 0.5, box.top)
      ..lineTo(box.right, box.bottom - 0.5)
      ..lineTo(box.left + 0.5, box.bottom)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Pen.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    if (checked) {
      final tick = Path()
        ..moveTo(box.left + 3, box.center.dy)
        ..quadraticBezierTo(box.left + 6, box.bottom - 4, box.left + 7, box.bottom - 2)
        ..quadraticBezierTo(box.center.dx + 3, box.top, box.right + 3, box.top - 3);
      canvas.drawPath(
        tick,
        Paint()
          ..color = Pen.red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(CheckboxPainter old) => old.checked != checked;
}
