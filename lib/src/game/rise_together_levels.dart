import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/level_spawn_config.dart';

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

class Level5 extends RiseTogetherLevel {
  @override
  final double verticalMultiplier = 10.0;

  @override
  LevelSpawnConfig? spawnConfigForSeed(int experimentSeed) => LevelSpawnConfig(
    seed: experimentSeed ^ 0x9e377905,
    levelWidth: RiseTogetherLevel.horizontalWidth,
    levelHeight: verticalHeight,
    spawns: const [
      SpawnInstance(
        objectType: 'fatal',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.05,
          maxVerticalProgress: 0.15,
        ),
      ),
      SpawnInstance(
        objectType: 'powerdown_width',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.15,
          maxVerticalProgress: 0.25,
        ),
        customParams: {'widthMultiplier': 0.7},
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
          minVerticalProgress: 0.45,
          maxVerticalProgress: 0.55,
          minHorizontalPosition: 0.0,
          maxHorizontalPosition: 0.0,
        ),
        customParams: {'zoneHeightMeters': 0.4 * GameGeometry.scale},
      ),
      SpawnInstance(
        objectType: 'fatal',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.6,
          maxVerticalProgress: 0.7,
        ),
      ),
      SpawnInstance(
        objectType: 'control_reversal_zone',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.75,
          maxVerticalProgress: 0.85,
          minHorizontalPosition: 0.0,
          maxHorizontalPosition: 0.0,
        ),
        customParams: {'zoneHeightMeters': 0.4 * GameGeometry.scale},
      ),
    ],
  );

  const Level5();
}

class Level6 extends RiseTogetherLevel {
  @override
  final double verticalMultiplier = 15.0;

  @override
  LevelSpawnConfig? spawnConfigForSeed(int experimentSeed) => LevelSpawnConfig(
    seed: experimentSeed ^ 0x9e377906,
    levelWidth: RiseTogetherLevel.horizontalWidth,
    levelHeight: verticalHeight,
    spawns: const [
      SpawnInstance(
        objectType: 'powerup_width',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.03,
          maxVerticalProgress: 0.08,
        ),
        customParams: {'widthMultiplier': 1.4},
      ),
      SpawnInstance(
        objectType: 'fatal',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.1,
          maxVerticalProgress: 0.15,
        ),
      ),
      SpawnInstance(
        objectType: 'control_reversal_zone',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.3,
          maxVerticalProgress: 0.4,
          minHorizontalPosition: 0.0,
          maxHorizontalPosition: 0.0,
        ),
        customParams: {'zoneHeightMeters': 0.4 * GameGeometry.scale},
      ),
      SpawnInstance(
        objectType: 'powerdown_width',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.28,
          maxVerticalProgress: 0.35,
          minHorizontalPosition: 0.0,
          maxHorizontalPosition: 0.0,
        ),
        customParams: {'widthMultiplier': 0.65},
      ),
      SpawnInstance(
        objectType: 'fatal',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.4,
          maxVerticalProgress: 0.45,
        ),
      ),
      SpawnInstance(
        objectType: 'powerup_width',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.48,
          maxVerticalProgress: 0.55,
        ),
        customParams: {'widthMultiplier': 1.35},
      ),
      SpawnInstance(
        objectType: 'control_reversal_zone',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.65,
          maxVerticalProgress: 0.7,
          minHorizontalPosition: 0.0,
          maxHorizontalPosition: 0.0,
        ),
        customParams: {'zoneHeightMeters': 0.6 * GameGeometry.scale},
      ),
      SpawnInstance(
        objectType: 'fatal',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.68,
          maxVerticalProgress: 0.73,
        ),
      ),
      SpawnInstance(
        objectType: 'powerdown_width',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.76,
          maxVerticalProgress: 0.82,
        ),
        customParams: {'widthMultiplier': 0.75},
      ),
      SpawnInstance(
        objectType: 'control_reversal_zone',
        constraints: PlacementConstraints(
          minVerticalProgress: 0.6,
          maxVerticalProgress: 0.7,
        ),
        customParams: {'zoneHeightMeters': 0.25 * GameGeometry.scale},
      ),
    ],
  );

  const Level6();
}
