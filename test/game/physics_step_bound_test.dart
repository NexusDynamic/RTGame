import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';

/// The ball's terminal speed, in world units per second: gravity over the
/// linear damping of 1.0 set in Ball.createBody.
const _terminalSpeed = 9.81 * GameGeometry.scale;

/// How far the ground extends below the playfield. A step that moves the ball
/// further than this in one integration can put it out the other side.
const _groundThickness = GameGeometry.groundDepth;

void main() {
  group('boundPhysicsStep', () {
    test('leaves a healthy frame untouched', () {
      for (final dt in [1 / 120, 1 / 60, 1 / 30]) {
        expect(RiseTogetherGameBase.boundPhysicsStep(dt), dt);
      }
    });

    test('bounds the resume-dt after a backgrounded window', () {
      // 13.9583s was measured on macOS after the window lost focus.
      expect(
        RiseTogetherGameBase.boundPhysicsStep(13.9583),
        RiseTogetherGameBase.maxPhysicsStep,
      );
    });

    test('a bounded step cannot carry the ball through the ground', () {
      // The failure this exists to prevent: at terminal velocity the ball
      // must not travel further in one step than the ground is thick, or it
      // tunnels out of the level and falls forever.
      final travel =
          _terminalSpeed * RiseTogetherGameBase.boundPhysicsStep(13.9583);
      expect(travel, lessThan(_groundThickness));
    });

    test('an unbounded step WOULD carry it through — the bug being fixed', () {
      expect(_terminalSpeed * 3.45, greaterThan(_groundThickness));
    });

    test('a bounded step cannot swing the paddle past its angle clamp', () {
      // Paddle.update clamps the angle once per frame, but box2d integrates
      // angular velocity inside the step, so an unbounded step rotates the
      // bar straight to its limit and dips a corner below the floor.
      const maxAngularVelocity =
          1.0 * 0.3; // full differential thrust x rotation_multiplier default
      const clamp = 1.3;
      expect(
        maxAngularVelocity * RiseTogetherGameBase.maxPhysicsStep,
        lessThan(clamp),
      );
    });

    test('is never negative or NaN-propagating for a zero frame', () {
      expect(RiseTogetherGameBase.boundPhysicsStep(0), 0);
    });
  });
}
