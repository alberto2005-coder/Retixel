import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model.dart';

/// Padding (per side) reserved around the crosshair so outline and blur are
/// never clipped by the sprite bounds.
double spritePadding(CrosshairSpec spec) {
  final double outline = spec.outline ? spec.outlineWidth : 0;
  return 4 + outline + spec.blur * 3;
}

/// Side length of the square sprite that holds [spec] at its natural size.
int spriteSide(CrosshairSpec spec) {
  final double side = spec.size + spritePadding(spec) * 2;
  return side.ceil().clamp(8, 1024);
}

Color _outlineColor(Color base) {
  // Black outline on bright crosshairs, white on dark ones.
  return base.computeLuminance() > 0.42
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
}

Paint _strokePaint(double width, Color color, double blur) {
  final Paint paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..color = color;
  if (blur > 0) {
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
  }
  return paint;
}

Path _shapePath(CrosshairSpec spec, double radius, double thickness, double gap) {
  final Path path = Path();
  switch (spec.shape) {
    case CrosshairShape.cross:
    case CrosshairShape.x:
      final int arms = spec.arms;
      final double start = -math.pi / 2 +
          (spec.shape == CrosshairShape.x ? math.pi / 4 : 0);
      for (int i = 0; i < arms; i++) {
        final double angle = start + i * 2 * math.pi / arms;
        final double inner = gap + thickness / 2;
        final double outer = radius;
        if (outer <= inner) continue;
        path.moveTo(math.cos(angle) * inner, math.sin(angle) * inner);
        path.lineTo(math.cos(angle) * outer, math.sin(angle) * outer);
      }
    case CrosshairShape.tee:
      final double top = -radius + thickness / 2;
      path.moveTo(-radius, top);
      path.lineTo(radius, top);
      path.moveTo(0, gap + thickness / 2);
      path.lineTo(0, radius);
    case CrosshairShape.triangle:
      final double half = radius * 0.92;
      path.moveTo(0, -radius);
      path.lineTo(half, radius * 0.7);
      path.lineTo(-half, radius * 0.7);
      path.close();
    case CrosshairShape.chevron:
      path.moveTo(-radius * 0.9, radius * 0.45);
      path.lineTo(0, -radius * 0.55);
      path.lineTo(radius * 0.9, radius * 0.45);
    case CrosshairShape.square:
      path.addRect(Rect.fromCenter(
        center: Offset.zero,
        width: radius * 1.5,
        height: radius * 1.5,
      ));
    case CrosshairShape.circle:
      path.addOval(Rect.fromCircle(
        center: Offset.zero,
        radius: math.max(1, radius - thickness / 2),
      ));
    case CrosshairShape.dot:
    case CrosshairShape.image:
      break;
  }
  return path;
}

/// Draws [raw] centred inside [box].
///
/// [scale] multiplies every length, which lets the preview zoom without
/// changing the model. The sprite renderer always uses scale 1 so what the
/// user sizes is what lands on screen.
void paintCrosshair(
  Canvas canvas,
  Size box,
  CrosshairSpec raw, {
  ui.Image? image,
  double scale = 1,
}) {
  final CrosshairSpec spec = raw.sanitized();
  final double size = spec.size * scale;
  final double thickness = math.max(1, spec.thickness * scale);
  final double gap = spec.gap * scale;
  final double radius = size / 2;
  final double blur = spec.blur * scale;
  final Color base = spec.uiColor;
  final Color color = base.withValues(alpha: base.a * spec.opacity);

  canvas.save();
  canvas.translate(box.width / 2, box.height / 2);
  canvas.rotate(spec.rotation * math.pi / 180);

  final Color contrast = _outlineColor(color);
  final bool hasOutline = spec.outline && spec.outlineWidth > 0;
  final double outlineWidth = spec.outlineWidth * scale;

  if (spec.shape == CrosshairShape.image && image != null) {
    final double side = math.min(size, box.shortestSide);
    final Rect dst = Rect.fromCenter(
      center: Offset.zero,
      width: side,
      height: side,
    );
    // A layer is the reliable way to apply one global alpha to a bitmap:
    // Paint.color is ignored by drawImage and a color filter would tint it.
    canvas.saveLayer(
      dst.inflate(blur * 3 + 2),
      Paint()
        ..color = Color.fromARGB(
          (255 * spec.opacity.clamp(0, 1)).round(),
          255,
          255,
          255,
        ),
    );
    final Paint paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      paint,
    );
    canvas.restore();
    canvas.restore();
    return;
  }

  if (spec.shape == CrosshairShape.dot) {
    final double dotRadius =
        math.max(thickness / 2, math.min(radius, spec.dotSize * scale / 2));
    if (hasOutline) {
      canvas.drawCircle(
        Offset.zero,
        dotRadius + outlineWidth,
        Paint()
          ..isAntiAlias = true
          ..color = contrast.withValues(alpha: 0.7 * spec.opacity)
          ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null,
      );
    }
    canvas.drawCircle(
      Offset.zero,
      dotRadius,
      Paint()
        ..isAntiAlias = true
        ..color = color
        ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null,
    );
  } else {
    final Path path = _shapePath(spec, radius, thickness, gap);
    if (hasOutline) {
      canvas.drawPath(
        path,
        _strokePaint(
          thickness + outlineWidth * 2,
          contrast.withValues(alpha: 0.7 * spec.opacity),
          blur,
        ),
      );
    }
    canvas.drawPath(path, _strokePaint(thickness, color, blur));
  }

  if (spec.dot && spec.shape != CrosshairShape.dot) {
    final double dotRadius = math.max(1.0, spec.dotSize * scale / 2);
    if (hasOutline) {
      canvas.drawCircle(
        Offset.zero,
        dotRadius + outlineWidth,
        Paint()
          ..isAntiAlias = true
          ..color = contrast.withValues(alpha: 0.7 * spec.opacity)
          ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null,
      );
    }
    canvas.drawCircle(
      Offset.zero,
      dotRadius,
      Paint()
        ..isAntiAlias = true
        ..color = color
        ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null,
    );
  }

  canvas.restore();
}

/// Live preview painter. [zoom] is a pure visual multiplier.
class CrosshairPreviewPainter extends CustomPainter {
  const CrosshairPreviewPainter({
    required this.spec,
    required this.image,
    required this.zoom,
  });

  final CrosshairSpec spec;
  final ui.Image? image;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    paintCrosshair(canvas, size, spec, image: image, scale: zoom);
  }

  @override
  bool shouldRepaint(CrosshairPreviewPainter oldDelegate) {
    return oldDelegate.spec != spec ||
        oldDelegate.image != image ||
        oldDelegate.zoom != zoom;
  }
}
