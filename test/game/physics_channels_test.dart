import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/physics_channels.dart';

/// Tests the REAL channel contract, not a reimplementation of it.
///
/// `physics_channel_test.dart` asserted arithmetic it defined locally, so it
/// could not fail when the production code diverged — and every documented
/// failure in this area was exactly such a divergence.
void main() {
  group('layout', () {
    test('is 8 channels per team, 16 per match, 32 for parallel 1v1', () {
      // These appear verbatim in recorded LSL data; changing one invalidates
      // existing analysis.
      expect(PhysicsChannels.perTeam, equals(8));
      expect(PhysicsChannels.teamsPerMatch, equals(2));
      expect(PhysicsChannels.perMatch, equals(16));
      expect(PhysicsChannels.oneVOneTotal, equals(32));
    });

    test('channel indices are stable and cover the slice exactly once', () {
      final indices = [
        PhysicsChannels.ballX,
        PhysicsChannels.ballY,
        PhysicsChannels.ballRotation,
        PhysicsChannels.paddleY,
        PhysicsChannels.paddleAngle,
        PhysicsChannels.paddleWidthMultiplier,
        PhysicsChannels.leftBitflags,
        PhysicsChannels.rightBitflags,
      ];
      expect(indices, equals([0, 1, 2, 3, 4, 5, 6, 7]));
      expect(indices.toSet().length, equals(PhysicsChannels.perTeam));
    });

    test('team offsets do not overlap', () {
      expect(PhysicsChannels.offsetForTeam(0), equals(0));
      expect(PhysicsChannels.offsetForTeam(1), equals(8));
    });
  });

  group('sliceForMatch', () {
    test('a 16-channel sample is a whole single match', () {
      final slice = PhysicsChannels.sliceForMatch(16, 0)!;
      expect(slice.start, equals(0));
      expect(slice.end, equals(16));
    });

    test('a 16-channel sample ignores matchId', () {
      // Joint and individual phases leave matchId at 0, but a stale 1 from a
      // previous 1v1 round must not shift the read off the end.
      final slice = PhysicsChannels.sliceForMatch(16, 1)!;
      expect(slice.start, equals(0));
      expect(slice.end, equals(16));
    });

    test('a 32-channel sample slices by match', () {
      final match0 = PhysicsChannels.sliceForMatch(32, 0)!;
      final match1 = PhysicsChannels.sliceForMatch(32, 1)!;

      expect((match0.start, match0.end), equals((0, 16)));
      expect((match1.start, match1.end), equals((16, 32)));
    });

    test('slices are contiguous and cover the whole sample', () {
      final a = PhysicsChannels.sliceForMatch(32, 0)!;
      final b = PhysicsChannels.sliceForMatch(32, 1)!;
      expect(a.end, equals(b.start));
      expect(b.end, equals(32));
    });

    test(
      'an out-of-range matchId yields null rather than reading past the end',
      () {
        expect(PhysicsChannels.sliceForMatch(32, 2), isNull);
        expect(PhysicsChannels.sliceForMatch(32, -1), isNull);
      },
    );

    test('an unrecognised length yields null, not a throw', () {
      // A throw here escapes the inbox listener and cancels the subscription,
      // stopping all physics for the rest of the round.
      for (final length in [0, 1, 15, 17, 31, 33, 48]) {
        expect(
          PhysicsChannels.sliceForMatch(length, 0),
          isNull,
          reason: '$length channels should be rejected',
        );
      }
    });

    test('isValidLength agrees with sliceForMatch', () {
      for (final length in [0, 15, 16, 17, 31, 32, 33]) {
        expect(
          PhysicsChannels.isValidLength(length),
          equals(PhysicsChannels.sliceForMatch(length, 0) != null),
          reason: 'disagreement at $length',
        );
      }
    });
  });

  group('sliceUnchanged', () {
    List<double> slice() => List.filled(PhysicsChannels.perTeam, 0.0);

    test('identical slices are unchanged', () {
      expect(PhysicsChannels.sliceUnchanged(slice(), slice()), isTrue);
    });

    test('a change in any single channel is detected', () {
      // The predecessor compared each value against the slot of its *first*
      // occurrence, so with 0.0 recurring at rest a real change read as
      // "unchanged" and was never broadcast — participants saw the paddle and
      // press indicators freeze.
      for (var i = 0; i < PhysicsChannels.perTeam; i++) {
        final current = slice()..[i] = 1.0;
        expect(
          PhysicsChannels.sliceUnchanged(current, slice()),
          isFalse,
          reason: 'a change at channel $i must be detected',
        );
      }
    });

    test('detects a bitflag change even when other channels repeat', () {
      // The exact shape of the old bug: widthMultiplier shares the value 1.0
      // with a single-player bitflag.
      final previous = slice()..[PhysicsChannels.paddleWidthMultiplier] = 1.0;
      final current = List<double>.from(previous)
        ..[PhysicsChannels.leftBitflags] = 1.0;

      expect(PhysicsChannels.sliceUnchanged(current, previous), isFalse);
    });

    test('is exact, not tolerance-based', () {
      // Bitflags are integers widened to double; a tolerance would swallow a
      // single-player press.
      final previous = slice();
      final current = slice()..[PhysicsChannels.ballY] = 1e-12;
      expect(PhysicsChannels.sliceUnchanged(current, previous), isFalse);
    });

    test('mismatched lengths count as changed', () {
      expect(
        PhysicsChannels.sliceUnchanged(slice(), List.filled(4, 0.0)),
        isFalse,
      );
    });
  });
}
