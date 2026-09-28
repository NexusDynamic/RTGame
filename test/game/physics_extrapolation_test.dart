import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/physics_extrapolation.dart';

/// The arithmetic a follower uses when physics state stops arriving.
///
/// This engages during exactly the situation that is hardest to reason about
/// afterwards — a transport fault mid-trial — so the failure modes worth
/// pinning are the ones that would make a bad situation worse: a ball flung off
/// the level, motion invented from a single sample, or a divide-by-zero on two
/// samples that share a timestamp (which the inlet's per-poll-tick clock makes
/// ordinary rather than exotic).
void main() {
  group('projectChannel', () {
    test('advances by the implied velocity', () {
      // 0.1 units over 0.01 s = 10 units/s; 0.05 s of lead adds 0.5.
      expect(
        projectChannel(value: 1.1, previousValue: 1.0, span: 0.01, lead: 0.05),
        closeTo(1.6, 1e-12),
      );
    });

    test('a stationary ball is not moved', () {
      // The property that makes this safe to leave running: broadcast is
      // change-gated, so a resting ball sends nothing at all. Silence during a
      // legitimately quiet trial must therefore be a no-op, not a drift.
      expect(
        projectChannel(value: 2.0, previousValue: 2.0, span: 0.01, lead: 0.25),
        2.0,
      );
    });

    test('no lead leaves the value exactly alone', () {
      expect(
        projectChannel(value: 1.1, previousValue: 1.0, span: 0.01, lead: 0.0),
        1.1,
      );
    });

    test('two samples sharing a timestamp do not divide by zero', () {
      // received_clock is read once per inlet poll tick and shared by every
      // sample drained in it, so equal timestamps are routine.
      expect(
        projectChannel(value: 1.1, previousValue: 1.0, span: 0.0, lead: 0.05),
        1.1,
      );
      expect(
        projectChannel(value: 1.1, previousValue: 1.0, span: -0.01, lead: 0.05),
        1.1,
      );
    });

    test('a non-finite input passes the raw value through', () {
      expect(
        projectChannel(
          value: 1.1,
          previousValue: double.nan,
          span: 0.01,
          lead: 0.05,
        ),
        1.1,
      );
    });

    test('direction is preserved for downward motion', () {
      expect(
        projectChannel(
          value: -0.6,
          previousValue: -0.5,
          span: 0.01,
          lead: 0.02,
        ),
        closeTo(-0.8, 1e-12),
      );
    });
  });
}
