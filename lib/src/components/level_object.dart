import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:rise_together_game/src/attributes/resetable.dart';
import 'package:rise_together_game/src/components/zone_component.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/game/rise_together_world.dart';
import 'package:rise_together_game/src/components/ball.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Base class for all interactive level objects
///
/// Provides physics body, collision detection, and lifecycle management
abstract class LevelObject extends BodyComponent<RiseTogetherGameBase>
    with AppLogging, Resetable {
  @override
  RiseTogetherWorld get world => _world;
  final RiseTogetherWorld _world;

  @override
  final Vector2 position;
  final Vector2 size;
  final String? spritePath;
  final Component? customComponent;
  late final Component _component;

  /// Unique spawn ID for network synchronization (deterministic across devices)
  int? spawnId;

  /// Whether this object has been consumed/used
  bool _isConsumed = false;
  bool get isConsumed => _isConsumed;

  void Function()? _beforeRemove;
  void Function()? get beforeRemove => _beforeRemove;

  /// Reset consumed state (for object pooling)
  void resetForReuse() {
    _isConsumed = false;
    spawnId = null;
  }

  @override
  void reset() {
    resetForReuse();
  }

  LevelObject(
    this._world, {
    required this.position,
    required this.size,
    this.spritePath,
    this.customComponent,
  }) {
    if (spritePath == null && customComponent == null) {
      throw ArgumentError(
        'Either spritePath or customComponent must be provided',
      );
    }
  }

  @override
  Future<void> onLoad() async {
    // Below the opponent ghost and previous-best marks (priority 0): a zone's
    // stripe is opaque and was added after them on every level load, so at
    // equal priority it hid the translucent ghost entirely. The level backdrop
    // is drawn by RiseTogetherWorld.render before any child, so it stays under.
    priority = -1;
    await super.onLoad();

    if (spritePath != null) {
      // Load and add sprite
      appLog.info('Loading sprite: $spritePath');
      final sprite = await gameRef.loadSprite(spritePath!);
      _component = SpriteComponent(
        sprite: sprite,
        size: size,
        anchor: Anchor.center,
      );
    } else {
      appLog.info('Using custom component: $customComponent');
      _component = customComponent!;
    }
    add(_component);

    appLog.fine('$runtimeType spawned at $position with size $size');
  }

  @override
  Body createBody() {
    // Static sensor body (no physical collision, just detection)
    final bodyDef = BodyDef(
      type: BodyType.static,
      position: position,
      // forge2d box2d v3
      gravityScale: 0,
      // allowFastRotation: false,
      // forge2d box2d v2
      // userData: this,
    );

    // forge2d box2d v3
    final shape = Polygon.box(size.x / 2, size.y / 2);
    // forge2d box2d v2
    // final shape = PolygonShape()
    //   ..setAsBox(size.x / 2, size.y / 2, Vector2.zero(), 0);

    // forge2d box2d v3
    //
    // box2d v3 event flags, which bit us on migration:
    //   - `isSensor` alone generates NO events. Sensor event generation is off
    //     by default, even for sensors.
    //   - `enableContactEvents` is *ignored* for sensors, so it is not the flag
    //     to reach for here — `enableSensorEvents` is.
    //   - Both the sensor shape and the visiting shape need
    //     `enableSensorEvents` (Ball already sets it).
    // BodyComponent.createBody() sets these for you, but every component in
    // this project overrides createBody, so we set them by hand.
    final fixtureDef = ShapeDef(
      material: SurfaceMaterial(friction: 0),
      userData: this,
      isSensor:
          true, // Sensor = triggers collision callbacks but no physical response
      enableSensorEvents: true,
    );
    // forge2d box2d v2
    // final fixtureDef = FixtureDef(
    //   shape,
    //   isSensor:
    //       true, // Sensor = triggers collision callbacks but no physical response
    // );

    renderBody = false;
    // forge2d box2d v3
    return _world.createBody(bodyDef)..createShape(shape, fixtureDef);
    // forge2d box2d v2
    // return _world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  /// Handle ball contact - implemented by subclasses
  void onBallContact(Ball ball);

  /// Called when ball exits this object's sensor area. Override to handle.
  void onBallEndContact(Ball ball) {}

  /// Mark object as consumed and remove from world
  void consume() {
    if (_isConsumed) return;
    _isConsumed = true;

    appLog.fine('$runtimeType consumed at spawnId=$spawnId');

    // Notify world of consumption for network synchronization
    if (spawnId != null) {
      _world.consumeLevelObject(spawnId!);
    } else {
      appLog.warning(
        'LevelObject consumed without spawnId - cannot sync across network',
      );
    }

    removeFromParent();
  }
}

/// Fatal obstacle - resets level when ball makes contact
class FatalObstacle extends LevelObject {
  FatalObstacle(
    super.world, {
    required super.position,
    required super.size,
    super.spritePath = 'assets/images/obstacle_fatal.png',
  });

  @override
  void onBallContact(Ball ball) {
    appLog.info('Ball hit fatal obstacle at $position');
    // Not consumed — obstacle persists for level lifetime
    _world.restartLevel();
  }

  @override
  // ignore: unnecessary_overrides
  void reset() {
    super.reset();
  }
}

/// Paddle width powerup - increases paddle width when consumed
class PaddleWidthPowerup extends LevelObject {
  final double widthMultiplier;

  PaddleWidthPowerup(
    super.world, {
    required super.position,
    required super.size,
    this.widthMultiplier = 1.3, // 30% wider
    super.spritePath = 'assets/images/powerup_paddle_width.png',
  });

  @override
  void onBallContact(Ball ball) {
    appLog.info('Paddle width powerup collected at $position');
    _beforeRemove = () {
      _world.paddle.applyWidthMultiplier(widthMultiplier, resetPosition: false);
    };
    consume();
  }

  @override
  // ignore: unnecessary_overrides
  void reset() {
    super.reset();
  }
}

/// Paddle width powerdown - decreases paddle width when consumed
class PaddleWidthPowerdown extends LevelObject {
  final double widthMultiplier;

  PaddleWidthPowerdown(
    super.world, {
    required super.position,
    required super.size,
    this.widthMultiplier = 0.7, // 30% narrower
    super.spritePath = 'assets/images/powerdown_paddle_width.png',
  });

  @override
  void onBallContact(Ball ball) {
    appLog.info('Paddle width powerdown collected at $position');
    _beforeRemove = () {
      _world.paddle.applyWidthMultiplier(widthMultiplier, resetPosition: false);
    };
    consume();
  }

  @override
  // ignore: unnecessary_overrides
  void reset() {
    super.reset();
  }
}

/// Control reversal trigger - flips team inputs for a duration (legacy, one-shot)
class ControlReversalTrigger extends LevelObject {
  final double duration;

  ControlReversalTrigger(
    super.world, {
    required super.position,
    required super.size,
    this.duration = 10.0, // seconds
    super.spritePath = 'assets/images/trigger_control_reversal.png',
  });

  @override
  void onBallContact(Ball ball) {
    appLog.info('Control reversal triggered at $position for ${duration}s');
    _beforeRemove = () {
      _world.controller.activateControlReversal(duration);
    };
    consume();
  }

  @override
  // ignore: unnecessary_overrides
  void reset() {
    super.reset();
  }
}

/// Control reversal zone - reversal is active while ball is inside the zone.
///
/// Ball entering the zone activates reversal; ball exiting deactivates it.
/// The zone is NOT consumed — it persists for the level's lifetime.
class ControlReversalZone extends LevelObject {
  ControlReversalZone(
    super.world, {
    required super.position,
    required super.size,
  }) : super(customComponent: ZoneComponent(size: size));

  @override
  void onBallContact(Ball ball) {
    appLog.info('Ball entered control reversal zone at $position');
    _world.controller.activateControlReversalZone();
    // NOT consumed — zone persists for level lifetime
  }

  @override
  void onBallEndContact(Ball ball) {
    appLog.info('Ball exited control reversal zone at $position');
    _world.controller.deactivateControlReversal();
  }

  @override
  // ignore: unnecessary_overrides
  void reset() {
    super.reset();
  }
}
