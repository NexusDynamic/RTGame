import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/physics_channels.dart';
import 'package:rise_together_game/src/game/snapshot_interpolator.dart';

void main() {
  const ballY = PhysicsChannels.ballY;
  const rotation = PhysicsChannels.ballRotation;
  const leftBits = PhysicsChannels.leftBitflags;

  List<double> state({double y = 0, double rot = 0, double bits = 0}) {
    final s = List<double>.filled(PhysicsChannels.perMatch, 0);
    s[ballY] = y;
    s[rotation] = rot;
    s[leftBits] = bits;
    return s;
  }

  late SnapshotInterpolator interpolator;
  setUp(() {
    interpolator = SnapshotInterpolator(delay: 0.1, maxExtrapolation: 0.05);
  });

  test('nothing to show until a sample arrives', () {
    expect(interpolator.sample(1), isNull);
  });

  test('blends positions at the delayed render time', () {
    interpolator
      ..add(state(y: 0), 1.0)
      ..add(state(y: 4), 1.2);
    // Render time 1.1 is halfway between the two samples.
    expect(interpolator.sample(1.2)![ballY], closeTo(2, 1e-9));
  });

  test('discrete channels take the newer sample', () {
    interpolator
      ..add(state(bits: 1), 1.0)
      ..add(state(bits: 2), 1.2);
    expect(interpolator.sample(1.15)![leftBits], 2);
  });

  test('rotation blends the short way across the wrap', () {
    interpolator
      ..add(state(rot: math.pi - 0.1), 1.0)
      ..add(state(rot: -math.pi + 0.1), 1.2);
    final mid = interpolator.sample(1.2)![rotation];
    // Halfway along the 0.2 rad short arc is ±π, not 0.
    expect(math.cos(mid), closeTo(-1, 1e-6));
  });

  test('extrapolates briefly past the newest sample, then holds', () {
    interpolator
      ..add(state(y: 0), 1.0)
      ..add(state(y: 1), 1.1); // 10 units/s
    // Render time 1.13: 0.03 s past the newest.
    expect(interpolator.sample(1.23)![ballY], closeTo(1.3, 1e-9));
    // Far past: capped at maxExtrapolation (0.05 s).
    expect(interpolator.sample(5)![ballY], closeTo(1.5, 1e-9));
  });

  test('old samples are dropped as render time passes them', () {
    for (var i = 0; i < 10; i++) {
      interpolator.add(state(y: i.toDouble()), 1 + i * 0.1);
    }
    interpolator.sample(1.75); // render time 1.65
    expect(interpolator.length, lessThanOrEqualTo(4));
  });

  test('capacity bounds a burst', () {
    final small = SnapshotInterpolator(capacity: 4);
    for (var i = 0; i < 100; i++) {
      small.add(state(), i.toDouble());
    }
    expect(small.length, 4);
  });

  test('same-instant arrivals are kept in order, not divided by zero', () {
    interpolator
      ..add(state(y: 0), 1.0)
      ..add(state(y: 2), 1.0);
    final y = interpolator.sample(1.1)![ballY];
    expect(y.isFinite, isTrue);
  });

  group('teleports', () {
    // Default maxJump is half a level width; a reset back to the start is
    // several level heights.
    const reset = 40.0;
    const paddleY = PhysicsChannels.paddleY;
    final team1BallY = PhysicsChannels.offsetForTeam(1) + ballY;

    test('a reset snaps to the new pose instead of sweeping to it', () {
      interpolator
        ..add(state(y: reset), 1.0)
        ..add(state(y: 0), 1.2);
      expect(interpolator.sample(1.2)![ballY], 0);
    });

    test('a paddle jump alone counts', () {
      final a = state()..[paddleY] = reset;
      final b = state()..[paddleY] = 0;
      interpolator
        ..add(a, 1.0)
        ..add(b, 1.2);
      expect(interpolator.sample(1.2)![paddleY], 0);
    });

    test('is not projected past the newest sample', () {
      interpolator
        ..add(state(y: reset), 1.0)
        ..add(state(y: 0), 1.1);
      expect(interpolator.sample(1.23)![ballY], 0);
    });

    test('only the team that teleported snaps', () {
      final a = state(y: reset)..[team1BallY] = 0;
      final b = state(y: 0)..[team1BallY] = 4;
      interpolator
        ..add(a, 1.0)
        ..add(b, 1.2);
      final out = interpolator.sample(1.2)!;
      expect(out[ballY], 0);
      expect(out[team1BallY], closeTo(2, 1e-9));
    });
  });

  group('lastSampleTime', () {
    test('is null before the first sample', () {
      interpolator.sample(1);
      expect(interpolator.lastSampleTime, isNull);
    });

    test('is the newer of the two samples being blended', () {
      interpolator
        ..add(state(), 1.0)
        ..add(state(), 1.2)
        ..add(state(), 1.4);
      interpolator.sample(1.2); // render time 1.1
      expect(interpolator.lastSampleTime, 1.2);
    });

    test('is the newest while projecting, and resets on clear', () {
      interpolator
        ..add(state(), 1.0)
        ..add(state(), 1.1);
      interpolator.sample(2);
      expect(interpolator.lastSampleTime, 1.1);
      interpolator.clear();
      expect(interpolator.lastSampleTime, isNull);
    });
  });
}
