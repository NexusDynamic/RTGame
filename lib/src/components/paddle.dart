import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/attributes/positionable.dart';
import 'package:rise_together_game/src/attributes/resetable.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/game/rise_together_world.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';

class Paddle extends BodyComponent<RiseTogetherGameBase>
    with AppLogging, AppSettings, PositionableBodyComponent, Resetable {
  final Vector2 _start;
  final Vector2 _end;

  // Halfwidth
  double get _w => (_end.x - _start.x).abs() / 2;
  // halfheight
  double get _h => (_end.y - _start.y).abs() / 2;

  late BodyDef _bodyDef;
  // forge2d box2d v3
  late ShapeDef _fixtureDef;
  late Shape _fixture;
  // forge2d box2d v2
  // late FixtureDef _fixtureDef;
  // late Fixture _fixture;

  /// Position valuenotifier for paddle
  final ValueNotifier<double> positionNotifier = ValueNotifier(0.0);
  @override
  RiseTogetherWorld get world => _world;

  final RiseTogetherWorld _world;

  double thrustLeft = 0.0;
  double thrustRight = 0.0;

  // Public getter for starting position.
  //
  // This is the CENTRE of the paddle bar, which is also the body origin. The
  // fixture below is built origin-centred (setAsBoxXY), so shape coordinates
  // are body-local and must not repeat the offset that is already carried by
  // the body position -- doing so double-counts it and silently shifts the
  // collision surface. (That was the previous behaviour: the surface sat at
  // y = -0.02 rather than the -0.03 that _start/_end describe.)
  Vector2 get startPosition => Vector2(_start.x + _w, _start.y - _h);

  // Store the original paddle width (without any multipliers applied)
  late double _originalWidth;

  // Track width multipliers separately:
  // - Base multiplier from configuration (persists)
  // - Temporary multiplier from obstacle effects (resets on level restart)
  double _baseWidthMultiplier; // From settings
  double _tempWidthMultiplier = 1.0; // From obstacles

  // Total multiplier is the product of both
  double get widthMultiplier => _baseWidthMultiplier * _tempWidthMultiplier;

  Paddle(
    this._world,
    this._start,
    this._end, {
    double baseWidthMultiplier = 1.0,
  }) : _baseWidthMultiplier = baseWidthMultiplier;

  @override
  Future<void> onLoad() async {
    // Store the original width (full width = 2 * _w)
    // This is the configured width, which may include the base multiplier
    // We need to divide by base multiplier to get the TRUE original
    _originalWidth = (_end.x - _start.x).abs() / _baseWidthMultiplier;

    priority = 1;

    appLog.info(
      'Paddle initialized: width=${(_end.x - _start.x).abs()}, base multiplier=$_baseWidthMultiplier, original width=$_originalWidth',
    );

    // add a circle component to represent the anchor point. ..this is visible
    // but does not interact with physics.
    //
    // Children render in body-local space and the body origin is the paddle
    // centre, so this is Vector2.zero(). It previously repeated the _start/_h
    // offsets, which put the marker a half-thickness off the bar it marks.
    add(
      CircleComponent(
        radius: GameGeometry.anchorRadius,
        paint: Paint()..color = const Color.fromARGB(149, 26, 26, 26),
        anchor: Anchor.center,
        position: Vector2.zero(),
      ),
    );
    appLog.fine('Creating paddle body with w: $_w, h: $_h');

    // A box, not a segment: a zero-thickness body is the worst case for box2d
    // v3 speculative contacts (tolerance is 4 * linearSlop, which at this scale
    // is wider than the paddle was). setAsBoxXY is origin-centred, matching the
    // body origin -- see startPosition.
    // forge2d box2d v3
    final shape = Polygon.box(_w, _h);

    // forge2d box2d v2
    // final shape = PolygonShape()..setAsBoxXY(_w, _h);

    // forge2d box2d v3
    _fixtureDef = ShapeDef(
      material: SurfaceMaterial(friction: 20.0, rollingResistance: 0.0),
      density: 1.0,
    );
    // forge2d box2d v2
    // _fixtureDef = FixtureDef(shape, friction: 20.0, density: 1.0);

    _bodyDef = BodyDef(
      type: BodyType.kinematic,
      position: startPosition,
      // forge2d box2d v3
      gravityScale: 0,
      // forge2d box2d v2
      // gravityOverride: Vector2.zero(),
    );
    // fill is correct for a polygon fixture: BodyComponent dispatches those to
    // renderPolygon/drawPath. (An EdgeShape instead goes to drawLine, which is
    // a stroking call and ignores fill -- with strokeWidth defaulting to 0 that
    // renders as a 1px hairline at any zoom, which is what this used to do.)
    paint = Paint()
      ..color = const Color.fromARGB(255, 0, 187, 255)
      ..style = PaintingStyle.fill;
    positionNotifier.value = _bodyDef.position.y;
    appLog.fine('Paddle position: ${_bodyDef.position}');
    appLog.fine('World: ${_world.hashCode}');
    body = _world.createBody(_bodyDef);
    // forge2d box2d v3
    _fixture = body.createShape(shape, _fixtureDef);
    // forge2d box2d v2
    // _fixture = body.createFixture(_fixtureDef);
    await super.onLoad();
  }

  @override
  Body createBody() {
    return body;
  }

  /// Set thrust values from action system
  double setThrust(double leftThrust, double rightThrust) {
    thrustLeft = leftThrust;
    thrustRight = rightThrust;
    // if (leftThrust > 0 || rightThrust > 0) {
    //   print('PADDLE DEBUG: setThrust called with left=$leftThrust, right=$rightThrust on world ${world.pos}');
    // }
    return thrustLeft + thrustRight;
  }

  void updatePaddleShape(
    Vector2 newStart,
    Vector2 newEnd, {
    bool resetPosition = true,
  }) {
    appLog.info("current paddle angle: ${body.angle}");
    stopMovement();
    cancelPendingTransforms();

    _start.setFrom(newStart);
    _end.setFrom(newEnd);

    // Update the fixture to match new width, in place -- no fixture recreation.
    // forge2d box2d v3
    _fixture.destroy();
    final shape = Polygon.box(_w, _h);
    _fixture = body.createShape(shape, _fixtureDef);
    // forge2d box2d v2
    // (_fixture.shape as PolygonShape).setAsBoxXY(_w, _h);

    if (resetPosition) {
      // forge2d box2d v3
      body.setTransform(startPosition, Rot.fromAngle(0));
      // forge2d box2d v2
      // body.setTransform(startPosition, 0);
      positionNotifier.value = startPosition.y;
      appLog.info('Reset paddle position to: $startPosition');
    }
    appLog.info(
      'Updated paddle shape to w: $_w, h: $_h at position: ${body.position}',
    );
    appLog.info("new paddle angle: ${body.angle}");
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (hasPendingTransforms) {
      applyPendingTransforms();
      // Follower (participant) path: the body is moved by network transforms
      // rather than by the solver, so nothing else publishes the new position.
      // Without this, positionNotifier stays pinned at its start value and
      // anything bound to it (camera follow, indicators) never tracks.
      positionNotifier.value = body.position.y;
      return;
    }
    // Only update if kinematic, otherwise it is updated by direct transform
    if (!isKinematic) {
      return;
    }
    // If no thrust, stop movement
    if (thrustLeft == 0.0 && thrustRight == 0.0) {
      // forge2d box2d v2
      // body.clearForces();
      body.linearVelocity = Vector2.zero();
      body.angularVelocity = 0.0;
      positionNotifier.value = body.position.y;
      return;
    }

    // Calculate rotation amount based on thrust difference
    double rotationAmount = 0.0;
    final degreesPerSecond = 1.0;
    final rotationMultiplier = appSettings.getDouble(
      'physics.rotation_multiplier',
    );
    if (thrustLeft > 0) {
      rotationAmount += degreesPerSecond * rotationMultiplier * dt * thrustLeft;
    }
    if (thrustRight > 0) {
      rotationAmount -=
          degreesPerSecond * rotationMultiplier * dt * thrustRight;
    }

    // Calculate upward velocity based on total thrust
    // thrust_multiplier is used directly as a linear velocity, so it is in the
    // length domain and must be scaled. rotation_multiplier above is angular
    // and must not be.
    final totalThrust = thrustLeft + thrustRight;
    final thrustMultiplier = GameGeometry.velocity(
      appSettings.getDouble('physics.thrust_multiplier'),
    );
    final upwardVelocity = -1.0 * thrustMultiplier * totalThrust;

    // Apply the rotation and upward velocity
    body.setTransform(
      body.position,
      // forge2d box2d v3
      Rot.fromAngle(body.angle + rotationAmount),
      // forge2d box2d v2
      // body.angle + rotationAmount,
    );
    body.linearVelocity = Vector2(0.0, upwardVelocity);

    // Limit rotation angle
    if (body.angle < -1.3) {
      body.angularVelocity = 0.0;
      // forge2d box2d v3
      body.setTransform(body.position, Rot.fromAngle(-1.3));
      // forge2d box2d v2
      // body.setTransform(body.position, -1.3);
    } else if (body.angle > 1.3) {
      body.angularVelocity = 0.0;
      // forge2d box2d v3
      body.setTransform(body.position, Rot.fromAngle(1.3));
      // forge2d box2d v2
      // body.setTransform(body.position, 1.3);
    }
    applyPendingTransforms();
    positionNotifier.value = body.position.y;
  }

  /// Apply temporary width multiplier to paddle (for obstacle effects)
  /// This is cumulative and resets when level restarts
  void applyWidthMultiplier(double multiplier, {bool resetPosition = true}) {
    _tempWidthMultiplier *= multiplier;
    appLog.info(
      'Applying temp width multiplier: $multiplier (temp: $_tempWidthMultiplier, base: $_baseWidthMultiplier, total: $widthMultiplier)',
    );

    _updatePaddleWidth(resetPosition: resetPosition);
  }

  /// Set base width multiplier from configuration
  /// This persists across level restarts
  void setBaseWidthMultiplier(double multiplier) {
    _baseWidthMultiplier = multiplier;
    appLog.info(
      'Setting base width multiplier: $_baseWidthMultiplier (temp: $_tempWidthMultiplier, total: $widthMultiplier)',
    );

    _updatePaddleWidth();
  }

  /// Synchronize total width multiplier from server (for participants)
  /// This updates the temporary multiplier based on received total
  void syncWidthMultiplier(double totalMultiplier) {
    if ((widthMultiplier - totalMultiplier).abs() < 0.001) {
      return; // Already in sync
    }

    appLog.info(
      'Syncing paddle width: received total=$totalMultiplier, current total=$widthMultiplier (base=$_baseWidthMultiplier, temp=$_tempWidthMultiplier)',
    );

    // Calculate new temp multiplier: total = base * temp, so temp = total / base
    final newTemp = totalMultiplier / _baseWidthMultiplier;
    if ((_tempWidthMultiplier - newTemp).abs() > 0.001) {
      final oldTemp = _tempWidthMultiplier;
      _tempWidthMultiplier = newTemp;
      appLog.info(
        'Updated temp multiplier: $oldTemp -> $_tempWidthMultiplier (new total: $widthMultiplier)',
      );
      _updatePaddleWidth();
    }
  }

  /// Update paddle width based on current multipliers
  void _updatePaddleWidth({bool resetPosition = true}) {
    final currentWidth = (_end.x - _start.x).abs();
    // Use stored original width and apply current total multiplier
    final newWidth = _originalWidth * widthMultiplier;
    final center = _start.x + (_end.x - _start.x).abs() / 2;

    final newStart = Vector2(center - newWidth / 2, _start.y);
    final newEnd = Vector2(center + newWidth / 2, _end.y);

    appLog.info(
      'Updating paddle width: original=$_originalWidth, multiplier=$widthMultiplier, current=$currentWidth -> new=$newWidth',
    );

    updatePaddleShape(newStart, newEnd, resetPosition: resetPosition);
  }

  /// Reset only the temporary width effect without moving the paddle.
  void resetTempWidth() {
    if (_tempWidthMultiplier != 1.0) {
      appLog.info(
        'Resetting temp width multiplier from $_tempWidthMultiplier to 1.0 (level advance)',
      );
      _tempWidthMultiplier = 1.0;
      _updatePaddleWidth();
    }
  }

  /// Return the paddle to rest at its start pose, leaving its current width
  /// alone.
  ///
  /// Used by the within-level restart (fatal wall), where an obstacle's width
  /// effect is meant to persist for the rest of the level. [reset] adds the
  /// width reset on top of this.
  ///
  /// Thrust is zeroed here rather than being left to the action stream:
  /// [RiseTogetherWorld.clearActions] asks for zero thrust via
  /// `clearTeamActions()`, which pushes `PaddleAction.none` through a
  /// StreamController and therefore only lands an event-loop turn or more
  /// later. Until it does, [update] still sees the old thrust and re-applies
  /// rotation and upward velocity from the pose we just restored -- which is
  /// the paddle "continuing to move a little" after a reset. (That path also
  /// only emits for players who already have an action recorded, so for some
  /// players it never lands at all.)
  ///
  /// Transforms are applied synchronously for the same reason: setPosition and
  /// setAngle only stage them, and anything reading the body before the next
  /// update() -- a physics broadcast, most of all -- would see the pre-reset
  /// pose. Contact callbacks are dispatched after the step returns (see
  /// Forge2DWorld.update), so writing the transform from one is safe.
  void clearMotion() {
    thrustLeft = 0.0;
    thrustRight = 0.0;
    stopMovement();
    cancelPendingTransforms();
    setPosition(startPosition);
    setAngle(0.0);
    applyPendingTransforms();
    positionNotifier.value = startPosition.y;
  }

  @override
  void reset() {
    appLog.fine('Resetting paddle to start position: $startPosition');

    // Vanilla state: drop obstacle width effects, keep the configured base
    // multiplier. resetTempWidth() repositions the body itself, so it must run
    // before clearMotion() has the final say on the pose.
    resetTempWidth();

    clearMotion();
  }
}
