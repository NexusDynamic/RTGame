import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';
import 'package:rise_together_game/src/net/player_roster.dart';

/// Team balancing and the start precondition were previously reachable only
/// over the network, inside the coordinator. They decide who plays with whom,
/// which is an experimental variable, so they are worth asserting directly.
void main() {
  late PlayerRoster roster;

  setUp(() => roster = PlayerRoster());

  PlayerAssignment player(String id, int team, {bool coordinator = false}) =>
      PlayerAssignment(
        nodeId: id,
        nodeName: id,
        teamId: team,
        playerId: 'player_$id',
        isCoordinator: coordinator,
      );

  group('membership', () {
    test('starts empty', () {
      expect(roster.isEmpty, isTrue);
      expect(roster.length, equals(0));
      expect(roster.forNode('nobody'), isNull);
    });

    test('put then read back', () {
      roster.put(player('p1', 0));
      expect(roster.contains('p1'), isTrue);
      expect(roster.forNode('p1')!.teamId, equals(0));
      expect(roster.length, equals(1));
    });

    test('re-putting the same node replaces rather than duplicates', () {
      roster.put(player('p1', 0));
      roster.put(player('p1', 1));
      expect(roster.length, equals(1));
      expect(roster.forNode('p1')!.teamId, equals(1));
    });

    test('remove returns the departed assignment', () {
      roster.put(player('p1', 0));
      expect(roster.remove('p1')!.nodeId, equals('p1'));
      expect(roster.contains('p1'), isFalse);
    });

    test('replaceAll swaps the whole roster', () {
      // What a participant does on every assignments broadcast; a stale entry
      // surviving would put someone on a team the coordinator has moved them off.
      roster.put(player('old', 0));
      roster.replaceAll({'p1': player('p1', 1)});

      expect(roster.contains('old'), isFalse);
      expect(roster.contains('p1'), isTrue);
      expect(roster.length, equals(1));
    });

    test('the exposed collections are unmodifiable', () {
      roster.put(player('p1', 0));
      expect(
        () => roster.assignments.add(player('x', 0)),
        throwsUnsupportedError,
      );
      expect(
        () => roster.byNodeId['x'] = player('x', 0),
        throwsUnsupportedError,
      );
    });
  });

  group('team counts', () {
    test('are keyed by team id as a string, for the wire', () {
      roster.put(player('p1', 0));
      roster.put(player('p2', 0));
      roster.put(player('p3', 1));

      // JSON object keys are strings; this map goes straight into
      // game_configuration's `teams` field.
      expect(roster.teamCounts(), equals({'0': 2, '1': 1}));
    });

    test('omit teams with nobody on them', () {
      roster.put(player('p1', 0));
      expect(roster.teamCounts(), equals({'0': 1}));
    });

    test('playerCountForTeam excludes the coordinator', () {
      roster.put(player('coord', 0, coordinator: true));
      roster.put(player('p1', 0));

      expect(roster.playerCountForTeam(0), equals(1));
      // teamCounts is the raw roster; playerCountForTeam is the player count.
      expect(roster.teamCounts()['0'], equals(2));
    });
  });

  group('balancing', () {
    test('an empty roster sends the first joiner to team 0', () {
      expect(roster.balancedTeamFor(), equals(0));
    });

    test('joiners alternate while teams stay even', () {
      expect(roster.balancedTeamFor(), equals(0));
      roster.put(player('p1', 0));
      expect(roster.balancedTeamFor(), equals(1));
      roster.put(player('p2', 1));
      expect(roster.balancedTeamFor(), equals(0));
    });

    test('the smaller team wins', () {
      roster.put(player('p1', 0));
      roster.put(player('p2', 0));
      roster.put(player('p3', 1));
      expect(roster.balancedTeamFor(), equals(1));
    });

    test('ties go to team 0, so filling order is stable across runs', () {
      roster.put(player('p1', 0));
      roster.put(player('p2', 1));
      expect(roster.balancedTeamFor(), equals(0));
    });
  });

  group('canStart', () {
    test('is false with nobody assigned', () {
      expect(roster.canStart(), isFalse);
    });

    test('is false with only the coordinator', () {
      roster.put(player('coord', 0, coordinator: true));
      expect(
        roster.canStart(),
        isFalse,
        reason: 'the coordinator is never a player',
      );
    });

    test('is true with players on both teams', () {
      roster.put(player('p1', 0));
      roster.put(player('p2', 1));
      expect(roster.canStart(), isTrue);
    });

    test('is true with everyone on one team', () {
      // Deliberately `or`, not `and`, and confirmed intentional: teams are
      // assigned manually for real sessions, and the permissive check is what
      // makes solo testing possible.
      roster.put(player('p1', 0));
      expect(roster.canStart(), isTrue);

      final other = PlayerRoster()..put(player('p2', 1));
      expect(other.canStart(), isTrue);
    });
  });

  group('wire format', () {
    test('toWire keys by node id and serialises each assignment', () {
      roster.put(player('p1', 1));
      final wire = roster.toWire();

      expect(wire.keys, equals(['p1']));
      final entry = wire['p1'] as Map<String, dynamic>;
      expect(entry['teamId'], equals(1));
      expect(entry['playerId'], equals('player_p1'));
      expect(entry['isCoordinator'], isFalse);
    });

    test('round-trips through tryFromMap', () {
      roster.put(player('p1', 1));
      final restored = PlayerAssignment.tryFromMap(roster.toWire()['p1']);
      expect(restored?.nodeId, equals('p1'));
      expect(restored?.teamId, equals(1));
    });
  });
}
