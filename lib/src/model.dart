import 'dart:convert';
import 'dart:ui' show Color;

/// Crosshair shapes available in the designer.
///
/// These are generic geometric primitives. No artwork from any third-party
/// application is used or reproduced.
enum CrosshairShape {
  cross,
  dot,
  circle,
  tee,
  triangle,
  chevron,
  square,
  x,
  image;

  static CrosshairShape fromId(String? id) {
    for (final shape in CrosshairShape.values) {
      if (shape.name == id) return shape;
    }
    return CrosshairShape.cross;
  }
}

double _clampDouble(Object? value, double fallback, double min, double max) {
  final double parsed = switch (value) {
    num v => v.toDouble(),
    String v => double.tryParse(v) ?? fallback,
    _ => fallback,
  };
  if (parsed.isNaN || parsed.isInfinite) return fallback;
  return parsed.clamp(min, max);
}

int _clampInt(Object? value, int fallback, int min, int max) {
  final int parsed = switch (value) {
    num v => v.round(),
    String v => int.tryParse(v) ?? fallback,
    _ => fallback,
  };
  return parsed.clamp(min, max);
}

/// Everything needed to draw one crosshair.
///
/// All lengths are logical pixels. [size] is the outer diameter of the shape
/// as it must appear on screen; the sprite generator renders it 1:1 so a value
/// of 24 means 24 physical pixels on the overlay.
class CrosshairSpec {
  const CrosshairSpec({
    this.shape = CrosshairShape.cross,
    this.arms = 4,
    this.size = 24,
    this.thickness = 3,
    this.gap = 6,
    this.dot = false,
    this.dotSize = 4,
    this.outline = true,
    this.outlineWidth = 1.5,
    this.color = 0xFF00E87A,
    this.opacity = 1,
    this.rotation = 0,
    this.blur = 0,
    this.imagePath,
  });

  final CrosshairShape shape;

  /// Number of radial arms for cross/x; clamped to 2..8.
  final int arms;
  final double size;
  final double thickness;
  final double gap;
  final bool dot;
  final double dotSize;
  final bool outline;
  final double outlineWidth;
  final int color;
  final double opacity;
  final double rotation;
  final double blur;
  final String? imagePath;

  Color get uiColor => Color(color);

  CrosshairSpec copyWith({
    CrosshairShape? shape,
    int? arms,
    double? size,
    double? thickness,
    double? gap,
    bool? dot,
    double? dotSize,
    bool? outline,
    double? outlineWidth,
    int? color,
    double? opacity,
    double? rotation,
    double? blur,
    Object? imagePath = _unset,
  }) {
    return CrosshairSpec(
      shape: shape ?? this.shape,
      arms: arms ?? this.arms,
      size: size ?? this.size,
      thickness: thickness ?? this.thickness,
      gap: gap ?? this.gap,
      dot: dot ?? this.dot,
      dotSize: dotSize ?? this.dotSize,
      outline: outline ?? this.outline,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      rotation: rotation ?? this.rotation,
      blur: blur ?? this.blur,
      imagePath: imagePath == _unset ? this.imagePath : imagePath as String?,
    );
  }

  static const Object _unset = Object();

