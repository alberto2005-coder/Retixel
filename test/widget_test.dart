import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retixel/main.dart';
import 'package:retixel/src/model.dart';
import 'package:retixel/src/painter.dart';
import 'package:retixel/src/storage.dart';

/// The panel keeps two text fields focused, so the caret blink schedules frames
/// forever and `pumpAndSettle` never returns. Pump fixed slices instead.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

CrosshairSpec _previewSpec(WidgetTester tester) {
  final Iterable<CustomPaint> paints = tester.widgetList<CustomPaint>(
    find.byWidgetPredicate(
      (Widget widget) =>
          widget is CustomPaint && widget.painter is CrosshairPreviewPainter,
    ),
  );
  final CrosshairPreviewPainter painter =
      paints.first.painter! as CrosshairPreviewPainter;
  return painter.spec;
}

void main() {
  testWidgets('panel shows the designer, preview and overlay controls',
      (WidgetTester tester) async {
    final Directory dir =
        await Directory.systemTemp.createTemp('retixel-widget');
    addTearDown(() => dir.deleteSync(recursive: true));
    final Storage storage = await Storage.open(override: dir);

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(RetixelApp(
      storage: storage,
      initialState: const AppState(),
      initialProfiles: const <Profile>[],
      enableWindowHooks: false,
    ));
    await _settle(tester);

    expect(find.text('retixel'), findsOneWidget);
    expect(find.text('Activar overlay'), findsOneWidget);
    expect(find.text('Vista previa'.toUpperCase()), findsOneWidget);
    expect(find.text('Perfiles'.toUpperCase()), findsOneWidget);
    expect(find.text('Todavía no hay perfiles.'), findsOneWidget);

    // Changing the shape updates the live preview immediately.
    expect(_previewSpec(tester).shape, CrosshairShape.dot);
    await tester.tap(find.text('Cruz'));
    await _settle(tester);
    expect(_previewSpec(tester).shape, CrosshairShape.cross);
    expect(tester.takeException(), isNull);
  });
}
