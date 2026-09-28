import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:rise_together_game/src/attributes/positionable.dart';
import 'package:rise_together_game/src/attributes/resetable.dart';
import 'package:rise_together_game/src/components/level_object.dart';
import 'package:rise_together_game/src/components/wall.dart';
// import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/rise_together_world.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';

class Ball extends BodyComponent<RiseTogetherGameBase>
    with
        ContactCallbacks,
        AppLogging,
        AppSettings,
        PositionableBodyComponent,
        Resetable {
  bool isMoving = false;
  bool isRising = false;
  final double radius;
  @override
  RiseTogetherWorld get world => _world;
  final RiseTogetherWorld _world;

  // bool kinematic = false;

  Ball(this._world, {required this.radius, super.paint, Vector2? pos})
    : startPosition = pos ?? Vector2.zero(),
      super();

  @override
  Future<void> onLoad() async {
    priority = 1;
    appLog.fine(appSettings.toString());
    appLog.fine(
      'Ball onLoad called with radius: $radius, startPosition: $startPosition',
    );
    await super.onLoad();
  }

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: startPosition,
      linearDamping: 1.0,
      angularDamping: 0.8,
      // forge2d box2d v3
      gravityScale: 1.0,
      // forge2d box2d v2
      // Gravity is an acceleration, so it scales with the world. Note it is
      // applied in two places -- here per-body, and on the world itself in
      // RiseTogetherGameBase -- and both must use the same scaled value.
      // gravityOverride: Vector2(
      //   0,
      //   GameGeometry.gravity(appSettings['physics.gravity']),
      // ),
      // userData: this,
    );
    // forge2d box2d v3
    final shape = Circle(radius: radius);
    final fixtureDef = ShapeDef(
      material: SurfaceMaterial(friction: 0.5, restitution: 0.0),
      density: 5.0,
      enableContactEvents: true,
      enableSensorEvents: true,
      userData: this,
    );
    // forge2d box2d v2
    // final fixtureDef = FixtureDef(
    //   CircleShape()..radius = radius,
    //   density: 5.0,
    //   friction: 0.5,
    //   restitution: 0.0,
    // );

    final sprite = Sprite(gameRef.images.fromCache('assets/images/ball.png'));
    add(
      SpriteComponent(
        sprite: sprite,
        size: Vector2(radius * 2, radius * 2),
        anchor: Anchor.center,
      ),
    );
    renderBody = false;
    // forge2d box2d v3
    return _world.createBody(bodyDef)..createShape(shape, fixtureDef);
    // forge2d box2d v2
    // return _world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  final Vector2 startPosition;

  @override
  void update(double dt) {
    super.update(dt);
    if (hasPendingTransforms) {
      applyPendingTransforms();
    }
  }

  /// Return the ball to rest at its spawn position.
  ///
  /// Applied synchronously, for the same reason as [Paddle.clearMotion]: a
  /// staged transform can be cancelled before it ever lands (a level object
  /// consumed in the same frame calls `cancelPendingTransforms()` on its way
  /// through `updatePaddleShape`), and anything reading the body in between --
  /// the physics broadcast above all -- would see the pre-reset pose.
  ///
  /// Safe from a contact callback: Forge2DWorld.update() dispatches contact
  /// events after physicsWorld.step() has returned, not during it.
  void clearMotion() {
    isMoving = false;
    isRising = false;
    stopMovement();
    cancelPendingTransforms();
    setPosition(startPosition);
    applyPendingTransforms();
  }

  @override
  void reset() {
    appLog.fine('Resetting ball to start position: $startPosition');
    clearMotion();
  }

  void _handleWallContact(Wall wall) {
    if (wall.isLevelEnd) {
      // Ball reached the top wall - level complete!
      appLog.info('Ball reached level end wall');
      _world.controller.onLevelCompleted?.call();
    } else if (wall.isFatal) {
      // Ball hit a fatal wall - restart level
      appLog.info('Ball hit fatal wall');
      _world.restartLevel();
    }
  }

  @override
  void beginContact(Object other, Contact contact) {
    appLog.fine('Ball beginContact');

    if (other is Wall) {
      _handleWallContact(other);
      return;
    }
    if (other is LevelObject) {
      other.onBallContact(this);
      return;
    }
    appLog.fine('Ball contact with unknown object: ${other.runtimeType}');
  }

  @override
  void endContact(Object other, Contact contact) {
    appLog.fine('Ball endContact with ${other.runtimeType}');
    if (other is LevelObject) {
      other.onBallEndContact(this);
    }
  }
}
