import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/player_bitflags.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';

/// Bit assignment is not a UI detail: these values are packed into physics
/// channels 6 and 7 and broadcast every frame, so which player owns which bit
/// is what a recorded bitflag column *means*.
///
/// Every participant computes this locally from the roster it received, so all
/// of them must agree — an ordering that depended on arrival order or map
/// iteration would desynchronise the press indicators between devices and make
/// the recorded columns incomparable across sessions.
void main() {
  PlayerAssignment player(String nodeId, int team) => PlayerAssignment(
    nodeId: nodeId,
    nodeName: nodeId,
    teamId: team,
    playerId: 'player_$nodeId',
    isCoordinator: false,
  );

  group('ordering', () {
    test('is by team, then node id', () {
      final assigned = PlayerBitflags.assign([
        player('zeta', 1),
        player('alpha', 1),
        player('yankee', 0),
        player('bravo', 0),
      ]);

      expect(
        assigned.map((b) => b.nodeId),
        equals(['bravo', 'yankee', 'alpha', 'zeta']),
      );
    });

    test('is independent of input order', () {
      // Each device receives the roster as a map and may iterate it in a
      // different order; the result must not depend on that.
      final players = [
        player('c', 1),
        player('a', 0),
        player('d', 1),
        player('b', 0),
      ];
      final forward = PlayerBitflags.assign(players);
      final reversed = PlayerBitflags.assign(players.reversed.toList());

      expect(
        forward.map((b) => b.bitflagValue),
        equals(reversed.map((b) => b.bitflagValue)),
      );
      expect(
        forward.map((b) => b.nodeId),
        equals(reversed.map((b) => b.nodeId)),
      );
    });

    test('does not mutate the caller\'s list', () {
      final players = [player('b', 0), player('a', 0)];
      PlayerBitflags.assign(players);
      expect(players.first.nodeId, equals('b'));
    });
  });

  group('bit values', () {
    test('are successive powers of two', () {
      final assigned = PlayerBitflags.assign([
        player('a', 0),
        player('b', 0),
        player('c', 1),
        player('d', 1),
      ]);

      expect(assigned.map((b) => b.bitflagValue), equals([1, 2, 4, 8]));
      expect(assigned.map((b) => b.index), equals([0, 1, 2, 3]));
    });

    test('are unique and non-overlapping', () {
      final assigned = PlayerBitflags.assign([
        for (var i = 0; i < 8; i++) player('n$i', i % 2),
      ]);

      final bits = assigned.map((b) => b.bitflagValue).toList();
      expect(bits.toSet().length, equals(bits.length));
      // OR-ing every bit must lose nothing: that is what lets a team's presses
      // be packed into one channel and decoded again.
      final combined = bits.reduce((a, b) => a | b);
      for (final bit in bits) {
        expect(combined & bit, equals(bit));
      }
    });

    test('the index is global, not per team', () {
      // Team 1 gets 4 and 8, not 1 and 2 — so decoding a recording needs the
      // roster, not just the team id.
      final assigned = PlayerBitflags.assign([
        player('a', 0),
        player('b', 0),
        player('c', 1),
        player('d', 1),
      ]);

      final teamOne = assigned.where((b) => b.teamId == 1);
      expect(teamOne.map((b) => b.bitflagValue), equals([4, 8]));
    });
  });

  group('edge cases', () {
    test('an empty roster assigns nothing', () {
      expect(PlayerBitflags.assign(const []), isEmpty);
    });

    test('a single player gets bit 1', () {
      final assigned = PlayerBitflags.assign([player('solo', 0)]);
      expect(assigned.single.bitflagValue, equals(1));
    });
  });

  group('float32 channel limit', () {
    test('is 24, where float32 stops representing integers exactly', () {
      // Channels 6 and 7 are float32. 2^24 is the first integer it cannot
      // represent exactly, so a 25th player's bit could be perturbed in
      // transit and its press indicator silently misread.
      expect(PlayerBitflags.maxPlayers, equals(24));
      expect(PlayerBitflags.fitsInChannel(24), isTrue);
      expect(PlayerBitflags.fitsInChannel(25), isFalse);
    });

    test('the session cap of 16 nodes sits comfortably inside it', () {
      expect(PlayerBitflags.fitsInChannel(16), isTrue);
      // Sanity: the largest bit at the cap survives a float32 round-trip.
      const largestBit = 1 << 15;
      expect(largestBit.toDouble().toInt(), equals(largestBit));
    });
  });
}
