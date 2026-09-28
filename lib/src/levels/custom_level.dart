/// Player-made levels: the data model, and the only code that turns untrusted
/// text (an imported file, or a pack received from another player) into it.
///
/// A level is plain data drawn from a fixed menu: a height and a list of
/// objects, each one of [CustomObjectType] at a position with at most one
/// numeric parameter. Nothing in it is evaluated or looked up by name at play
/// time. Every decoder checks type, range and count, and returns null rather
/// than throwing, following the rules in `lib/src/net/game_session.dart`.
///
/// Coordinates are world units ([levelWidth] wide), x centred on 0 and y the
/// height above the ground, so a value means the same on every device.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

/// The objects a custom level can contain.
///
/// The wire format sends [index], so new values must only ever be appended.
enum CustomObjectType {
  /// Touching it restarts the level.
  fatal(param: null, spawnType: 'fatal'),

  /// Widens the paddle for the rest of the level.
  powerupWidth(
    param: ParamSpec('widthMultiplier', min: 1.05, max: 2.0, fallback: 1.3),
    spawnType: 'powerup_width',
  ),

  /// Narrows the paddle for the rest of the level.
  powerdownWidth(
    param: ParamSpec('widthMultiplier', min: 0.5, max: 0.95, fallback: 0.7),
    spawnType: 'powerdown_width',
  ),

  /// Swaps left and right for a while.
  controlReversal(
    param: ParamSpec('duration', min: 1, max: 30, fallback: 10),
    spawnType: 'control_reversal',
  ),

  /// A full-width band that swaps left and right while the ball is inside.
  controlReversalZone(
    param: ParamSpec('zoneHeight', min: 1, max: 10, fallback: 4),
    spawnType: 'control_reversal_zone',
  );

  const CustomObjectType({required this.param, required this.spawnType});

  /// The one parameter this type takes, if any.
  final ParamSpec? param;

  /// The object type string the level spawner understands.
  final String spawnType;

  bool get isZone => this == controlReversalZone;

  static CustomObjectType? byName(Object? name) =>
      values.where((t) => t.name == name).firstOrNull;

  static CustomObjectType? byIndex(Object? index) =>
      index is int && index >= 0 && index < values.length
      ? values[index]
      : null;
}

/// Bounds for an object's parameter.
@immutable
class ParamSpec {
  const ParamSpec(
    this.key, {
    required this.min,
    required this.max,
    required this.fallback,
  });

  /// Key in the file format, and in the spawner's params.
  final String key;
  final double min;
  final double max;
  final double fallback;
}

/// Hard limits. Anything outside them is rejected, not clamped, when decoded.
abstract final class CustomLevelLimits {
  /// World units; must match `GameGeometry.levelWidth`.
  static const double levelWidth = 10;

  /// Height of a level as a multiple of its width. The built-in levels go up
  /// to 15.
  static const double minHeight = 1;
  static const double maxHeight = 20;

  /// Nothing may reach down into the area where the ball and paddle start.
  static const double spawnClearance = 1.5;

  /// Side of the square non-zone objects, in world units.
  static const double objectSize = levelWidth * 0.1;

  static const int maxObjects = 40;
  static const int maxLevelsPerPack = 10;

  /// Levels in one imported file, and in the local library.
  static const int maxLevelsPerFile = 50;

  static const int maxNameLength = 40;

  /// A pack as sent to other players. The largest valid pack is about 10 KB.
  static const int maxWireChars = 16 * 1024;

  /// An imported file.
  static const int maxFileChars = 256 * 1024;

  /// Every number is kept to hundredths, so all devices build exactly the
  /// same level.
  static const int steps = 100;
  static const double quantum = 1 / steps;
}

/// Nearest hundredth. Division is correctly rounded, so this gives the same
/// double as parsing the two-decimal string on every platform.
double _quantize(double v) =>
    (v * CustomLevelLimits.steps).roundToDouble() / CustomLevelLimits.steps;

