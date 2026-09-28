import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/physics_channels.dart';

/// Tests for physics state channel layout and slice logic.
///
/// The constants below now come from [PhysicsChannels] rather than being
/// redeclared here. As local copies they could not fail when production
/// diverged — which is precisely how the change-detection and double-shift
/// bugs survived. See physics_channels_test.dart for the contract itself;
/// this file covers the combine logic layered on top.
void main() {
  const channelsPerTeam = PhysicsChannels.perTeam;
  const teamsPerMatch = PhysicsChannels.teamsPerMatch;
  const channelsPerMatch = PhysicsChannels.perMatch;
  const matchCount = PhysicsChannels.matchesInOneVOne;
  const totalChannels1v1 = PhysicsChannels.oneVOneTotal;

  group('channel counts', () {
    test('2v2 and individual: 16 channels (8 per team × 2 teams)', () {
      expect(channelsPerTeam * teamsPerMatch, equals(16));
    });

    test('1v1: 32 channels (16 per match × 2 matches)', () {
      expect(channelsPerMatch * matchCount, equals(32));
    });
  });

  group('channel layout within a 16-channel match block', () {
    // Coordinator encodes: [ballX, ballY, ballRotation, paddleY, paddleAngle,
    //                       paddleWidthMultiplier, leftBitflags, rightBitflags]
    // for team 0 at indices 0-7, team 1 at indices 8-15.

    test('team 0 occupies channels 0–7', () {
      final team0Range = List.generate(channelsPerTeam, (i) => i);
      expect(team0Range.first, equals(0));
      expect(team0Range.last, equals(7));
    });

    test('team 1 occupies channels 8–15', () {
      final team1Start = channelsPerTeam * 1;
      final team1Range = List.generate(channelsPerTeam, (i) => team1Start + i);
      expect(team1Range.first, equals(8));
      expect(team1Range.last, equals(15));
    });
  });

  group('1v1 match slice extraction', () {
    // Participant clients filter the 32-channel state to their own 16-channel
    // slice using: state.sublist(16 * matchId, 16 * (matchId + 1))

    late List<double> fullState;
    setUp(() {
      fullState = List.generate(totalChannels1v1, (i) => i.toDouble());
    });

    test('match 0 slice covers channels 0–15', () {
      const matchId = 0;
      final slice = fullState.sublist(
        channelsPerMatch * matchId,
        channelsPerMatch * (matchId + 1),
      );
      expect(slice.length, equals(16));
      expect(slice.first, equals(0.0));
      expect(slice.last, equals(15.0));
    });

    test('match 1 slice covers channels 16–31', () {
      const matchId = 1;
      final slice = fullState.sublist(
        channelsPerMatch * matchId,
        channelsPerMatch * (matchId + 1),
      );
      expect(slice.length, equals(16));
      expect(slice.first, equals(16.0));
      expect(slice.last, equals(31.0));
    });

    test('slices are non-overlapping', () {
      final slice0 = fullState.sublist(0, channelsPerMatch);
      final slice1 = fullState.sublist(channelsPerMatch);
      final combined = [...slice0, ...slice1];
      expect(combined, equals(fullState));
    });

    test('no channel is lost between matches', () {
      final allChannels = <double>[];
      for (int matchId = 0; matchId < matchCount; matchId++) {
        allChannels.addAll(
          fullState.sublist(
            channelsPerMatch * matchId,
            channelsPerMatch * (matchId + 1),
          ),
        );
      }
      expect(allChannels, equals(fullState));
    });
  });

  group('getCombinedPhysicsState logic', () {
    // Mirrors the logic in MatchManager.getCombinedPhysicsState().
    List<double>? combinedState({
      List<double>? delta0,
      List<double>? delta1,
      List<double>? snapshot0,
      List<double>? snapshot1,
    }) {
      if (delta0 == null && delta1 == null) return null;
      return [
        ...(delta0 ?? snapshot0 ?? List.filled(channelsPerMatch, 0.0)),
        ...(delta1 ?? snapshot1 ?? List.filled(channelsPerMatch, 0.0)),
      ];
    }

    final state16 = List.generate(16, (i) => i.toDouble());
    final otherState16 = List.generate(16, (i) => (i + 100).toDouble());

    test('returns null when both matches have no new data', () {
      expect(combinedState(delta0: null, delta1: null), isNull);
    });

    test('returns 32 channels when only match 0 changed', () {
      final result = combinedState(
        delta0: state16,
        delta1: null,
        snapshot1: otherState16,
      );
      expect(result?.length, equals(32));
      expect(result?.sublist(0, 16), equals(state16));
      expect(result?.sublist(16), equals(otherState16));
    });

    test('returns 32 channels when only match 1 changed', () {
      final result = combinedState(
        delta0: null,
        delta1: state16,
        snapshot0: otherState16,
      );
      expect(result?.length, equals(32));
      expect(result?.sublist(0, 16), equals(otherState16));
      expect(result?.sublist(16), equals(state16));
    });

    test('returns 32 channels when both matches changed', () {
      final result = combinedState(delta0: state16, delta1: otherState16);
      expect(result?.length, equals(32));
      expect(result?.sublist(0, 16), equals(state16));
      expect(result?.sublist(16), equals(otherState16));
    });

    test('falls back to zeros when snapshot is also null', () {
      final result = combinedState(
        delta0: state16,
        delta1: null,
        snapshot1: null,
      );
      expect(result?.sublist(16), equals(List.filled(16, 0.0)));
    });
  });
}
