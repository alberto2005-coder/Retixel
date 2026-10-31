import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model.dart';
import 'storage.dart';

/// One physical display as reported by the native overlay.
class MonitorInfo {
  const MonitorInfo({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.primary,
  });

  final int index;
  final int left;
  final int top;
  final int width;
  final int height;
  final bool primary;

  String get resolution => '$width×$height';

  static MonitorInfo? parse(String line) {
    final List<String> parts = line.split(';');
    if (parts.length < 6) return null;
    final int? index = int.tryParse(parts[0].trim());
    final int? left = int.tryParse(parts[1].trim());
    final int? top = int.tryParse(parts[2].trim());
    final int? width = int.tryParse(parts[3].trim());
    final int? height = int.tryParse(parts[4].trim());
    if (index == null || left == null || top == null || width == null ||
        height == null || width <= 0 || height <= 0) {
      return null;
    }
    return MonitorInfo(
      index: index,
      left: left,
      top: top,
      width: width,
      height: height,
      primary: parts[5].trim() == '1',
    );
  }

  static List<MonitorInfo> parseAll(String text) {
    final List<MonitorInfo> result = <MonitorInfo>[];
    for (final String line in text.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      final MonitorInfo? monitor = parse(line);
      if (monitor != null) result.add(monitor);
    }
    return result;
  }
}

class OverlayException implements Exception {
  const OverlayException(this.kind);
  final String kind;
  @override
  String toString() => 'OverlayException($kind)';
}

/// Owns the lifecycle of the native renderer and the runtime files it reads.
///
/// The service never talks to the overlay over a socket: the contract is two
/// files in [Storage] (`overlay.ini` and `crosshair.bin`). That keeps the
/// renderer replaceable and makes crashes obvious (the process exits, the
/// window disappears, the panel stays usable).
class OverlayService extends ChangeNotifier {
  OverlayService(this.storage);

  final Storage storage;

  Process? _process;
  bool _starting = false;
  String? _error;
  List<MonitorInfo> _monitors = const <MonitorInfo>[];
  String _log = '';

  bool get running => _process != null;
  bool get starting => _starting;
  String? get error => _error;
  List<MonitorInfo> get monitors => _monitors;
  String get log => _log;
  bool get executableAvailable => storage.overlayExecutable() != null;

  /// Reads the display list. Safe to call at any time; the overlay does not
  /// need to be running.
  Future<List<MonitorInfo>> readMonitors() async {
    final String? exe = storage.overlayExecutable();
    if (exe == null) throw const OverlayException('missingExe');
    final File out = File('${storage.dir.path}\\monitors.txt');
    try {
      final ProcessResult result = await Process.run(
        exe,
        <String>['--list-monitors', out.path],
      ).timeout(const Duration(seconds: 6));
      if (result.exitCode != 0 || !await out.exists()) {
        throw const OverlayException('monitors');
      }
      final List<MonitorInfo> parsed = MonitorInfo.parseAll(await out.readAsString());
      if (parsed.isEmpty) throw const OverlayException('monitors');
      return parsed;
    } on OverlayException {
      rethrow;
    } catch (_) {
      throw const OverlayException('monitors');
    } finally {
      try {
        if (await out.exists()) await out.delete();
      } catch (_) {
        // A leftover temp file is harmless.
      }
    }
  }

  Future<void> refreshMonitors() async {
    try {
      _monitors = await readMonitors();
      _error = null;
    } on OverlayException catch (e) {
      _error = e.kind;
    } catch (_) {
      _error = 'monitors';
    }
    notifyListeners();
  }

  Future<void> refreshLog() async {
    _log = await storage.readLogTail();
    notifyListeners();
  }

  Future<bool> start({
    required CrosshairSpec spec,
    required OverlaySettings settings,
    required Uint8List sprite,
    required int parentPid,
  }) async {
    if (_process != null) {
      return update(
        spec: spec,
        settings: settings,
        sprite: sprite,
        parentPid: parentPid,
      );
    }
    _starting = true;
    _error = null;
    notifyListeners();

    final String? exe = storage.overlayExecutable();
    if (exe == null) {
      _starting = false;
      _error = 'missingExe';
      notifyListeners();
      return false;
    }

    try {
      await storage.writeRuntime(
        spec: spec,
        settings: settings,
        parentPid: parentPid,
        sprite: sprite,
      );
      await storage.clearLog();
      final Process process = await Process.start(
        exe,
        <String>['--config', storage.configFile.path],
        workingDirectory: storage.dir.path,
      );
      _process = process;
      unawaited(process.exitCode.then((int code) async {
        if (!identical(_process, process)) return;
        _process = null;
        _starting = false;
        if (code != 0) _error = 'crashed';
        await refreshLog();
        notifyListeners();
      }));

      // Give the renderer time to create its window and register the hotkey.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_process == null) {
        _starting = false;
        await refreshLog();
        if (_log.contains('instancia duplicada')) _error = 'alreadyRunning';
        notifyListeners();
        return false;
      }
      await refreshLog();
      _starting = false;
      notifyListeners();
      return true;
    } catch (_) {
      _process = null;
      _starting = false;
      _error = 'startFailed';
      notifyListeners();
      return false;
    }
  }

  Future<bool> update({
    required CrosshairSpec spec,
    required OverlaySettings settings,
    required Uint8List sprite,
    required int parentPid,
  }) async {
    if (_process == null) return false;
    try {
      await storage.writeRuntime(
        spec: spec,
        settings: settings,
        parentPid: parentPid,
        sprite: sprite,
      );
      return true;
    } catch (_) {
      _error = 'startFailed';
      notifyListeners();
      return false;
    }
  }

  Future<void> stop() async {
    final Process? process = _process;
    _process = null;
    _starting = false;
    if (process != null) {
      process.kill();
    }
    notifyListeners();
  }

  String describeError(String Function(String) translate) {
    final String? kind = _error;
    if (kind == null) return '';
    final String key = 'error.$kind';
    final String text = translate(key);
    return text == key ? translate('error.unknown') : text;
  }

  @override
  void dispose() {
    _process?.kill();
    _process = null;
    super.dispose();
  }
}
