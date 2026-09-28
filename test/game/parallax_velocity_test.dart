import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/rise_together_world.dart';

/// The background parallax (the star layers) scrolls to represent how fast the
/// paddle is rising. The bg_scaffold girders used to be its front layer; they
/// are now drawn in world space, locked to the ground.
///
/// It used to scroll on the bare normalised thrust, which is a 0..1 team input
/// and not a speed. The speed that thrust actually produces is
/// `GameGeometry.velocity(physics.thrust_multiplier) * thrust` — so with
/// `thrust_multiplier` turned down to 0.2 the paddle climbed at a fifth of the
/// default rate while the girders kept scrolling at the full one.
void main() {
  group('parallaxVelocityForThrust', () {
    double speed(double thrust, double multiplier) =>
        parallaxVelocityForThrust(thrust, multiplier).y.abs();

    test('no thrust means no scroll', () {
      expect(speed(0.0, 1.0), equals(0.0));
    });

    test('scrolls upward (negative y) under thrust', () {
      // Vector2 is float32-backed, hence the 1e-6 tolerances throughout.
      // Y is negative-going up, and the background must move opposite to the
      // climb, so the sign is load-bearing rather than cosmetic.
      expect(parallaxVelocityForThrust(1.0, 1.0).y, isNegative);
    });

    test('the default configuration reproduces the previous constant', () {
      // The old hardcoded 0.25 per unit thrust. Preserved exactly at
      // thrust_multiplier = 1.0 so this change is invisible at defaults.
      expect(speed(1.0, 1.0), closeTo(1.28, 1e-6));
      expect(speed(0.5, 1.0), closeTo(0.64, 1e-6));
    });

    test('scroll speed tracks thrust_multiplier', () {
      // The regression: this ratio used to be 1.0 — the background ignored the
      // setting entirely.
      expect(speed(1.0, 0.2) / speed(1.0, 1.0), closeTo(0.2, 1e-6));
    });

    test('scroll speed tracks the world scale', () {
      // Derived from GameGeometry rather than hardcoded, so a scale change
      // cannot silently desynchronise the background from the motion.
      expect(
        speed(1.0, 1.0),
        closeTo(GameGeometry.scale * kParallaxPerWorldVelocity, 1e-6),
      );
    });

    test('is proportional to thrust', () {
      expect(speed(0.5, 0.2) * 2, closeTo(speed(1.0, 0.2), 1e-6));
    });

    test('a solo player and a full team reach the same scroll speed', () {
      // Thrust is normalised by team size (ActionStreamManager), so one
      // participant in the individual condition supplies totalThrust = 1.0 on
      // their own, exactly as a full team does jointly. That is why the
      // individual condition looks faster per press — not a scale factor.
      const soloIndividual = 1.0 / 1;
      const oneOfTwoJoint = 1.0 / 2;
      expect(
        speed(soloIndividual, 0.2),
        greaterThan(speed(oneOfTwoJoint, 0.2)),
      );
      expect(
        speed(oneOfTwoJoint * 2, 0.2),
        closeTo(speed(soloIndividual, 0.2), 1e-6),
      );
    });
  });
}
