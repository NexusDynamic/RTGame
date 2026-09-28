import 'package:flame/components.dart';
import 'package:rise_together_game/src/components/level_object.dart';
import 'package:rise_together_game/src/game/rise_together_world.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Registry of the level objects currently live in a world.
///
/// This was previously an object *pool*, but the pooling never functioned and
/// could not be repaired in place:
///
///  * `acquire` keyed on the spawn type (`'fatal'`, `'powerup_width'`) while
///    `release` keyed on `runtimeType` (`'fatalobstacle'`, …). The buckets
///    never intersected, so nothing was ever reused and released objects
///    accumulated forever, each retaining the world and its sprite.
///  * Reuse would have read `body.isAwake` on a body that
///    `BodyComponent.onRemove` had already destroyed.
///  * `prewarm` built objects that never ran `onLoad`, leaving `body` an
///    uninitialised `late` field.
///  * `LevelObject.position` is `final` and `createBody()` reads it, so a
///    remounted object would rebuild its body at its original spawn point —
///    silently breaking deterministic obstacle placement across clients.
///
/// Level objects are created per level load, not per frame, so pooling bought
/// nothing. What the rest of the code actually depends on is the set of active
/// objects, which is all this class now provides.
class LevelObjectPool with AppLogging {
  final RiseTogetherWorld world;
  final Set<LevelObject> _activeObjects = {};

  /// Live view of the active objects.
  ///
  /// Deliberately not a defensive copy: this is read every frame from
  /// [RiseTogetherWorld.update], where the previous `toISet()` allocated a full
  /// immutable-set copy per world per frame even with zero objects. Callers
  /// that mutate during iteration must snapshot with `.toList()` themselves —
  /// see [releaseAll].
  Iterable<LevelObject> get activeObjects => _activeObjects;

  int get activeCount => _activeObjects.length;

  LevelObjectPool(this.world);

  /// Create a level object and register it as active.
  LevelObject acquire({
    required String objectType,
    required Vector2 position,
    required Vector2 size,
    Map<String, dynamic>? customParams,
  }) {
    final object = createLevelObject(
      world,
      objectType,
      position,
      size,
      customParams,
    );
    _activeObjects.add(object);
    appLog.fine('Created $objectType');
    return object;
  }

  /// Deregister an object and remove it from the world.
  void release(LevelObject object) {
    if (!_activeObjects.remove(object)) {
      appLog.warning('Attempted to release object not in active set');
      return;
    }

    if (object.isMounted) {
      object.removeFromParent();
    }
  }

  /// Release every active object.
  void releaseAll() {
    // Snapshot: release() mutates _activeObjects.
    for (final object in _activeObjects.toList()) {
      release(object);
    }
    appLog.fine('Released all active level objects');
  }

  /// Drop all references without touching the world. For teardown paths where
  /// the components are being disposed anyway.
  void clear() {
    _activeObjects.clear();
    appLog.fine('Cleared level object registry');
  }
}

/// Build a level object from its spawn type string, e.g. `'fatal'`.
///
/// The one place type strings become objects: built-in level configs and
/// custom levels (see `CustomObjectType.spawnType`) both come through here.
/// Throws [ArgumentError] for an unknown type.
LevelObject createLevelObject(
  RiseTogetherWorld world,
  String objectType,
  Vector2 position,
  Vector2 size,
  Map<String, dynamic>? customParams,
) {
  switch (objectType.toLowerCase()) {
    case 'fatal':
    case 'fatalobstacle':
      return FatalObstacle(world, position: position, size: size);

    case 'powerup_width':
    case 'paddlewidthpowerup':
      final multiplier =
          (customParams?['widthMultiplier'] as num?)?.toDouble() ?? 1.3;
      return PaddleWidthPowerup(
        world,
        position: position,
        size: size,
        widthMultiplier: multiplier,
      );

    case 'powerdown_width':
    case 'paddlewidthpowerdown':
      final multiplier =
          (customParams?['widthMultiplier'] as num?)?.toDouble() ?? 0.7;
      return PaddleWidthPowerdown(
        world,
        position: position,
        size: size,
        widthMultiplier: multiplier,
      );

    case 'control_reversal':
    case 'controlreversaltrigger':
      final duration = (customParams?['duration'] as num?)?.toDouble() ?? 10.0;
      return ControlReversalTrigger(
        world,
        position: position,
        size: size,
        duration: duration,
      );

    case 'control_reversal_zone':
    case 'controlreversalzone':
      return ControlReversalZone(world, position: position, size: size);

    default:
      throw ArgumentError('Unknown object type: $objectType');
  }
}