  /// Returns a copy that respects every invariant the renderer relies on.
  CrosshairSpec sanitized() {
    final int cleanColor = color & 0xFFFFFFFF;
    // Fully transparent crosshairs are useless and look like a bug; keep at
    // least 5% alpha, matching the overlay's own floor.
    final int alpha = (cleanColor >> 24) & 0xFF;
    final int safeColor = alpha < 13 ? (cleanColor | 0x0D000000) : cleanColor;
    return CrosshairSpec(
      shape: shape,
      arms: arms.clamp(2, 8),
      size: size.clamp(8, 200),
      thickness: thickness.clamp(1, 40),
      gap: gap.clamp(0, 60),
      dot: dot,
      dotSize: dotSize.clamp(1, 40),
      outline: outline,
      outlineWidth: outlineWidth.clamp(0, 8),
      color: safeColor,
      opacity: opacity.clamp(0.05, 1),
      rotation: rotation.clamp(-180, 180),
      blur: blur.clamp(0, 12),
      imagePath: imagePath,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'shape': shape.name,
        'arms': arms,
        'size': size,
        'thickness': thickness,
        'gap': gap,
        'dot': dot,
        'dotSize': dotSize,
        'outline': outline,
        'outlineWidth': outlineWidth,
        'color': color,
        'opacity': opacity,
        'rotation': rotation,
        'blur': blur,
        'imagePath': imagePath,
      };

  factory CrosshairSpec.fromJson(Map<String, dynamic> json) {
    const fallback = CrosshairSpec();
    return CrosshairSpec(
      shape: CrosshairShape.fromId(json['shape'] as String?),
      arms: _clampInt(json['arms'], fallback.arms, 2, 8),
      size: _clampDouble(json['size'], fallback.size, 8, 200),
      thickness: _clampDouble(json['thickness'], fallback.thickness, 1, 40),
      gap: _clampDouble(json['gap'], fallback.gap, 0, 60),
      dot: json['dot'] == true,
      dotSize: _clampDouble(json['dotSize'], fallback.dotSize, 1, 40),
      outline: json['outline'] != false,
      outlineWidth:
          _clampDouble(json['outlineWidth'], fallback.outlineWidth, 0, 8),
      color: _clampInt(json['color'], fallback.color, 0, 0xFFFFFFFF),
      opacity: _clampDouble(json['opacity'], fallback.opacity, 0.05, 1),
      rotation: _clampDouble(json['rotation'], fallback.rotation, -180, 180),
      blur: _clampDouble(json['blur'], fallback.blur, 0, 12),
      imagePath: (json['imagePath'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['imagePath'] as String).trim(),
    ).sanitized();
  }

  /// Portable, URL-safe representation used by the share dialog.
  String encodeShare() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'v': 1,
      'kind': 'crosshair',
      'spec': toJson(),
    };
    return 'CCX1.${base64Url.encode(utf8.encode(jsonEncode(payload)))}';
  }

  static CrosshairSpec? decodeShare(String raw) {
    String text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('CCX1.')) text = text.substring(5);
    try {
      final String decoded = utf8.decode(base64Url.decode(base64Url.normalize(text)));
      final Object? json = jsonDecode(decoded);
      if (json is! Map<String, dynamic>) return null;
      final Object? spec = json['spec'];
      if (spec is! Map<String, dynamic>) return null;
      return CrosshairSpec.fromJson(spec);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CrosshairSpec &&
      other.shape == shape &&
      other.arms == arms &&
      other.size == size &&
      other.thickness == thickness &&
      other.gap == gap &&
      other.dot == dot &&
      other.dotSize == dotSize &&
      other.outline == outline &&
      other.outlineWidth == outlineWidth &&
      other.color == color &&
      other.opacity == opacity &&
      other.rotation == rotation &&
      other.blur == blur &&
      other.imagePath == imagePath;

  @override
  int get hashCode => Object.hash(shape, arms, size, thickness, gap, dot,
      dotSize, outline, outlineWidth, color, opacity, rotation, blur, imagePath);
}

/// Settings that belong to the overlay window rather than the crosshair.
class OverlaySettings {
  const OverlaySettings({
    this.monitor = 0,
    this.offsetX = 0,
    this.offsetY = 0,
    this.hotkey = 'F8',
    this.hideOnAds = true,
  });

  final int monitor;
  final int offsetX;
  final int offsetY;
  final String hotkey;
  final bool hideOnAds;

