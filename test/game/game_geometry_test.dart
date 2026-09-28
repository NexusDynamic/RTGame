import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/rise_together_levels.dart';

// Box2D tolerance constants are reproduced here rather than imported, for two
// reasons: forge2d is only a transitive dependency, and these move between the
// v2 and v3 generations (v2 exposes them as mutable top-level variables in
// settings.dart, v3 as C macros). Hardcoding keeps this test meaningful across
// the migration. Values verified against forge2d 0.14.2+1 and 0.15.0.

/// forge2d v2 `polygonRadius` (= 2 * linearSlop): the skin applied to every
/// polygon and edge fixture. `lib/src/settings.dart:40`.
const double polygonRadius = 2 * 0.005;

/// forge2d v2 `maxTranslation`: cap on how far a body may move in one step.
/// `lib/src/settings.dart:64`.
const double maxTranslation = 2.0;

/// Box2D v3's speculative contact distance, in ABSOLUTE world units.
///
/// From forge2d 0.15's vendored box2d source (`src/constants.h`):
///   B2_LINEAR_SLOP          = 0.005 * b2_lengthUnitsPerMeter
///   B2_SPECULATIVE_DISTANCE = 4 * B2_LINEAR_SLOP
///
/// It does not shrink when the world is small, which is the whole reason
/// [GameGeometry.scale] exists. Hardcoded rather than read from forge2d
/// because the currently-resolved forge2d is still v2 and does not expose it.
const double speculativeDistance = 4 * 0.005;

/// How many speculative distances of clearance we require. Below ~1 the ball
/// generates contacts with walls it has not touched, which fires the fatal-wall
/// handler on spawn and puts the level into a reset loop.
const double requiredMargin = 4.0;

void main() {
  group('GameGeometry internal consistency', () {
    test('vertical layout composes from thickness and radius', () {
      expect(
        GameGeometry.paddleTopY,
        GameGeometry.paddleBottomY - GameGeometry.paddleThickness,
      );
      expect(
        GameGeometry.ballSpawnY,
        GameGeometry.paddleTopY - GameGeometry.ballRadius,
      );
    });

    test('proportions are scale-invariant', () {
      // These ratios define the game's look and feel. They must not drift when
      // `scale` changes -- that is what makes a scale change a pure change of
      // units rather than a gameplay change.
      expect(
        GameGeometry.ballRadius / GameGeometry.levelWidth,
        closeTo(0.02, 1e-12),
      );
      expect(
        GameGeometry.paddleHalfWidth / GameGeometry.levelWidth,
        closeTo(0.15, 1e-12),
      );
      expect(
        GameGeometry.paddleThickness / GameGeometry.ballRadius,
        closeTo(1.0, 1e-12),
      );
      expect(
        GameGeometry.wallThickness / GameGeometry.levelWidth,
        closeTo(0.01, 1e-12),
      );
    });

    test('RiseTogetherLevel delegates its width to GameGeometry', () {
      expect(RiseTogetherLevel.horizontalWidth, GameGeometry.levelWidth);
    });

    test('distanceMultiplier compensates so reported metres are unchanged', () {
      // A ball that climbs the full height of Level 1 must report the same
      // distance in metres regardless of scale.
      const rawMultiplier = 100.0;
      final height = const Level1().verticalHeight;
      final metres = height * GameGeometry.distanceMultiplier(rawMultiplier);
      expect(metres, closeTo(1.0 * rawMultiplier, 1e-9));
    });
  });

  group('clearances vs box2d tolerances', () {
    // The bug this refactor exists to fix: at scale 1.0 the paddle sat 0.01
    // from the fatal ground wall and the ball spawned 0.03 from it, against a
    // speculative distance of 0.02.

    test('paddle clears the fatal ground wall', () {
      // Ground wall inner face is y = 0; paddle bottom face is paddleBottomY.
      final clearance = GameGeometry.paddleBottomY.abs();
      expect(
        clearance,
        greaterThanOrEqualTo(requiredMargin * speculativeDistance),
        reason:
            'Paddle bottom is ${clearance.toStringAsFixed(4)} from the fatal '
            'ground wall, only ${(clearance / speculativeDistance).toStringAsFixed(1)}x '
            'the speculative distance. Raise GameGeometry.scale.',
      );
    });

    test('ball clears the fatal ground wall at spawn', () {
      // Ball's lowest point is its centre plus the radius (y is negative up),
      // which is exactly the paddle's top face.
      final ballBottom = GameGeometry.ballSpawnY + GameGeometry.ballRadius;
      final clearance = ballBottom.abs();
      expect(
        clearance,
        greaterThanOrEqualTo(requiredMargin * speculativeDistance),
        reason:
            'Ball spawns ${clearance.toStringAsFixed(4)} above the fatal ground '
            'wall, only ${(clearance / speculativeDistance).toStringAsFixed(1)}x '
            'the speculative distance.',
      );
    });

    test('ball clears the fatal side walls at spawn', () {
      final clearance = GameGeometry.levelWidth / 2 - GameGeometry.ballRadius;
      expect(
        clearance,
        greaterThanOrEqualTo(requiredMargin * speculativeDistance),
      );
    });

    test('gameplay objects sit in the size band box2d is tuned for', () {
      // Box2D is designed for objects roughly 0.1-10 units across; below that
      // its absolute tolerances start to dominate.
      expect(GameGeometry.ballRadius * 2, greaterThanOrEqualTo(0.1));
      expect(GameGeometry.paddleThickness, greaterThanOrEqualTo(0.1));
      expect(GameGeometry.wallThickness, greaterThanOrEqualTo(0.1));
      expect(GameGeometry.levelWidth, lessThanOrEqualTo(10.0));
    });

    test('objects are larger than forge2d v2 polygon skin', () {
      // polygonRadius = 2 * linearSlop is applied as a skin to every polygon
      // and edge fixture. It was half the ball's radius before scaling.
      expect(
        GameGeometry.ballRadius,
        greaterThan(4 * polygonRadius),
        reason:
            'polygonRadius ($polygonRadius) is a large fraction of '
            'the ball radius (${GameGeometry.ballRadius}).',
      );
    });
  });

  group('velocity limits', () {
    // Ball terminal velocity is gravity / linearDamping. linearDamping is 1.0
    // (ball.dart) and gravity is scaled, so terminal velocity scales too.
    const rawGravity = 9.81;
    const linearDamping = 1.0;
    const tickRateHz = 120.0;

    double terminalVelocity() =>
        GameGeometry.gravity(rawGravity) / linearDamping;

    test('stays under forge2d v2 maxTranslation per step', () {
      final perStep = terminalVelocity() / tickRateHz;
      expect(
        perStep,
        lessThan(maxTranslation),
        reason:
            'At ${GameGeometry.scale}x scale the ball moves '
            '${perStep.toStringAsFixed(3)} units per ${tickRateHz}Hz step, '
            'against a cap of $maxTranslation. Lower GameGeometry.scale '
            'or raise forge2d maxTranslation.',
      );
    });

    test('stays under box2d v3 default maximumLinearSpeed', () {
      // WorldDef.maximumLinearSpeed defaults to 400 in forge2d 0.15.
      expect(terminalVelocity(), lessThan(400.0));
    });
  });
}