/// A finite number, or null. JSON has no int/double distinction to rely on.
double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

/// One object placed in a level.
@immutable
class CustomObject {
  const CustomObject._(this.type, this.x, this.y, this.param);

  /// Returns null unless every value is in range for [type].
  ///
  /// [param] is required for types that take one and forbidden otherwise.
  static CustomObject? create({
    required CustomObjectType type,
    required double x,
    required double y,
    double? param,
    required double levelHeight,
  }) {
    if (!x.isFinite || !y.isFinite) return null;
    final spec = type.param;
    if ((spec == null) != (param == null)) return null;
    if (param != null) {
      if (!param.isFinite || param < spec!.min || param > spec.max) return null;
      param = _quantize(param);
    }
    x = _quantize(x);
    y = _quantize(y);
    final (halfW, halfH) = halfExtents(type, param);
    if (type.isZone) {
      if (x != 0) return null;
    } else if (x.abs() > CustomLevelLimits.levelWidth / 2 - halfW) {
      return null;
    }
    if (y - halfH < CustomLevelLimits.spawnClearance - 1e-9) return null;
    if (y + halfH > levelHeight + 1e-9) return null;
    return CustomObject._(type, x, y, param);
  }

  final CustomObjectType type;

  /// Centre, in world units from the middle of the level.
  final double x;

  /// Centre, in world units above the ground.
  final double y;

  /// Value for [CustomObjectType.param]; null when the type takes none.
  final double? param;

  /// Half width and half height of an object of [type].
  static (double, double) halfExtents(CustomObjectType type, double? param) {
    if (type.isZone) {
      return (
        CustomLevelLimits.levelWidth / 2,
        (param ?? type.param!.fallback) / 2,
      );
    }
    const half = CustomLevelLimits.objectSize / 2;
    return (half, half);
  }

  /// Size in world units, (width, height).
  (double, double) get size {
    final (w, h) = halfExtents(type, param);
    return (w * 2, h * 2);
  }

  /// The same object moved, or null if it would not fit there.
  CustomObject? moved({
    required double x,
    required double y,
    required double levelHeight,
  }) => create(type: type, x: x, y: y, param: param, levelHeight: levelHeight);

  /// Nearest valid position to (x, y) in a level of [levelHeight].
  static (double, double) clampPosition(
    CustomObjectType type,
    double? param,
    double x,
    double y,
    double levelHeight,
  ) {
    final (halfW, halfH) = halfExtents(type, param);
    final maxX = CustomLevelLimits.levelWidth / 2 - halfW;
    final minY = CustomLevelLimits.spawnClearance + halfH;
    final maxY = levelHeight - halfH;
    // Quantize inwards so the result always validates.
    double inRange(double v, double lo, double hi) {
      final q = _quantize(v.clamp(lo, hi < lo ? lo : hi));
      if (q < lo) return q + CustomLevelLimits.quantum;
      if (q > hi) return q - CustomLevelLimits.quantum;
      return q;
    }

    return (
      type.isZone ? 0 : inRange(x, -maxX, maxX),
      inRange(y, minY, maxY < minY ? minY : maxY),
    );
  }

  List<Object> _toWire() => [type.index, x, y, ?param];

  static CustomObject? _fromWire(Object? json, double levelHeight) {
    if (json is! List || json.length < 3 || json.length > 4) return null;
    final type = CustomObjectType.byIndex(json[0]);
    final x = _number(json[1]);
    final y = _number(json[2]);
    final param = json.length == 4 ? _number(json[3]) : null;
    if (type == null || x == null || y == null) return null;
    if (json.length == 4 && param == null) return null;
    return create(
      type: type,
      x: x,
      y: y,
      param: param,
      levelHeight: levelHeight,
    );
  }

  Map<String, Object> _toFile() => {
    'type': type.name,
    'x': x,
    'y': y,
    if (type.param case final spec?) spec.key: ?param,
  };

