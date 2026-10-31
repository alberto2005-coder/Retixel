import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The Retixel mark, drawn as vector so it stays crisp at any size.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BrandMarkPainter()),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 1024;
    final Rect full = Offset.zero & size;
    final RRect tile = RRect.fromRectAndRadius(full, Radius.circular(216 * s));

    canvas.drawRRect(
      tile,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          <Color>[const Color(0xFF121820), const Color(0xFF07090D)],
        ),
    );
    canvas.drawRRect(
      tile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, 3 * s)
        ..color = const Color(0xFF263240),
    );

    final Offset center = size.center(Offset.zero);
    final double ring = 246 * s;

    canvas.drawCircle(
      center,
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 86 * s
        ..color = kPrimary.withValues(alpha: 0.12),
    );
    canvas.drawCircle(
      center,
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 44 * s
        ..shader = ui.Gradient.linear(
          Offset(center.dx - ring, center.dy - ring),
          Offset(center.dx + ring, center.dy + ring),
          <Color>[kPrimary, const Color(0xFF2A9FB0)],
        ),
    );
    canvas.drawCircle(
      center,
      150 * s,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10 * s
        ..color = kPrimary.withValues(alpha: 0.35),
    );

    final Paint tick = Paint()
      ..color = kPrimary
      ..strokeWidth = 42 * s
      ..strokeCap = StrokeCap.round;
    final double inner = 322 * s;
    final double outer = 404 * s;
    canvas.drawLine(center.translate(0, -inner), center.translate(0, -outer), tick);
    canvas.drawLine(center.translate(inner, 0), center.translate(outer, 0), tick);
    canvas.drawLine(center.translate(0, inner), center.translate(0, outer), tick);
    canvas.drawLine(center.translate(-inner, 0), center.translate(-outer, 0), tick);

    canvas.drawCircle(center, 52 * s, Paint()..color = kAccent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small lockup used in the header and the about dialog.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.markSize = 34, this.showTagline = false});

  final double markSize;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BrandMark(size: markSize),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'retixel',
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                height: 1,
                color: kText,
              ),
            ),
            if (showTagline) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'overlay de mira',
                style: text.bodySmall?.copyWith(fontSize: 11, height: 1),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
