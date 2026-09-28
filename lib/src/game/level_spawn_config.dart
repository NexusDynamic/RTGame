import 'dart:math';
import 'package:flame/components.dart';
import 'package:rise_together_game/src/components/level_object.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/level_object_pool.dart';
import 'package:rise_together_game/src/game/rise_together_world.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Placement constraints for spawning objects
class PlacementConstraints {
  /// Minimum vertical progress (0.0 = bottom, 1.0 = top)
  final double minVerticalProgress;

  /// Maximum vertical progress (0.0 = bottom, 1.0 = top)
  final double maxVerticalProgress;

  /// Minimum horizontal position, in WORLD UNITS (not normalised): it is
  /// clamped against the paddle half-width and used directly as an x
  /// coordinate. Defaults to the paddle's reach.
  final double minHorizontalPosition;

  /// Maximum horizontal position, in WORLD UNITS. See [minHorizontalPosition].
  final double maxHorizontalPosition;

  const PlacementConstraints({
    this.minVerticalProgress = 0.0,
    this.maxVerticalProgress = 1.0,
    this.minHorizontalPosition = -GameGeometry.paddleHalfWidth,
    this.maxHorizontalPosition = GameGeometry.paddleHalfWidth,
  });

  /// Common constraint: only spawn after 1/5th of level
  static const afterFirstFifth = PlacementConstraints(minVerticalProgress: 0.2);

  /// Common constraint: spawn in middle third of level
  static const middleThird = PlacementConstraints(
    minVerticalProgress: 0.33,
    maxVerticalProgress: 0.67,
  );

  /// Common constraint: only in left half
  static const leftHalf = PlacementConstraints(maxHorizontalPosition: 0.0);

  /// Common constraint: only in right half
  static const rightHalf = PlacementConstraints(minHorizontalPosition: 0.0);

  Map<String, dynamic> toJson() => {
    'minVerticalProgress': minVerticalProgress,
    'maxVerticalProgress': maxVerticalProgress,
    'minHorizontalPosition': minHorizontalPosition,
    'maxHorizontalPosition': maxHorizontalPosition,
  };

