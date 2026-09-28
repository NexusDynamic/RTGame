import 'package:flame/components.dart' show Vector2;
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/level_spawn_config.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';

abstract class RiseTogetherLevel {
  /// Width of the playfield, in world units.
  ///
  /// Delegates to [GameGeometry.levelWidth] so the world scale has a single
  /// home; `verticalMultiplier` below stays dimensionless and must NOT be
  /// scaled.
  static const horizontalWidth = GameGeometry.levelWidth;
  double get verticalHeight => horizontalWidth * verticalMultiplier;
  abstract final double verticalMultiplier;

  /// Spawn configuration for this level (null = no objects).
  /// Deprecated: use [spawnConfigForSeed] instead so obstacle positions are
  /// reproducible across runs when an experiment seed is in use.
  LevelSpawnConfig? get spawnConfig => null;

  /// Returns the spawn config seeded with [experimentSeed] xor'd with a
  /// level-specific constant so each level produces a unique placement.
  /// Override in subclasses that have obstacles. Returns null by default.
  LevelSpawnConfig? spawnConfigForSeed(int experimentSeed) => null;

  const RiseTogetherLevel();
}

// @TODO: Make levels configurable via settings or external config files
class Level1 extends RiseTogetherLevel {
  @override
  final double verticalMultiplier = 1.0;
  const Level1();
}

class Level2 extends RiseTogetherLevel {
  @override
  final double verticalMultiplier = 2.0;

  @override
  LevelSpawnConfig? spawnConfigForSeed(int experimentSeed) => LevelSpawnConfig(
    seed: experimentSeed ^ 0x9e377902,
    levelWidth: RiseTogetherLevel.horizontalWidth,
    levelHeight: verticalHeight,
    spawns: const [
      SpawnInstance(
        objectType: 'control_reversal_zone',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.4,
          maxVerticalProgress: 0.6,
          minHorizontalPosition: 0.0,
          maxHorizontalPosition: 0.0,
        ),
        customParams: {'zoneHeightMeters': 0.3 * GameGeometry.scale},
      ),
    ],
  );

  const Level2();
}

class Level3 extends RiseTogetherLevel {
  @override
  final double verticalMultiplier = 5.0;

  @override
  LevelSpawnConfig? spawnConfigForSeed(int experimentSeed) => LevelSpawnConfig(
    seed: experimentSeed ^ 0x9e377903,
    levelWidth: RiseTogetherLevel.horizontalWidth,
    levelHeight: verticalHeight,
    spawns: const [
      SpawnInstance(
        objectType: 'powerup_width',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.1,
          maxVerticalProgress: 0.2,
        ),
        customParams: {'widthMultiplier': 1.3},
      ),
      SpawnInstance(
        objectType: 'control_reversal_zone',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.3,
          maxVerticalProgress: 0.7,
          minHorizontalPosition: 0.0,
          maxHorizontalPosition: 0.0,
        ),
        customParams: {'zoneHeightMeters': 0.4 * GameGeometry.scale},
      ),
    ],
  );

  const Level3();
}

class Level4 extends RiseTogetherLevel {
  @override
  final double verticalMultiplier = 7.0;

  @override
  LevelSpawnConfig? spawnConfigForSeed(int experimentSeed) => LevelSpawnConfig(
    seed: experimentSeed ^ 0x9e377904,
    levelWidth: RiseTogetherLevel.horizontalWidth,
    levelHeight: verticalHeight,
    spawns: const [
      SpawnInstance(
        objectType: 'fatal',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.1,
          maxVerticalProgress: 0.3,
        ),
      ),
      SpawnInstance(
        objectType: 'powerup_width',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.3,
          maxVerticalProgress: 0.4,
        ),
        customParams: {'widthMultiplier': 1.3},
      ),
      SpawnInstance(
        objectType: 'control_reversal_zone',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.5,
          maxVerticalProgress: 0.7,
          minHorizontalPosition: 0.0,
          maxHorizontalPosition: 0.0,
        ),
        customParams: {'zoneHeightMeters': 0.4 * GameGeometry.scale},
      ),
    ],
  );

  const Level4();
}

// Levels 5 onwards are laid out with LevelSpawnConfig.slotted, which rules out
// overlapping objects by construction (Level 6 used to stack a zone, a fatal
// obstacle and a second zone in the same stretch). They share one height and
// get harder by density and mix -- more fatal obstacles and zones per level --
// rather than by length. Levels 1-4 are unchanged; see docs/DATA_COMPAT.md.

typedef LevelObjectSpec = (String, Map<String, dynamic>?);

const LevelObjectSpec _fatal = ('fatal', null);
const LevelObjectSpec _up = ('powerup_width', {'widthMultiplier': 1.3});
const LevelObjectSpec _down = ('powerdown_width', {'widthMultiplier': 0.75});
const LevelObjectSpec _zone = (
  'control_reversal_zone',
  {'zoneHeightMeters': 0.4 * GameGeometry.scale},
);
const LevelObjectSpec _tallZone = (
  'control_reversal_zone',
  {'zoneHeightMeters': 0.5 * GameGeometry.scale},
);

