import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/model.dart';
import 'src/panel.dart';
import 'src/storage.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final Storage storage = await Storage.open();
  final AppState state = await storage.loadState();
  final List<Profile> profiles = await storage.loadProfiles();

  // Size is set once in windows/runner/main.cpp. Setting it again here would
  // double-apply the DPI scale and clip the layout on scaled displays.
  const WindowOptions options = WindowOptions(
    center: true,
    backgroundColor: kBackground,
    title: 'Retixel',
    minimumSize: Size(1100, 720),
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setTitle('Retixel');
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(RetixelApp(
    storage: storage,
    initialState: state,
    initialProfiles: profiles,
  ));
}

class RetixelApp extends StatelessWidget {
  const RetixelApp({
    super.key,
    required this.storage,
    required this.initialState,
    required this.initialProfiles,
    this.enableWindowHooks = true,
  });

  final Storage storage;
  final AppState initialState;
  final List<Profile> initialProfiles;
  final bool enableWindowHooks;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Retixel',
      debugShowCheckedModeBanner: false,
      theme: buildRetixelTheme(),
      home: PanelPage(
        storage: storage,
        initialState: initialState,
        initialProfiles: initialProfiles,
        enableWindowHooks: enableWindowHooks,
      ),
    );
  }
}
