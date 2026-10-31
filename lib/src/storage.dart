import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'model.dart';

/// Filesystem layout.
///
/// Everything lives in `%LOCALAPPDATA%\Retixel`:
///
/// ```
/// profiles.json   saved crosshairs
/// state.json      last session (spec, overlay, language, active profile)
/// overlay.ini     runtime contract read by the native overlay
/// crosshair.bin   raw sprite (CXSP header + straight RGBA)
/// overlay.log     diagnostics written by the native overlay
/// exports\        PNG exports
/// ```
class Storage {
  Storage.at(this.dir);

  final Directory dir;

  static Future<Storage> open({Directory? override}) async {
    final String? localAppData = Platform.environment['LOCALAPPDATA'];
    final Directory base = override ??
        Directory(_join(
          localAppData ?? Platform.environment['APPDATA'] ?? Directory.current.path,
          'Retixel',
        ));
    await base.create(recursive: true);
    await Directory(_join(base.path, 'exports')).create(recursive: true);
    return Storage.at(base);
  }

  static String _join(String parent, String child) {
    if (parent.endsWith('\\') || parent.endsWith('/')) return '$parent$child';
    return '$parent${Platform.pathSeparator}$child';
  }

  String path(String name) => _join(dir.path, name);

  File get profilesFile => File(path('profiles.json'));
  File get stateFile => File(path('state.json'));
  File get configFile => File(path('overlay.ini'));
  File get spriteFile => File(path('crosshair.bin'));
  File get logFile => File(path('overlay.log'));
  Directory get exportsDir => Directory(path('exports'));

  /// Absolute path of the native renderer, or null when the build did not
  /// produce it. Checked next to the running executable and one level up,
  /// which covers both `flutter run` and a release bundle.
  String? overlayExecutable() {
    final File running = File(Platform.resolvedExecutable);
    final Directory exeDir = running.parent;
    final List<String> candidates = <String>[
      _join(exeDir.path, 'retixel_overlay.exe'),
      _join(exeDir.parent.path, 'retixel_overlay.exe'),
      _join(dir.path, 'retixel_overlay.exe'),
    ];
    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<void> _writeAtomic(File target, List<int> bytes) async {
    final File temp = File('${target.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    try {
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);
    } on FileSystemException {
      // Antivirus or another process holding the handle: fall back to an
      // in-place write rather than losing the update.
      await target.writeAsBytes(bytes, flush: true);
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  Future<List<Profile>> loadProfiles() async {
    final List<Profile> profiles = <Profile>[];
    if (!await profilesFile.exists()) return profiles;
    try {
      final Object? json = jsonDecode(await profilesFile.readAsString());
      if (json is! Map<String, dynamic>) return profiles;
      final Object? list = json['profiles'];
      if (list is! List) return profiles;
      for (final Object? item in list) {
        if (item is Map<String, dynamic>) profiles.add(Profile.fromJson(item));
      }
    } catch (_) {
      await _quarantine(profilesFile);
      return <Profile>[];
    }
    profiles.sort((Profile a, Profile b) => b.updatedAt.compareTo(a.updatedAt));
    return profiles;
  }

  Future<void> saveProfiles(List<Profile> profiles) async {
    final String text = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'profiles': profiles.map((Profile p) => p.toJson()).toList(),
    });
    await _writeAtomic(profilesFile, utf8.encode(text));
  }

  Future<AppState> loadState() async {
    if (!await stateFile.exists()) return const AppState();
    try {
      final Object? json = jsonDecode(await stateFile.readAsString());
      if (json is! Map<String, dynamic>) return const AppState();
      return AppState.fromJson(json);
    } catch (_) {
      await _quarantine(stateFile);
      return const AppState();
    }
  }

  Future<void> saveState(AppState state) async {
    final String text = const JsonEncoder.withIndent('  ').convert(state.toJson());
    await _writeAtomic(stateFile, utf8.encode(text));
  }

  /// Writes the sprite first and the ini second so the overlay never sees a
  /// config that points at a half-written sprite.
  Future<void> writeRuntime({
    required CrosshairSpec spec,
    required OverlaySettings settings,
    required int parentPid,
    required Uint8List sprite,
  }) async {
    await _writeAtomic(spriteFile, sprite);
    final String ini = <String>[
      '# Retixel — runtime generado por el panel. No editar a mano.',
      'monitor=${settings.monitor}',
      'offset_x=${settings.offsetX}',
      'offset_y=${settings.offsetY}',
      'opacity=1.0',
      'hotkey=${settings.hotkey}',
      'hide_on_ads=${settings.hideOnAds ? 1 : 0}',
      'parent_pid=$parentPid',
      'sprite=crosshair.bin',
      '',
    ].join('\r\n');
    await _writeAtomic(configFile, utf8.encode(ini));
  }

  /// Last lines of the native log, used by the diagnostics dialog.
  Future<String> readLogTail({int maxLines = 16}) async {
    if (!await logFile.exists()) return '';
    try {
      final String text = await logFile.readAsString();
      final List<String> lines = text
          .split(RegExp(r'\r?\n'))
          .where((String line) => line.trim().isNotEmpty)
          .toList();
      if (lines.length <= maxLines) return lines.join('\n');
      return lines.sublist(lines.length - maxLines).join('\n');
    } catch (_) {
      return '';
    }
  }

  Future<void> clearLog() async {
    try {
      if (await logFile.exists()) await logFile.writeAsString('', flush: true);
    } catch (_) {
      // Diagnostics are best effort.
    }
  }

  Future<String> exportPng(Uint8List bytes, {String? fileName}) async {
    await exportsDir.create(recursive: true);
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final String safe = (fileName ?? 'crosshair-$stamp')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final String finalName = safe.toLowerCase().endsWith('.png') ? safe : '$safe.png';
    final File target = File(_join(exportsDir.path, finalName));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<void> _quarantine(File file) async {
    try {
      final String target =
          '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      await file.rename(target);
    } catch (_) {
      // If the file cannot be moved we simply ignore it this session.
    }
  }
}
