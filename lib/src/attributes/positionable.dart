import 'package:flame_forge2d/flame_forge2d.dart';

abstract mixin class PositionableBodyComponent {
  abstract Body body;
  bool _pendingPositionUpdate = false;
  bool _pendingAngleUpdate = false;
  // forge2d box2d v3
  BodyType get bodyType => body.type;
  bool get isKinematic => body.type == BodyType.kinematic;
  bool get isDynamic => body.type == BodyType.dynamic;
  bool get isStatic => body.type == BodyType.static;
  // BodyType get bodyType => body.bodyType;
  // bool get isKinematic => body.bodyType == BodyType.kinematic;
  // bool get isDynamic => body.bodyType == BodyType.dynamic;
  // bool get isStatic => body.bodyType == BodyType.static;

  final Vector2 _pendingPosition = Vector2.zero();
  double _pendingAngle = 0.0;
  bool get hasPendingPositionUpdate => _pendingPositionUpdate;
  bool get hasPendingAngleUpdate => _pendingAngleUpdate;
  bool get hasPendingTransforms =>
      _pendingPositionUpdate || _pendingAngleUpdate;

  /// Sets the position of the object.
  void setPosition(Vector2 position) {
    _pendingPositionUpdate = true;
    _pendingPosition.setFrom(position);
  }

  /// Sets the angle of the object.
  void setAngle(double angle) {
    _pendingAngleUpdate = true;
    _pendingAngle = angle;
  }

  void stopMovement() {
    // noop if kinematic is false
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0.0;
  }

  set bodyType(BodyType newType) {
    // forge2d box2d v3
    if (body.type != newType) {
      body.type = newType;
    }
    // forge2d box2d v2
    // if (body.bodyType != newType) {
    //   body.setType(newType);
    // }
  }

  void toKinematic() {
    bodyType = BodyType.kinematic;
  }

  void toDynamic() {
    bodyType = BodyType.dynamic;
  }

  void toStatic() {
    bodyType = BodyType.static;
  }

  void cancelPendingPositionUpdate() {
    _pendingPositionUpdate = false;
  }

  void cancelPendingAngleUpdate() {
    _pendingAngleUpdate = false;
  }

  void cancelPendingTransforms() {
    cancelPendingPositionUpdate();
    cancelPendingAngleUpdate();
  }

  /// Updates the position and angle of the object if a pending update is set.
  void applyPendingTransforms() {
    if (!_pendingPositionUpdate && !_pendingAngleUpdate) {
      return;
    }
    body.setTransform(
      _pendingPositionUpdate ? _pendingPosition : body.position,
      // forge2d box2d v3
      Rot.fromAngle(_pendingAngleUpdate ? _pendingAngle : body.angle),
      // forge2d box2d v2
      // _pendingAngleUpdate ? _pendingAngle : body.angle,
    );
    _pendingAngleUpdate = false;
    _pendingPositionUpdate = false;
  }
}