/// A level laid out bottom-to-top from [objects]; see [LevelSpawnConfig.slotted].
abstract class SlottedLevel extends RiseTogetherLevel {
  const SlottedLevel();

  int get seedSalt;
  List<LevelObjectSpec> get objects;

  @override
  LevelSpawnConfig? spawnConfigForSeed(int experimentSeed) =>
      LevelSpawnConfig.slotted(
        seed: experimentSeed ^ seedSalt,
        levelWidth: RiseTogetherLevel.horizontalWidth,
        levelHeight: verticalHeight,
        objects: objects,
      );
}

/// 9 objects: 3 fatal, 2 zones, 2 up, 2 down.
class Level5 extends SlottedLevel {
  @override
  final double verticalMultiplier = 10.0;
  @override
  int get seedSalt => 0x9e377905;
  @override
  List<LevelObjectSpec> get objects => const [
    _up, _fatal, _down, _zone, _fatal, _up, _down, _zone, _fatal, //
  ];
  const Level5();
}

/// 12 objects: 4 fatal, 3 zones, 3 up, 2 down.
class Level6 extends SlottedLevel {
  @override
  final double verticalMultiplier = 15.0;
  @override
  int get seedSalt => 0x9e377906;
  @override
  List<LevelObjectSpec> get objects => const [
    _up, _fatal, _down, _zone, _fatal, _up, //
    _fatal, _zone, _down, _up, _fatal, _zone, //
  ];
  const Level6();
}

/// 14 objects: 5 fatal, 3 zones, 3 up, 3 down.
class Level7 extends SlottedLevel {
  @override
  final double verticalMultiplier = 15.0;
  @override
  int get seedSalt => 0x9e377907;
  @override
  List<LevelObjectSpec> get objects => const [
    _up, _fatal, _down, _zone, _fatal, _up, _fatal, //
    _down, _zone, _fatal, _up, _down, _zone, _fatal, //
  ];
  const Level7();
}

/// 16 objects: 6 fatal, 4 zones, 3 up, 3 down.
class Level8 extends SlottedLevel {
  @override
  final double verticalMultiplier = 15.0;
  @override
  int get seedSalt => 0x9e377908;
  @override
  List<LevelObjectSpec> get objects => const [
    _up, _fatal, _down, _zone, _fatal, _fatal, _up, _zone, //
    _down, _fatal, _zone, _up, _fatal, _down, _tallZone, _fatal, //
  ];
  const Level8();
}

/// 18 objects: 7 fatal, 4 zones, 3 up, 4 down.
class Level9 extends SlottedLevel {
  @override
  final double verticalMultiplier = 15.0;
  @override
  int get seedSalt => 0x9e377909;
  @override
  List<LevelObjectSpec> get objects => const [
    _up, _fatal, _down, _zone, _fatal, _fatal, _up, _down, _zone, //
    _fatal, _down, _tallZone, _fatal, _up, _fatal, _zone, _down, _fatal, //
  ];
  const Level9();
}

/// 20 objects: 8 fatal, 5 zones, 3 up, 4 down.
class Level10 extends SlottedLevel {
  @override
  final double verticalMultiplier = 15.0;
  @override
  int get seedSalt => 0x9e37790a;
  @override
  List<LevelObjectSpec> get objects => const [
    _up, _fatal, _down, _zone, _fatal, _fatal, _up, _zone, _down, _fatal, //
    _fatal, _tallZone, _down, _up, _fatal, _zone, _fatal, _down, _tallZone,
    _fatal, //
  ];
  const Level10();
}

/// A level the player built (see `lib/src/levels/custom_level.dart`).
///
/// Objects sit exactly where the author put them; the seed is ignored, so a
/// level plays the same every time and on every device.
class CustomRiseTogetherLevel extends RiseTogetherLevel {
  CustomRiseTogetherLevel(this.data);

  final CustomLevel data;

  @override
  double get verticalMultiplier => data.heightMultiplier;

  @override
  LevelSpawnConfig? spawnConfigForSeed(int experimentSeed) {
    if (data.objects.isEmpty) return null;
    final height = verticalHeight;
    return LevelSpawnConfig.fixed(
      levelWidth: RiseTogetherLevel.horizontalWidth,
      levelHeight: height,
      placements: [
        for (final o in data.objects)
          SpawnPlacement(
            SpawnInstance(
              objectType: o.type.spawnType,
              constraints: PlacementConstraints(
                minVerticalProgress: o.y / height,
                maxVerticalProgress: o.y / height,
                minHorizontalPosition: o.x,
                maxHorizontalPosition: o.x,
              ),
              customParams: {
                if (o.type.param case final spec?) spec.key: ?o.param,
              },
            ),
            // World y is negative going up.
            Vector2(o.x, -o.y),
            Vector2(o.size.$1, o.size.$2),
          ),
      ],
    );
  }
}
