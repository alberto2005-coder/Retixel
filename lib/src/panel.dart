import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'brand.dart';
import 'i18n.dart';
import 'model.dart';
import 'overlay_service.dart';
import 'painter.dart';
import 'sprite.dart';
import 'storage.dart';
import 'theme.dart';

const String kAppVersion = '1.0.0';

const List<int> _presetColors = <int>[
  0xFF4ADEDE,
  0xFFFFFFFF,
  0xFFFF4D4D,
  0xFF6CFF6C,
  0xFFFFB454,
  0xFFFF6BD5,
  0xFF9B7BFF,
  0xFFB8C0CC,
];

class PanelPage extends StatefulWidget {
  const PanelPage({
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
  State<PanelPage> createState() => _PanelPageState();
}

class _PanelPageState extends State<PanelPage> with WindowListener {
  late CrosshairSpec _spec;
  late OverlaySettings _overlay;
  late List<Profile> _profiles;
  late String? _activeProfileId;
  late String _language;

  late final OverlayService _service;
  late final TextEditingController _hexController;
  late final TextEditingController _hotkeyController;
  final FocusNode _hexFocus = FocusNode();
  final FocusNode _hotkeyFocus = FocusNode();

  List<MonitorInfo> _monitors = const <MonitorInfo>[];
  ui.Image? _customImage;
  Timer? _persistTimer;
  bool _busy = false;
  double _zoom = 4;
  String _previewBackground = 'dark';

  L10n get _t => L10n(_language);

  @override
  void initState() {
    super.initState();
    _spec = widget.initialState.spec.sanitized();
    _overlay = widget.initialState.overlay;
    _profiles = List<Profile>.of(widget.initialProfiles);
    _activeProfileId = widget.initialState.activeProfileId;
    _language = widget.initialState.language;

    _hexController = TextEditingController(text: _hexOf(_spec.color));
    _hotkeyController = TextEditingController(text: _overlay.hotkey);
    _service = OverlayService(widget.storage)..addListener(_onServiceChanged);

    if (widget.enableWindowHooks) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshMonitors();
        if (widget.initialState.overlayWasOn) {
          _toggleOverlay();
        }
      });
    }