  OverlaySettings copyWith({
    int? monitor,
    int? offsetX,
    int? offsetY,
    String? hotkey,
    bool? hideOnAds,
  }) {
    return OverlaySettings(
      monitor: monitor ?? this.monitor,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      hotkey: hotkey ?? this.hotkey,
      hideOnAds: hideOnAds ?? this.hideOnAds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'monitor': monitor,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'hotkey': hotkey,
        'hideOnAds': hideOnAds,
      };

  factory OverlaySettings.fromJson(Map<String, dynamic> json) {
    return OverlaySettings(
      monitor: _clampInt(json['monitor'], 0, 0, 16),
      offsetX: _clampInt(json['offsetX'], 0, -4000, 4000),
      offsetY: _clampInt(json['offsetY'], 0, -4000, 4000),
      hotkey: (json['hotkey'] as String?)?.trim().isNotEmpty ?? false
          ? (json['hotkey'] as String).trim()
          : 'F8',
      hideOnAds: json['hideOnAds'] != false,
    );
  }

  /// Accepts `ctrl+alt+f8`, `shift+x`, `f9`, `num5`... Returns null when the
  /// string cannot describe a single key with optional modifiers.
  static String? normalizeHotkey(String raw) {
    final List<String> parts = raw
        .toLowerCase()
        .split('+')
        .map((String part) => part.trim())
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty || parts.length > 4) return null;

    const Set<String> modifiers = {'ctrl', 'alt', 'shift', 'win'};
    const Set<String> named = {
      'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11',
      'f12', 'insert', 'home', 'end', 'pageup', 'pagedown', 'pause',
      'scrolllock', 'num0', 'num1', 'num2', 'num3', 'num4', 'num5', 'num6',
      'num7', 'num8', 'num9',
    };

    final List<String> ordered = <String>[];
    String? key;
    for (final String part in parts) {
      if (modifiers.contains(part)) {
        if (!ordered.contains(part)) ordered.add(part);
        continue;
      }
      if (key != null) return null;
      final bool isNamed = named.contains(part);
      final bool isChar = RegExp(r'^[a-z0-9]$').hasMatch(part);
      if (!isNamed && !isChar) return null;
      key = part;
    }
    if (key == null) return null;
    ordered.add(key);
    return ordered.join('+');
  }
}

/// A saved crosshair plus the overlay settings it was saved with.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.spec,
    required this.overlay,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final CrosshairSpec spec;
  final OverlaySettings overlay;
  final int updatedAt;

  Profile copyWith({
    String? name,
    CrosshairSpec? spec,
    OverlaySettings? overlay,
    int? updatedAt,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      spec: spec ?? this.spec,
      overlay: overlay ?? this.overlay,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'spec': spec.toJson(),
        'overlay': overlay.toJson(),
        'updatedAt': updatedAt,
      };

  factory Profile.fromJson(Map<String, dynamic> json) {
    final Object? spec = json['spec'];
    final Object? overlay = json['overlay'];
    return Profile(
      id: (json['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: ((json['name'] as String?) ?? '').trim().isEmpty
          ? 'Perfil'
          : (json['name'] as String).trim(),
      spec: spec is Map<String, dynamic>
          ? CrosshairSpec.fromJson(spec)
          : const CrosshairSpec(),
      overlay: overlay is Map<String, dynamic>
          ? OverlaySettings.fromJson(overlay)
          : const OverlaySettings(),
      updatedAt: _clampInt(json['updatedAt'], 0, 0, 1 << 52),
    );
  }
}

/// Persisted session state.
class AppState {
  const AppState({
    this.spec = const CrosshairSpec(),
    this.overlay = const OverlaySettings(),
    this.activeProfileId,
    this.language = 'es',
    this.overlayWasOn = false,
  });

  final CrosshairSpec spec;
  final OverlaySettings overlay;
  final String? activeProfileId;
  final String language;
  final bool overlayWasOn;

  AppState copyWith({
    CrosshairSpec? spec,
    OverlaySettings? overlay,
    Object? activeProfileId = _unset,
    String? language,
    bool? overlayWasOn,
  }) {
    return AppState(
      spec: spec ?? this.spec,
      overlay: overlay ?? this.overlay,
      activeProfileId: activeProfileId == _unset
          ? this.activeProfileId
          : activeProfileId as String?,
      language: language ?? this.language,
      overlayWasOn: overlayWasOn ?? this.overlayWasOn,
    );
  }

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'spec': spec.toJson(),
        'overlay': overlay.toJson(),
        'activeProfileId': activeProfileId,
        'language': language,
        'overlayWasOn': overlayWasOn,
      };

  factory AppState.fromJson(Map<String, dynamic> json) {
    final Object? spec = json['spec'];
    final Object? overlay = json['overlay'];
    return AppState(
      spec: spec is Map<String, dynamic>
          ? CrosshairSpec.fromJson(spec)
          : const CrosshairSpec(),
      overlay: overlay is Map<String, dynamic>
          ? OverlaySettings.fromJson(overlay)
          : const OverlaySettings(),
      activeProfileId: (json['activeProfileId'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['activeProfileId'] as String,
      language: json['language'] == 'en' ? 'en' : 'es',
      overlayWasOn: json['overlayWasOn'] == true,
    );
  }
}