  static CustomObject? _fromFile(Object? json, double levelHeight) {
    if (json is! Map<String, dynamic>) return null;
    final type = CustomObjectType.byName(json['type']);
    final x = _number(json['x']);
    final y = _number(json['y']);
    if (type == null || x == null || y == null) return null;
    final spec = type.param;
    double? param;
    if (spec != null) {
      final raw = json[spec.key];
      // A missing parameter means the default; a present one must be valid.
      param = raw == null ? spec.fallback : _number(raw);
      if (param == null) return null;
    }
    return create(
      type: type,
      x: x,
      y: y,
      param: param,
      levelHeight: levelHeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CustomObject &&
      other.type == type &&
      other.x == x &&
      other.y == y &&
      other.param == param;

  @override
  int get hashCode => Object.hash(type, x, y, param);
}

/// One player-made level.
@immutable
class CustomLevel {
  CustomLevel._(this.heightMultiplier, List<CustomObject> objects, this.name)
    : objects = List.unmodifiable(objects);

  /// Returns null unless the height and object count are in range and every
  /// object fits in the level.
  static CustomLevel? create({
    required double heightMultiplier,
    List<CustomObject> objects = const [],
    String name = '',
  }) {
    if (!heightMultiplier.isFinite ||
        heightMultiplier < CustomLevelLimits.minHeight ||
        heightMultiplier > CustomLevelLimits.maxHeight) {
      return null;
    }
    if (objects.length > CustomLevelLimits.maxObjects) return null;
    final multiplier = _quantize(heightMultiplier);
    final height = multiplier * CustomLevelLimits.levelWidth;
    // Re-check each object against this level's height.
    final checked = <CustomObject>[];
    for (final o in objects) {
      final again = o.moved(x: o.x, y: o.y, levelHeight: height);
      if (again == null) return null;
      checked.add(again);
    }
    return CustomLevel._(multiplier, checked, sanitizeName(name));
  }

  /// Height as a multiple of the width, like the built-in levels'
  /// `verticalMultiplier`.
  final double heightMultiplier;
  final List<CustomObject> objects;

  /// The author's label. Stays on this device: never part of [toWire].
  final String name;

  double get height => heightMultiplier * CustomLevelLimits.levelWidth;

  CustomLevel? copyWith({
    double? heightMultiplier,
    List<CustomObject>? objects,
    String? name,
  }) => create(
    heightMultiplier: heightMultiplier ?? this.heightMultiplier,
    objects: objects ?? this.objects,
    name: name ?? this.name,
  );

  /// Trim, drop control and formatting characters (which include the bidi
  /// overrides), and cap the length.
  static String sanitizeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\p{Cc}\p{Cf}\p{Co}\p{Cs}]', unicode: true), '')
        .trim();
    final runes = cleaned.runes.toList();
    return runes.length <= CustomLevelLimits.maxNameLength
        ? cleaned
        : String.fromCharCodes(
            runes.take(CustomLevelLimits.maxNameLength),
          ).trim();
  }

  List<Object> _toWire() => [
    heightMultiplier,
    [for (final o in objects) o._toWire()],
  ];

  static CustomLevel? _fromWire(Object? json) {
    if (json is! List || json.length != 2) return null;
    final multiplier = _number(json[0]);
    final rawObjects = json[1];
    if (multiplier == null || rawObjects is! List) return null;
    if (rawObjects.length > CustomLevelLimits.maxObjects) return null;
    if (multiplier < CustomLevelLimits.minHeight ||
        multiplier > CustomLevelLimits.maxHeight) {
      return null;
    }
    final height = _quantize(multiplier) * CustomLevelLimits.levelWidth;
    final objects = <CustomObject>[];
    for (final raw in rawObjects) {
      final o = CustomObject._fromWire(raw, height);
      if (o == null) return null;
      objects.add(o);
    }
    return create(heightMultiplier: multiplier, objects: objects);
  }