    final String? imagePath = _spec.imagePath;
    if (imagePath != null) {
      unawaited(_loadImageFile(File(imagePath), notifyOnError: false));
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _service.removeListener(_onServiceChanged);
    if (widget.enableWindowHooks) windowManager.removeListener(this);
    _hexController.dispose();
    _hotkeyController.dispose();
    _hexFocus.dispose();
    _hotkeyFocus.dispose();
    _customImage?.dispose();
    _service.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void onWindowClose() {
    unawaited(_shutdown());
  }

  Future<void> _shutdown() async {
    await _service.stop();
    if (widget.enableWindowHooks) {
      await windowManager.destroy();
    }
  }

  // ------------------------------------------------------------- persistence

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 350), _persistNow);
  }

  Future<void> _persistNow() async {
    await widget.storage.saveState(AppState(
      spec: _spec,
      overlay: _overlay,
      activeProfileId: _activeProfileId,
      language: _language,
      overlayWasOn: _service.running,
    ));
    if (_service.running) await _pushRuntime();
  }

  Future<void> _pushRuntime() async {
    try {
      final Uint8List bytes = await buildSpriteBytes(_spec, image: _customImage);
      await _service.update(
        spec: _spec,
        settings: _overlay,
        sprite: bytes,
        parentPid: pid,
      );
    } catch (_) {
      // The panel stays usable; the overlay keeps its last good sprite.
    }
  }

  void _setSpec(CrosshairSpec next) {
    setState(() => _spec = next.sanitized());
    if (!_hexFocus.hasFocus) {
      _hexController.text = _hexOf(_spec.color);
    }
    _schedulePersist();
  }

  void _setOverlay(OverlaySettings next, {bool syncHotkey = true}) {
    setState(() => _overlay = next);
    if (syncHotkey && !_hotkeyFocus.hasFocus) {
      _hotkeyController.text = next.hotkey;
    }
    _schedulePersist();
  }

  // ------------------------------------------------------------------ window

  Future<void> _toggleOverlay() async {
    if (_busy) return;
    if (_service.running) {
      await _service.stop();
      await _persistNow();
      if (mounted) _toast(_t.t('status.stopped'));
      return;
    }

    setState(() => _busy = true);
    try {
      final Uint8List sprite =
          await buildSpriteBytes(_spec, image: _customImage);
      final bool ok = await _service.start(
        spec: _spec,
        settings: _overlay,
        sprite: sprite,
        parentPid: pid,
      );
      if (!mounted) return;
      _toast(ok
          ? _t.t('status.running')
          : (_service.describeError(_t.t).isEmpty
              ? _t.t('error.startFailed')
              : _service.describeError(_t.t)));
      await _persistNow();
    } catch (_) {
      if (mounted) _toast(_t.t('error.startFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshMonitors() async {
    try {
      final List<MonitorInfo> list = await _service.readMonitors();
      if (!mounted) return;
      setState(() {
        _monitors = list;
        if (_overlay.monitor >= list.length) {
          _overlay = _overlay.copyWith(monitor: 0);
        }
      });
    } on OverlayException {
      if (mounted) _toast(_t.t('error.monitors'));
    } catch (_) {
      if (mounted) _toast(_t.t('error.monitors'));
    }
  }

  Future<void> _openLog() async {
    await _service.refreshLog();
    if (!mounted) return;
    final String text = _service.log;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(_t.t('log.title')),
        content: SizedBox(
          width: 560,
          child: SelectableText(
            text.isEmpty ? _t.t('log.empty') : text,
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontFamilyFallback: <String>['Courier New', 'monospace'],
              fontSize: 12,
              height: 1.5,
              color: kMuted,
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t.t('dialog.close')),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ image

  Future<ui.Image?> _decode(File file) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      ui.Codec codec = await ui.instantiateImageCodec(bytes);
      ui.FrameInfo frame = await codec.getNextFrame();
      if (frame.image.width > 512) {
        frame.image.dispose();
        codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
        frame = await codec.getNextFrame();
      }
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadImageFile(File file, {bool notifyOnError = true}) async {
    if (!await file.exists()) {
      if (notifyOnError && mounted) _toast(_t.t('error.image'));
      return;
    }
    final ui.Image? image = await _decode(file);
    if (!mounted) {
      image?.dispose();
      return;
    }
    if (image == null) {
      if (notifyOnError) _toast(_t.t('error.image'));
      return;
    }
    setState(() {
      _customImage?.dispose();
      _customImage = image;
      _spec = _spec.copyWith(shape: CrosshairShape.image, imagePath: file.path);
    });
  }

  Future<void> _pickImage() async {
    const XTypeGroup group = XTypeGroup(
      label: 'Imagen',
      extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (file == null || !mounted) return;
    final File local = File(file.path);
    try {
      if (await local.length() > 16 * 1024 * 1024) {
        _toast(_t.t('error.imageTooBig'));
        return;
      }
    } catch (_) {
      _toast(_t.t('error.image'));
      return;
    }
    await _loadImageFile(local);
    if (mounted) _schedulePersist();
  }

  void _removeImage() {
    setState(() {
      _customImage?.dispose();
      _customImage = null;
      _spec = _spec
          .copyWith(shape: CrosshairShape.cross, imagePath: null)
          .sanitized();
    });
    _schedulePersist();
  }

  // --------------------------------------------------------------- profiles

  Profile? get _activeProfile {
    for (final Profile profile in _profiles) {
      if (profile.id == _activeProfileId) return profile;
    }
    return null;
  }

  Future<void> _saveProfile() async {
    final String? name = await _askProfileName(_activeProfile?.name ?? '');
    if (name == null || !mounted) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int existing = _profiles.indexWhere(
      (Profile p) => p.name.toLowerCase() == name.toLowerCase(),
    );

    if (existing >= 0) {
      final bool overwrite = await _confirm(
        _t.t('profile.overwriteTitle'),
        _t.t('profile.overwriteBody', vars: <String, String>{'name': name}),
        confirmLabel: _t.t('profile.overwrite'),
      );
      if (!overwrite || !mounted) return;
      final Profile updated = _profiles[existing].copyWith(
        spec: _spec,
        overlay: _overlay,
        updatedAt: now,
      );
      setState(() {
        _profiles[existing] = updated;
        _activeProfileId = updated.id;
      });
    } else {
      final Profile profile = Profile(
        id: '$now',
        name: name,
        spec: _spec,
        overlay: _overlay,
        updatedAt: now,
      );
      setState(() {
        _profiles.insert(0, profile);
        _activeProfileId = profile.id;
      });
    }

    await widget.storage.saveProfiles(_profiles);
    await _persistNow();
    if (mounted) _toast(_t.t('profile.saved'));
  }

  Future<void> _loadProfile(Profile profile) async {
    setState(() {
      _spec = profile.spec.sanitized();
      _overlay = profile.overlay;
      _activeProfileId = profile.id;
      _hexController.text = _hexOf(_spec.color);
      _hotkeyController.text = _overlay.hotkey;
    });

    final String? path = _spec.imagePath;
    if (path != null) {
      await _loadImageFile(File(path), notifyOnError: false);
    } else {
      _customImage?.dispose();
      _customImage = null;
    }

    if (_service.running) await _pushRuntime();
    await _persistNow();
    if (mounted) _toast(_t.t('profile.loaded'));
  }

  Future<void> _deleteProfile(Profile profile) async {
    final bool confirmed = await _confirm(
      _t.t('profile.deleteTitle'),
      _t.t('profile.deleteBody', vars: <String, String>{'name': profile.name}),
      confirmLabel: _t.t('profile.delete'),
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _profiles.removeWhere((Profile p) => p.id == profile.id);
      if (_activeProfileId == profile.id) _activeProfileId = null;
    });
    await widget.storage.saveProfiles(_profiles);
    await _persistNow();
    if (mounted) _toast(_t.t('profile.deleted'));
  }

  // ---------------------------------------------------------- share / export

  Future<void> _copyShareCode() async {
    await Clipboard.setData(ClipboardData(text: _spec.encodeShare()));
    if (mounted) _toast(_t.t('share.copied'));
  }

  Future<void> _importShareCode() async {
    final TextEditingController controller = TextEditingController();
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(_t.t('share.importTitle')),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(hintText: _t.t('share.importHint')),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t.t('dialog.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(_t.t('share.import')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || !mounted) return;

    final CrosshairSpec? spec = CrosshairSpec.decodeShare(code);
    if (spec == null) {
      _toast(_t.t('share.invalid'));
      return;
    }

    setState(() {
      _spec = spec;
      _activeProfileId = null;
      _hexController.text = _hexOf(_spec.color);
    });
    final String? path = spec.imagePath;
    if (path != null) {
      await _loadImageFile(File(path), notifyOnError: false);
    }
    if (_service.running) await _pushRuntime();
    await _persistNow();
  }

  Future<void> _exportPng() async {
    const XTypeGroup group = XTypeGroup(label: 'PNG', extensions: <String>['png']);
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: 'retixel-${_spec.shape.name}-${_spec.size.round()}.png',
      acceptedTypeGroups: <XTypeGroup>[group],
      confirmButtonText: _t.t('share.export'),
    );
    if (location == null || !mounted) return;
    try {
      final int side = 512;
      final Uint8List bytes = await buildPngBytes(
        _spec,
        image: _customImage,
        side: side,
        scale: side / spriteSide(_spec),
      );
      await File(location.path).writeAsBytes(bytes, flush: true);
      if (mounted) {
        _toast(_t.t('share.exported', vars: <String, String>{'path': location.path}));
      }
    } catch (_) {
      if (mounted) _toast(_t.t('share.exportFailed'));
    }
  }

  // ---------------------------------------------------------------- dialogs

  Future<String?> _askProfileName(String initial) async {
    final TextEditingController controller =
        TextEditingController(text: initial);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(_t.t('profile.save')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(labelText: _t.t('profile.name')),
          onSubmitted: (String value) =>
              Navigator.of(context).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t.t('dialog.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(_t.t('dialog.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  Future<bool> _confirm(
    String title,
    String body, {
    String? confirmLabel,
    bool danger = false,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t.t('dialog.cancel')),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: kDanger,
                    foregroundColor: const Color(0xFF2A0505),
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel ?? _t.t('dialog.ok')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _openAbout() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Row(
          children: <Widget>[
            const BrandMark(size: 30),
            const SizedBox(width: 12),
            Text(_t.t('about.title')),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_t.t('about.version', vars: <String, String>{'version': kAppVersion})),
              const SizedBox(height: 14),
              Text(_t.t('about.body')),
              const SizedBox(height: 10),
              Text(_t.t('about.limits')),
              const SizedBox(height: 10),
              Text(_t.t('about.license')),
              const SizedBox(height: 10),
              Text(_t.t('about.legal')),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t.t('dialog.close')),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ helpers

  String _hexOf(int color) {
    final int rgb = color & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  int? _parseHex(String raw) {
    String text = raw.trim().replaceAll('#', '');
    if (text.length == 3) {
      text = text.split('').map((String c) => '$c$c').join();
    }
    if (text.length == 6) {
      final int? value = int.tryParse(text, radix: 16);
      return value == null ? null : 0xFF000000 | value;
    }
    if (text.length == 8) return int.tryParse(text, radix: 16);
    return null;
  }

  void _toast(String message) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _applyHotkey() {
    final String? normalized =
        OverlaySettings.normalizeHotkey(_hotkeyController.text);
    if (normalized == null) {
      _toast(_t.t('error.hotkey'));
      return;
    }
    _hotkeyController.text = normalized;
    _setOverlay(_overlay.copyWith(hotkey: normalized));
  }

  void _nudge(int dx, int dy) {
    _setOverlay(_overlay.copyWith(
      offsetX: (_overlay.offsetX + dx).clamp(-4000, 4000),
      offsetY: (_overlay.offsetY + dy).clamp(-4000, 4000),
    ));
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final L10n t = _t;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(t),
            if (_service.error != null) _errorBanner(t),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: 348, child: _designColumn(t)),
                    const SizedBox(width: kGap),
                    Expanded(child: _previewColumn(t)),
                    const SizedBox(width: kGap),
                    SizedBox(width: 336, child: _sideColumn(t)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(L10n t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      child: Row(
        children: <Widget>[
          const BrandLockup(markSize: 34),
          const SizedBox(width: 14),
          Container(width: 1, height: 26, color: Colors.white12),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              t.t('app.tagline'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
          ),
          const Spacer(),
          if (_service.running)
            _StatusPill(
              key: const ValueKey<String>('status-on'),
              color: kSuccess,
              label: t.t('status.running'),
            ),
          if (_service.running) const SizedBox(width: 4),
          _languageButton(t),
          IconButton(
            tooltip: t.t('about.title'),
            onPressed: _openAbout,
            icon: const Icon(Icons.info_outline, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _languageButton(L10n t) {
    final bool spanish = t.isSpanish;
    return Tooltip(
      message: spanish ? 'English' : 'Español',
      child: TextButton(
        onPressed: () {
          setState(() => _language = spanish ? 'en' : 'es');
          _schedulePersist();
        },
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(
          spanish ? 'EN' : 'ES',
          style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.6),
        ),
      ),
    );
  }

  Widget _errorBanner(L10n t) {
    final String message = _service.describeError(t.t);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kDanger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, size: 18, color: kDanger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: kText, fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: _openLog,
            child: Text(t.t('log.view')),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- left column

  Widget _designColumn(L10n t) {
    return ListView(
      padding: const EdgeInsets.only(right: 2, bottom: 8),
      children: <Widget>[
        _PanelCard(
          title: t.t('section.shape'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CrosshairShape.values.map((CrosshairShape shape) {
              return _ShapeChip(
                shape: shape,
                label: t.t('shape.${shape.name}'),
                selected: _spec.shape == shape,
                onTap: () {
                  if (shape == CrosshairShape.image && _customImage == null) {
                    _pickImage();
                    return;
                  }
                  _setSpec(_spec.copyWith(shape: shape));
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: kGap),
        _PanelCard(
          title: t.t('section.geometry'),
          child: Column(
            children: <Widget>[
              _SliderRow(
                label: t.t('field.size'),
                value: _spec.size,
                min: 8,
                max: 200,
                divisions: 192,
                display: '${_spec.size.round()} px',
                onChanged: (double v) => _setSpec(_spec.copyWith(size: v)),
              ),
              _SliderRow(
                label: t.t('field.thickness'),
                value: _spec.thickness,
                min: 1,
                max: 20,
                divisions: 38,
                display: _spec.thickness.toStringAsFixed(1),
                onChanged: (double v) => _setSpec(_spec.copyWith(thickness: v)),
              ),
              _SliderRow(
                label: t.t('field.gap'),
                value: _spec.gap,
                min: 0,
                max: 60,
                divisions: 60,
                display: '${_spec.gap.round()} px',
                onChanged: (double v) => _setSpec(_spec.copyWith(gap: v)),
              ),
              if (_spec.shape == CrosshairShape.cross ||
                  _spec.shape == CrosshairShape.x)
                _SliderRow(
                  label: t.t('field.arms'),
                  value: _spec.arms.toDouble(),
                  min: 2,
                  max: 8,
                  divisions: 6,
                  display: '${_spec.arms}',
                  onChanged: (double v) =>
                      _setSpec(_spec.copyWith(arms: v.round())),
                ),
              _SliderRow(
                label: t.t('field.rotation'),
                value: _spec.rotation,
                min: -180,
                max: 180,
                divisions: 72,
                display: '${_spec.rotation.round()}°',
                onChanged: (double v) => _setSpec(_spec.copyWith(rotation: v)),
              ),
              _SliderRow(
                label: t.t('field.blur'),
                value: _spec.blur,
                min: 0,
                max: 12,
                divisions: 24,
                display: _spec.blur.toStringAsFixed(1),
                onChanged: (double v) => _setSpec(_spec.copyWith(blur: v)),
              ),
              const _CardDivider(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _spec.dot,
                onChanged: (bool v) => _setSpec(_spec.copyWith(dot: v)),
                title: Text(t.t('field.dot'), style: _labelStyle),
              ),
              if (_spec.dot)
                _SliderRow(
                  label: t.t('field.dotSize'),
                  value: _spec.dotSize,
                  min: 1,
                  max: 20,
                  divisions: 38,
                  display: _spec.dotSize.toStringAsFixed(1),
                  onChanged: (double v) =>
                      _setSpec(_spec.copyWith(dotSize: v)),
                ),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        _PanelCard(
          title: t.t('section.outline'),
          child: Column(
            children: <Widget>[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _spec.outline,
                onChanged: (bool v) => _setSpec(_spec.copyWith(outline: v)),
                title: Text(t.t('field.outline'), style: _labelStyle),
              ),
              if (_spec.outline)
                _SliderRow(
                  label: t.t('field.outlineWidth'),
                  value: _spec.outlineWidth,
                  min: 0,
                  max: 6,
                  divisions: 12,
                  display: _spec.outlineWidth.toStringAsFixed(1),
                  onChanged: (double v) =>
                      _setSpec(_spec.copyWith(outlineWidth: v)),
                ),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        _PanelCard(
          title: t.t('section.color'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _presetColors.map((int color) {
                  final bool selected = (_spec.color & 0xFFFFFF) ==
                      (color & 0xFFFFFF);
                  return _Swatch(
                    color: Color(color),
                    selected: selected,
                    onTap: () => _setSpec(_spec.copyWith(color: color)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      focusNode: _hexFocus,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: t.t('field.hex'),
                        prefixIcon: const Icon(Icons.tag, size: 16),
                      ),
                      onSubmitted: (String value) {
                        final int? parsed = _parseHex(value);
                        if (parsed == null) {
                          _hexController.text = _hexOf(_spec.color);
                          return;
                        }
                        _setSpec(_spec.copyWith(color: parsed));
                        _hexController.text = _hexOf(parsed);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _spec.uiColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _SliderRow(
                label: t.t('field.opacity'),
                value: _spec.opacity,
                min: 0.05,
                max: 1,
                divisions: 19,
                display: '${(_spec.opacity * 100).round()}%',
                onChanged: (double v) => _setSpec(_spec.copyWith(opacity: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        _PanelCard(
          title: t.t('section.image'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.image_outlined, size: 18, color: kMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _spec.imagePath == null
                          ? t.t('image.none')
                          : _spec.imagePath!.split(RegExp(r'[\\/]')).last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: Text(t.t('action.pickImage')),
                    ),
                  ),
                  if (_spec.imagePath != null) ...<Widget>[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: t.t('action.removeImage'),
                      onPressed: _removeImage,
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(t.t('hint.image'), style: _hintStyle),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- middle column

  Widget _previewColumn(L10n t) {
    return Column(
      children: <Widget>[
        Expanded(child: _previewCard(t)),
        const SizedBox(height: 12),
        _actionBar(t),
      ],
    );
  }

  Widget _previewCard(L10n t) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(t.t('section.preview'), style: _cardTitleStyle),
              const Spacer(),
              _BackgroundSelector(
                value: _previewBackground,
                labels: <String, String>{
                  'dark': t.t('preview.dark'),
                  'light': t.t('preview.light'),
                  'game': t.t('preview.game'),
                },
                onChanged: (String value) =>
                    setState(() => _previewBackground = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double side =
                      math.min(constraints.maxWidth, constraints.maxHeight);
                  return ColoredBox(
                    color: kBackground,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        CustomPaint(
                          painter: _PreviewScenePainter(_previewBackground),
                        ),
                        Center(
                          child: SizedBox.square(
                            dimension: side,
                            child: CustomPaint(
                              painter: CrosshairPreviewPainter(
                                spec: _spec,
                                image: _customImage,
                                zoom: _zoom,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_zoom.toStringAsFixed(1)}×',
                              style: const TextStyle(
                                color: kMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text(
                t.t('preview.realSize',
                    vars: <String, String>{'px': '${_spec.size.round()}'}),
                style: _hintStyle,
              ),
              const Spacer(),
              Text(t.t('preview.zoom'), style: _hintStyle),
              SizedBox(
                width: 150,
                child: Slider(
                  value: _zoom,
                  min: 1,
                  max: 10,
                  divisions: 18,
                  onChanged: (double v) => setState(() => _zoom = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBar(L10n t) {
    final bool running = _service.running;
    final bool starting = _service.starting || _busy;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: starting ? null : _toggleOverlay,
                  style: FilledButton.styleFrom(
                    backgroundColor: running ? kDanger : kPrimary,
                    foregroundColor:
                        running ? const Color(0xFF2A0505) : kOnPrimary,
                    minimumSize: const Size(0, 52),
                  ),
                  icon: starting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          running ? Icons.stop_circle_outlined : Icons.play_arrow,
                          size: 20,
                        ),
                  label: Text(
                    starting
                        ? t.t('status.starting')
                        : (running ? t.t('action.stop') : t.t('action.start')),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _openLog,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                ),
                icon: const Icon(Icons.article_outlined, size: 18),
                label: Text(t.t('log.view')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(Icons.info_outline, size: 14, color: kMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_overlay.hotkey.toUpperCase()} ${t.t('hint.hotkeyToggle')} · ${t.t('hint.fullscreen')}',
                  style: _hintStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- right column

  Widget _sideColumn(L10n t) {
    return ListView(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      children: <Widget>[
        _overlayCard(t),
        const SizedBox(height: kGap),
        _profilesCard(t),
        const SizedBox(height: kGap),
        _shareCard(t),
      ],
    );
  }

  Widget _monitorPicker(L10n t) {
    final int count = _monitors.length;

    if (count == 0) {
      return Row(
        children: <Widget>[
          const Icon(Icons.monitor_rounded, size: 17, color: kMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(t.t('monitor.none'), style: _hintStyle)),
        ],
      );
    }

    if (count == 1) {
      final MonitorInfo only = _monitors.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.monitor_rounded, size: 17, color: kPrimary),
              const SizedBox(width: 8),
              Text(
                '${t.t('monitor.singleLabel')} 1 · ${only.resolution}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kText,
                ),
              ),
              if (only.primary) ...<Widget>[
                const SizedBox(width: 8),
                Text(t.t('monitor.primary'), style: _hintStyle),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(t.t('monitor.singleHint'), style: _hintStyle),
        ],
      );
    }

    final int value = _overlay.monitor.clamp(0, count - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t.t('field.monitor'), style: _labelStyle),
        const SizedBox(height: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            dropdownColor: kSurfaceAlt,
            borderRadius: BorderRadius.circular(10),
            items: _monitors.map((MonitorInfo monitor) {
              return DropdownMenuItem<int>(
                value: monitor.index,
                child: Text(
                  '${t.t('monitor.singleLabel')} ${monitor.index + 1}'
                  ' · ${monitor.resolution}'
                  '${monitor.primary ? ' · ${t.t('monitor.primary')}' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
              );
            }).toList(),
            onChanged: (int? next) {
              if (next == null) return;
              _setOverlay(_overlay.copyWith(monitor: next));
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(t.t('monitor.hint'), style: _hintStyle),
      ],
    );
  }

  Widget _overlayCard(L10n t) {
    return _PanelCard(
      title: t.t('section.overlay'),
      trailing: IconButton(
        tooltip: t.t('action.refresh'),
        onPressed: _refreshMonitors,
        icon: const Icon(Icons.refresh, size: 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _monitorPicker(t)),
            ],
          ),
          const _CardDivider(),
          Text(t.t('field.position'), style: _labelStyle),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _Dpad(
                onUp: () => _nudge(0, -2),
                onDown: () => _nudge(0, 2),
                onLeft: () => _nudge(-2, 0),
                onRight: () => _nudge(2, 0),
                onCenter: () =>
                    _setOverlay(_overlay.copyWith(offsetX: 0, offsetY: 0)),
                centerTooltip: t.t('action.center'),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'X ${_overlay.offsetX >= 0 ? '+' : ''}${_overlay.offsetX}'
                      '   Y ${_overlay.offsetY >= 0 ? '+' : ''}${_overlay.offsetY}',
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 13,
                        color: kText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.t('hint.ads'),
                      style: _hintStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const _CardDivider(),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _hotkeyController,
                  focusNode: _hotkeyFocus,
                  decoration: InputDecoration(
                    labelText: t.t('field.hotkey'),
                    hintText: t.t('hint.hotkey'),
                  ),
                  onSubmitted: (_) => _applyHotkey(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _applyHotkey,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(t.t('action.apply')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(t.t('hint.hotkeyWhat'), style: _hintStyle),
          const SizedBox(height: 4),
          Text(t.t('hint.hotkeyConflict'), style: _hintStyle),
          const _CardDivider(),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _overlay.hideOnAds,
            onChanged: (bool v) =>
                _setOverlay(_overlay.copyWith(hideOnAds: v)),
            title: Text(t.t('switch.ads'), style: _labelStyle),
          ),
        ],
      ),
    );
  }

  Widget _profilesCard(L10n t) {
    return _PanelCard(
      title: t.t('section.profiles'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: _saveProfile,
            icon: const Icon(Icons.add, size: 16),
            label: Text(t.t('profile.save')),
          ),
          const SizedBox(height: 10),
          if (_profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                t.t('profile.empty'),
                textAlign: TextAlign.center,
                style: _hintStyle,
              ),
            )
          else
            ..._profiles.map((Profile profile) {
              final bool active = profile.id == _activeProfileId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: active
                      ? kPrimary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _loadProfile(profile),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            active
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 14,
                            color: active ? kPrimary : kMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: active ? kPrimary : kText,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${t.t('shape.${profile.spec.shape.name}')} · '
                                  '${profile.spec.size.round()} px',
                                  style: _hintStyle,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: t.t('profile.delete'),
                            onPressed: () => _deleteProfile(profile),
                            icon: const Icon(Icons.close, size: 15),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _shareCard(L10n t) {
    return _PanelCard(
      title: t.t('section.share'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: _copyShareCode,
            icon: const Icon(Icons.copy, size: 16),
            label: Text(t.t('share.copy')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _importShareCode,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: Text(t.t('share.import')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _exportPng,
            icon: const Icon(Icons.image_outlined, size: 16),
            label: Text(t.t('share.export')),
          ),
          const SizedBox(height: 10),
          Text(t.t('hint.autosave'), style: _hintStyle),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Small presentational widgets
// ----------------------------------------------------------------------------

final TextStyle _labelStyle = const TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: kText,
);

final TextStyle _hintStyle = const TextStyle(
  fontSize: 11.5,
  height: 1.35,
  color: kMuted,
);

final TextStyle _cardTitleStyle = const TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.1,
  color: kMuted,
);

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title.toUpperCase(), style: _cardTitleStyle)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, color: Colors.white12),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: _labelStyle),
              const Spacer(),
              Text(
                display,
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  color: kPrimary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShapeChip extends StatelessWidget {
  const _ShapeChip({
    required this.shape,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final CrosshairShape shape;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (shape) {
        CrosshairShape.cross => Icons.add,
        CrosshairShape.dot => Icons.circle,
        CrosshairShape.circle => Icons.radio_button_unchecked,
        CrosshairShape.tee => Icons.vertical_align_top,
        CrosshairShape.triangle => Icons.change_history,
        CrosshairShape.chevron => Icons.keyboard_arrow_up,
        CrosshairShape.square => Icons.crop_square,
        CrosshairShape.x => Icons.close,
        CrosshairShape.image => Icons.image_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? kPrimary : kMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 96,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? kPrimary.withValues(alpha: 0.1) : kSurfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? kPrimary.withValues(alpha: 0.6) : Colors.white10,
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(_icon, size: 17, color: fg),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? kText : kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? kText : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class _Dpad extends StatelessWidget {
  const _Dpad({
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
    required this.onCenter,
    required this.centerTooltip,
  });

  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onCenter;
  final String centerTooltip;

  Widget _arrow(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 34,
      height: 30,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _arrow(Icons.keyboard_arrow_up, onUp),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _arrow(Icons.keyboard_arrow_left, onLeft),
            Tooltip(
              message: centerTooltip,
              child: SizedBox(
                width: 34,
                height: 30,
                child: IconButton(
                  onPressed: onCenter,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.adjust, size: 15),
                ),
              ),
            ),
            _arrow(Icons.keyboard_arrow_right, onRight),
          ],
        ),
        _arrow(Icons.keyboard_arrow_down, onDown),
      ],
    );
  }
}

class _BackgroundSelector extends StatelessWidget {
  const _BackgroundSelector({
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final String value;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: kSurfaceAlt,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: labels.entries.map((MapEntry<String, String> entry) {
          final bool selected = entry.key == value;
          return GestureDetector(
            onTap: () => onChanged(entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? kSurface : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? kText : kMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.color, required this.label, super.key});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fake scene behind the crosshair, so contrast can be judged against
/// something other than a flat black rectangle.
class _PreviewScenePainter extends CustomPainter {
  const _PreviewScenePainter(this.mode);

  final String mode;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    switch (mode) {
      case 'light':
        canvas.drawRect(rect, Paint()..color = const Color(0xFFE7EBF0));
        _grid(canvas, size, const Color(0x14000000));
      case 'game':
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.linear(
              rect.topCenter,
              rect.bottomCenter,
              <Color>[
                const Color(0xFF22323F),
                const Color(0xFF0B1015),
              ],
            ),
        );
        final double horizon = size.height * 0.62;
        canvas.drawRect(
          Rect.fromLTWH(0, horizon, size.width, size.height - horizon),
          Paint()..color = const Color(0xFF121A18),
        );
        for (int i = 0; i < 5; i++) {
          final double w = size.width * (0.06 + i * 0.015);
          canvas.drawRect(
            Rect.fromLTWH(
              size.width * (0.08 + i * 0.19),
              horizon - size.height * (0.10 + i * 0.04),
              w,
              size.height,
            ),
            Paint()..color = const Color(0xFF0D1317),
          );
        }
        canvas.drawCircle(
          Offset(size.width * 0.78, size.height * 0.26),
          size.width * 0.05,
          Paint()..color = const Color(0xFFFFE0B2).withValues(alpha: 0.18),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, horizon - 1, size.width, 1),
          Paint()..color = const Color(0xFF3A4A3F).withValues(alpha: 0.6),
        );
      case 'dark':
      default:
        canvas.drawRect(rect, Paint()..color = const Color(0xFF07090C));
        _grid(canvas, size, const Color(0x0DFFFFFF));
    }
  }

  void _grid(Canvas canvas, Size size, Color color) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const double step = 32;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_PreviewScenePainter oldDelegate) =>
      oldDelegate.mode != mode;
}