  factory PlacementConstraints.fromJson(Map<String, dynamic> json) {
    return PlacementConstraints(
      minVerticalProgress:
          (json['minVerticalProgress'] as num?)?.toDouble() ?? 0.0,
      maxVerticalProgress:
          (json['maxVerticalProgress'] as num?)?.toDouble() ?? 1.0,
      minHorizontalPosition:
          (json['minHorizontalPosition'] as num?)?.toDouble() ?? -0.5,
      maxHorizontalPosition:
          (json['maxHorizontalPosition'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// Configuration for a single spawn instance
class SpawnInstance {
  // 'fatal', 'powerup_width', 'powerdown_width', 'control_reversal', 'control_reversal_zone'
  final String objectType;
  Type get objectClass {
    switch (objectType) {
      case 'fatal':
        return FatalObstacle;
      case 'powerup_width':
        return PaddleWidthPowerup;
      case 'powerdown_width':
        return PaddleWidthPowerdown;
      case 'control_reversal':
        return ControlReversalTrigger;
      case 'control_reversal_zone':
        return ControlReversalZone;
      default:
        throw ArgumentError('Unknown object type: $objectType');
    }
  }

  final PlacementConstraints constraints;
  final Map<String, dynamic>? customParams; // e.g., {'widthMultiplier': 1.5}

  const SpawnInstance({
    required this.objectType,
    this.constraints = const PlacementConstraints(),
    this.customParams,
  });

  Map<String, dynamic> toJson() => {
    'objectType': objectType,
    'constraints': constraints.toJson(),
    if (customParams != null) 'customParams': customParams,
  };

  factory SpawnInstance.fromJson(Map<String, dynamic> json) {
    return SpawnInstance(
      objectType: json['objectType'] as String,
      constraints: json['constraints'] != null
          ? PlacementConstraints.fromJson(
              json['constraints'] as Map<String, dynamic>,
            )
          : const PlacementConstraints(),
      customParams: json['customParams'] as Map<String, dynamic>?,
    );
  }
}

/// Deterministic level object spawner
///
/// Uses a seed to ensure reproducible object placement across all clients
/// in the same experiment run. Different experiment runs can use different seeds.
class LevelSpawnConfig with AppLogging {
  final int seed;
  final List<SpawnInstance> spawns;
  final double levelWidth;
  final double levelHeight;

  late Random _random;

  LevelSpawnConfig({
    required this.seed,
    required this.spawns,
    required this.levelWidth,
    required this.levelHeight,
  }) {
    _random = Random(seed);
  }

  /// Generate spawn positions for all configured objects
  ///
  /// Returns a list of tuples: (LevelObject factory, position)
  /// The same seed will always produce the same positions
  List<SpawnedObject> generateSpawns({
    required RiseTogetherWorld world,
    LevelObjectPool? pool,
  }) {
    // Get paddle width multiplier from settings to constrain spawn positions
    final paddleWidthMultiplier = world.appSettings.getDouble(
      'physics.paddle_width_multiplier',
    );

    appLog.info(
      'generateSpawns: levelWidth=$levelWidth, levelHeight=$levelHeight, spawns.length=${spawns.length}, paddleWidthMultiplier=$paddleWidthMultiplier',
    );

    final spawned = <SpawnedObject>[];
    for (final placement in computePlacements(paddleWidthMultiplier)) {
      final spawn = placement.spawn;
      final position = placement.position;
      final size = placement.size;

      appLog.info(
        'Spawning ${spawn.objectType} at position=$position, size=$size',
      );
      if (pool != null) {
        final pooledObject = pool.acquire(
          objectType: spawn.objectType,
          position: position,
          size: size,
          customParams: spawn.customParams,
        );
        spawned.add(SpawnedObject(pooledObject, position));
        appLog.info(
          'Generated spawn from pool: ${spawn.objectType} at $position (seed: $seed)',
        );
        continue;
      }
      final object = _createObject(
        world,
        spawn.objectType,
        position,
        size,
        spawn.customParams,
      );

      spawned.add(SpawnedObject(object, position));
      appLog.info(
        'Generated spawn: ${spawn.objectType} at $position (seed: $seed)',
      );
    }

    return spawned;
  }

  /// Where every configured object goes, without building any of them.
  ///
  /// Pure and deterministic for a given [seed] and [paddleWidthMultiplier] --
  /// split out of [generateSpawns] so layouts can be tested without a world.
  /// The draw order is one random pair per spawn, in list order, exactly as it
  /// always was, so existing levels place identically.
  List<SpawnPlacement> computePlacements(double paddleWidthMultiplier) {
    // Reset random with same seed for reproducibility
    _random = Random(seed);
    return [
      for (final spawn in spawns)
        SpawnPlacement(
          spawn,
          _generatePosition(spawn.constraints, paddleWidthMultiplier),
          defaultSize(spawn.objectType, spawn.customParams),
        ),
    ];
  }

  /// A config whose objects cannot overlap vertically, by construction.
  ///
  /// [objects] are laid out bottom to top, one per equal slot across the
  /// middle 90% of the level. Each object is still placed at random, but only
  /// within its own slot, shrunk at both ends by its half-height plus [gap], so
  /// neighbouring objects are always at least `2 * gap` apart. Reversal zones
  /// span the full width and are centred; everything else keeps the default
  /// horizontal range (the paddle's reach).
  factory LevelSpawnConfig.slotted({
    required int seed,
    required double levelWidth,
    required double levelHeight,
    required List<(String, Map<String, dynamic>?)> objects,
    double gap = GameGeometry.ballRadius * 2,
  }) {
    const bottom = 0.05;
    const top = 0.95;
    final slot = (top - bottom) / objects.length;
    final spawns = <SpawnInstance>[];
    for (var i = 0; i < objects.length; i++) {
      final (type, params) = objects[i];
      final halfHeight = _sizeFor(type, params, levelWidth).y / 2 + gap;
      final margin = halfHeight / levelHeight;
      var lo = bottom + slot * i + margin;
      var hi = bottom + slot * (i + 1) - margin;
      if (lo > hi) {
        // Slot too small for the object: pin it to the slot centre. Only a
        // misconfigured level gets here; the layout test catches it.
        lo = hi = bottom + slot * (i + 0.5);
      }
      final isZone = type == 'control_reversal_zone';
      spawns.add(
        SpawnInstance(
          objectType: type,
          constraints: isZone
              ? PlacementConstraints(
                  minVerticalProgress: lo,
                  maxVerticalProgress: hi,
                  minHorizontalPosition: 0.0,
                  maxHorizontalPosition: 0.0,
                )
              : PlacementConstraints(
                  minVerticalProgress: lo,
                  maxVerticalProgress: hi,
                ),
          customParams: params,
        ),
      );
    }
    return LevelSpawnConfig(
      seed: seed,
      spawns: spawns,
      levelWidth: levelWidth,
      levelHeight: levelHeight,
    );
  }

  /// Generate a random position within constraints
  Vector2 _generatePosition(
    PlacementConstraints constraints,
    double paddleWidthMultiplier,
  ) {
    // Vertical: 0.0 = bottom (y=0), 1.0 = top (y=-levelHeight)
    final verticalProgress =
        constraints.minVerticalProgress +
        _random.nextDouble() *
            (constraints.maxVerticalProgress - constraints.minVerticalProgress);
    final y = -levelHeight * verticalProgress;

    // Horizontal: constrain to the paddle's reach. Must stay in sync with the
    // paddle's own geometry, hence GameGeometry rather than a repeated literal
    // -- otherwise a scale change silently stops obstacles matching the paddle.
    final paddleHalfWidth =
        GameGeometry.paddleHalfWidth * paddleWidthMultiplier;

    // Clamp constraint bounds to paddle bounds
    final minX = constraints.minHorizontalPosition.clamp(
      -paddleHalfWidth,
      paddleHalfWidth,
    );
    final maxX = constraints.maxHorizontalPosition.clamp(
      -paddleHalfWidth,
      paddleHalfWidth,
    );

    // Ensure min <= max after clamping
    final actualMinX = minX < maxX ? minX : maxX;
    final actualMaxX = minX < maxX ? maxX : minX;

    // Interpolate between clamped bounds
    final x = actualMinX + _random.nextDouble() * (actualMaxX - actualMinX);

    return Vector2(x, y);
  }

  /// Size an object of [objectType] is spawned at in this level.
  Vector2 defaultSize(
    String objectType, [
    Map<String, dynamic>? customParams,
  ]) => _sizeFor(objectType, customParams, levelWidth);

  static Vector2 _sizeFor(
    String objectType,
    Map<String, dynamic>? customParams,
    double levelWidth,
  ) {
    if (objectType == 'control_reversal_zone') {
      // The fallback is only reached for configs deserialised without the
      // param; every level in rise_together_levels.dart supplies one. It was
      // 2.0, i.e. twice the entire width of Level 1 -- sized as if it were
      // metres rather than world units.
      final zoneHeight =
          (customParams?['zoneHeightMeters'] as num?)?.toDouble() ??
          GameGeometry.length(0.4);
      return Vector2(levelWidth, zoneHeight);
    }
    // Default size as fraction of level width
    // Making larger for visibility: 10% instead of 5%
    final baseSize = levelWidth * 0.1;
    return Vector2.all(baseSize);
  }

  /// Create the appropriate LevelObject instance
  LevelObject _createObject(
    RiseTogetherWorld world,
    String objectType,
    Vector2 position,
    Vector2 size,
    Map<String, dynamic>? customParams,
  ) {
    switch (objectType) {
      case 'fatal':
        return FatalObstacle(world, position: position, size: size);

      case 'powerup_width':
        final multiplier =
            (customParams?['widthMultiplier'] as num?)?.toDouble() ?? 1.3;
        return PaddleWidthPowerup(
          world,
          position: position,
          size: size,
          widthMultiplier: multiplier,
        );

      case 'powerdown_width':
        final multiplier =
            (customParams?['widthMultiplier'] as num?)?.toDouble() ?? 0.7;
        return PaddleWidthPowerdown(
          world,
          position: position,
          size: size,
          widthMultiplier: multiplier,
        );

      case 'control_reversal':
        final duration =
            (customParams?['duration'] as num?)?.toDouble() ?? 10.0;
        return ControlReversalTrigger(
          world,
          position: position,
          size: size,
          duration: duration,
        );

      case 'control_reversal_zone':
        return ControlReversalZone(world, position: position, size: size);

      default:
        throw ArgumentError('Unknown object type: $objectType');
    }
  }

  /// Serialize configuration to JSON
  Map<String, dynamic> toJson() => {
    'seed': seed,
    'levelWidth': levelWidth,
    'levelHeight': levelHeight,
    'spawns': spawns.map((s) => s.toJson()).toList(),
  };

  /// Deserialize configuration from JSON
  factory LevelSpawnConfig.fromJson(Map<String, dynamic> json) {
    return LevelSpawnConfig(
      seed: json['seed'] as int,
      levelWidth: (json['levelWidth'] as num).toDouble(),
      levelHeight: (json['levelHeight'] as num).toDouble(),
      spawns: (json['spawns'] as List)
          .map((s) => SpawnInstance.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Where one configured object goes; see [LevelSpawnConfig.computePlacements].
class SpawnPlacement {
  final SpawnInstance spawn;
  final Vector2 position;
  final Vector2 size;

  const SpawnPlacement(this.spawn, this.position, this.size);
}

/// Container for a spawned object and its position
class SpawnedObject {
  final LevelObject object;
  final Vector2 position;

  SpawnedObject(this.object, this.position);
}