  Map<String, Object> toFileJson() => {
    'name': name,
    'height': heightMultiplier,
    'objects': [for (final o in objects) o._toFile()],
  };

  /// One level from the file format; null if anything is invalid.
  static CustomLevel? fromFileJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final multiplier = _number(json['height']);
    final rawObjects = json['objects'] ?? const <Object?>[];
    final name = json['name'] ?? '';
    if (multiplier == null || rawObjects is! List || name is! String) {
      return null;
    }
    if (name.length > CustomLevelLimits.maxNameLength * 4) return null;
    if (rawObjects.length > CustomLevelLimits.maxObjects) return null;
    if (multiplier < CustomLevelLimits.minHeight ||
        multiplier > CustomLevelLimits.maxHeight) {
      return null;
    }
    final height = _quantize(multiplier) * CustomLevelLimits.levelWidth;
    final objects = <CustomObject>[];
    for (final raw in rawObjects) {
      final o = CustomObject._fromFile(raw, height);
      if (o == null) return null;
      objects.add(o);
    }
    return create(heightMultiplier: multiplier, objects: objects, name: name);
  }

  /// Same layout, regardless of name.
  bool sameLayout(CustomLevel other) =>
      other.heightMultiplier == heightMultiplier &&
      other.objects.length == objects.length &&
      Iterable.generate(
        objects.length,
      ).every((i) => other.objects[i] == objects[i]);
}

/// The levels of one online match, in order.
@immutable
class CustomLevelPack {
  CustomLevelPack._(List<CustomLevel> levels)
    : levels = List.unmodifiable(levels);

  static CustomLevelPack? create(List<CustomLevel> levels) {
    if (levels.isEmpty || levels.length > CustomLevelLimits.maxLevelsPerPack) {
      return null;
    }
    return CustomLevelPack._(levels);
  }

  static const _wireVersion = 1;

  final List<CustomLevel> levels;

  /// Compact form for other players. Carries no names or other text.
  String toWire() => jsonEncode([
    _wireVersion,
    [for (final l in levels) l._toWire()],
  ]);

  /// Decode a pack received from the network. Returns null for anything that
  /// is not exactly a valid pack, including oversized input, which is refused
  /// before it is parsed.
  static CustomLevelPack? fromWire(Object? wire) {
    if (wire is! String || wire.length > CustomLevelLimits.maxWireChars) {
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(wire);
    } on FormatException {
      return null;
    }
    if (json is! List || json.length != 2 || json[0] != _wireVersion) {
      return null;
    }
    final rawLevels = json[1];
    if (rawLevels is! List ||
        rawLevels.isEmpty ||
        rawLevels.length > CustomLevelLimits.maxLevelsPerPack) {
      return null;
    }
    final levels = <CustomLevel>[];
    for (final raw in rawLevels) {
      final level = CustomLevel._fromWire(raw);
      if (level == null) return null;
      levels.add(level);
    }
    return create(levels);
  }
}

/// The export / import file: any number of levels, with their names.
abstract final class CustomLevelFile {
  static const format = 'rise-together-levels';
  static const version = 1;

  static String encode(List<CustomLevel> levels) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'units': 'world units; x from the centre, y above the ground',
        'levels': [for (final l in levels) l.toFileJson()],
      });

  /// Decode a file the player chose to import. Null if it is not one, is too
  /// big, or any level in it is invalid.
  static List<CustomLevel>? decode(String text) {
    if (text.length > CustomLevelLimits.maxFileChars) return null;
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    if (json['format'] != format || json['version'] != version) return null;
    final rawLevels = json['levels'];
    if (rawLevels is! List ||
        rawLevels.isEmpty ||
        rawLevels.length > CustomLevelLimits.maxLevelsPerFile) {
      return null;
    }
    final levels = <CustomLevel>[];
    for (final raw in rawLevels) {
      final level = CustomLevel.fromFileJson(raw);
      if (level == null) return null;
      levels.add(level);
    }
    return levels;
  }
}
