import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model.dart';
import 'painter.dart';

/// Renders the crosshair at its natural size into a square image.
///
/// The image is used both for on-screen export and as the source of the raw
/// sprite handed to the native overlay.
Future<ui.Image> renderCrosshairImage(
  CrosshairSpec spec, {
  ui.Image? image,
  int? side,
  double scale = 1,
}) async {
  final CrosshairSpec clean = spec.sanitized();
  final int pixels = (side ?? spriteSide(clean)).clamp(8, 1024);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  paintCrosshair(
    canvas,
    Size(pixels.toDouble(), pixels.toDouble()),
    clean,
    image: image,
    scale: scale,
  );
  final ui.Picture picture = recorder.endRecording();
  try {
    return await picture.toImage(pixels, pixels);
  } finally {
    picture.dispose();
  }
}

/// Binary contract consumed by `retixel_overlay.exe`:
///
/// ```
/// offset 0  : 'C' 'X' 'S' 'P'
/// offset 4  : uint32 LE width
/// offset 8  : uint32 LE height
/// offset 12 : width * height * 4 bytes of straight (non-premultiplied) RGBA
/// ```
Future<Uint8List> buildSpriteBytes(
  CrosshairSpec spec, {
  ui.Image? image,
}) async {
  final ui.Image rendered = await renderCrosshairImage(spec, image: image);
  try {
    final ByteData? raw =
        await rendered.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (raw == null) {
      throw StateError('No se pudo leer el sprite renderizado.');
    }
    final int width = rendered.width;
    final int height = rendered.height;
    final Uint8List header = Uint8List(12);
    header.setRange(0, 4, 'CXSP'.codeUnits);
    final ByteData headerView = ByteData.view(header.buffer);
    headerView.setUint32(4, width, Endian.little);
    headerView.setUint32(8, height, Endian.little);

    final Uint8List pixels =
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(header)
      ..add(pixels);
    return builder.toBytes();
  } finally {
    rendered.dispose();
  }
}

/// PNG snapshot of the crosshair, for the export button.
Future<Uint8List> buildPngBytes(
  CrosshairSpec spec, {
  ui.Image? image,
  int? side,
  double scale = 1,
}) async {
  final ui.Image rendered =
      await renderCrosshairImage(spec, image: image, side: side, scale: scale);
  try {
    final ByteData? png =
        await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('No se pudo codificar el PNG.');
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    rendered.dispose();
  }
}
