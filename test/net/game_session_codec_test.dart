import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';

/// Everything a session receives is untrusted. These pin that each decoder
/// accepts exactly the well-formed, in-range shapes and rejects the rest
/// without throwing.
void main() {
  /// Round-trip through real JSON, the way messages actually arrive.
  Object? wire(Map<String, dynamic> json) => jsonDecode(jsonEncode(json));

  group('GameEvent.fromJson', () {
    test('every event survives a JSON round trip', () {
      const events = <GameEvent>[
        TeamLevelProgression(teamId: 1, levelIndex: 3, seed: 42),
        LevelObjectConsumed(teamId: 0, spawnId: 7),
        TeamCountdownState(teamId: 0, stateIndex: 2, levelIndex: 4),
        TeamCountdownState(teamId: 1, stateIndex: 0),
        TeamCountdownTrigger(teamId: 1, levelIndex: 2),
        TeamCountdownTrigger(teamId: 0),
        GlobalCountdownState(stateIndex: 1),
        RoundOver(levels: [2, 3], distances: [10.5, 11]),
        Rematch(round: 2, seed: 99),
      ];
      for (final event in events) {
        final decoded = GameEvent.fromJson(wire(event.toJson()));
        expect(decoded, isNotNull, reason: event.type);
        expect(decoded!.toJson(), event.toJson());
      }
    });

    final rejected = <String, Object?>{
      'not a map': 'hello',
      'a list': [1, 2],
      'null': null,
      'unknown type': {'type': 'rm_rf', 'teamId': 0},
      'missing type': {'teamId': 0},
      'team out of range': {
        'type': TeamLevelProgression.typeName,
        'teamId': 2,
        'levelIndex': 0,
        'seed': 1,
      },
      'team as string': {
        'type': LevelObjectConsumed.typeName,
        'teamId': '0',
        'spawnId': 1,
      },
      'negative level': {
        'type': TeamLevelProgression.typeName,
        'teamId': 0,
        'levelIndex': -1,
        'seed': 1,
      },
      'huge level': {
        'type': TeamLevelProgression.typeName,
        'teamId': 0,
        'levelIndex': maxLevelIndex + 1,
        'seed': 1,
      },
      'negative seed': {
        'type': TeamLevelProgression.typeName,
        'teamId': 0,
        'levelIndex': 1,
        'seed': -5,
      },
      'negative spawn id': {
        'type': LevelObjectConsumed.typeName,
        'teamId': 0,
        'spawnId': -1,
      },
      'countdown state out of range': {
        'type': GlobalCountdownState.typeName,
        'stateIndex': 1000,
      },
      'round result with NaN distance': {
        'type': RoundOver.typeName,
        'levels': [1, 1],
        'distances': [double.nan, 1],
      },
      'round result with three teams': {
        'type': RoundOver.typeName,
        'levels': [1, 1, 1],
        'distances': [1, 1, 1],
      },
      'round result with negative distance': {
        'type': RoundOver.typeName,
        'levels': [1, 1],
        'distances': [-5, 1],
      },
      'rematch back to round 0': {
        'type': Rematch.typeName,
        'round': 0,
        'seed': 1,
      },
      'rematch past the round cap': {
        'type': Rematch.typeName,
        'round': maxRound + 1,
        'seed': 1,
      },
      'level index as double': {
        'type': TeamCountdownTrigger.typeName,
        'teamId': 0,
        'levelIndex': 1.5,
      },
    };
    rejected.forEach((name, json) {
      test('rejects $name', () {
        expect(GameEvent.fromJson(json), isNull);
      });
    });

    test('carries no free text for display', () {
      // Countdown messages are rendered locally from a level index; a text
      // field from a peer must not survive decoding.
      final decoded = GameEvent.fromJson({
        'type': TeamCountdownTrigger.typeName,
        'teamId': 0,
        'message': 'visit evil.example',
      });
      expect(decoded, isA<TeamCountdownTrigger>());
      expect(decoded!.toJson().containsKey('message'), isFalse);
    });
  });

  group('RoundOver.winner', () {
    test('higher level wins, then distance, else a tie', () {
      expect(const RoundOver(levels: [2, 1], distances: [0, 99]).winner, 0);
      expect(const RoundOver(levels: [1, 1], distances: [3, 4]).winner, 1);
      expect(const RoundOver(levels: [1, 1], distances: [3, 3]).winner, -1);
    });
  });

  group('MatchRules.fromJson', () {
    test('accepts a whole-number duration that JSON turned into an int', () {
      final rules = MatchRules.fromJson(
        wire(
          const MatchRules(
            mode: MatchMode.versus,
            roundDurationSeconds: 180,
            seed: 9,
          ).toJson(),
        ),
      );
      expect(rules?.mode, MatchMode.versus);
      expect(rules?.roundDurationSeconds, 180.0);
      expect(rules?.seed, 9);
    });

    for (final (name, json) in <(String, Object?)>[
      ('too short', {'mode': 'coop', 'roundDurationSeconds': 1, 'seed': 1}),
      ('too long', {'mode': 'coop', 'roundDurationSeconds': 1e9, 'seed': 1}),
      (
        'duration as string',
        {'mode': 'coop', 'roundDurationSeconds': '180', 'seed': 1},
      ),
      ('missing seed', {'mode': 'coop', 'roundDurationSeconds': 180}),
      (
        'seed too large',
        {'mode': 'coop', 'roundDurationSeconds': 180, 'seed': 1 << 40},
      ),
      (
        'unknown mode',
        {'mode': 'chaos', 'roundDurationSeconds': 180, 'seed': 1},
      ),
      ('missing mode', {'roundDurationSeconds': 180, 'seed': 1}),
      ('not a map', 180),
    ]) {
      test('rejects $name', () => expect(MatchRules.fromJson(json), isNull));
    }
  });

  group('validPhysicsSample', () {
    List<double> sample([double fill = 0]) => List.filled(16, fill);

    test('accepts a normal sample', () {
      expect(validPhysicsSample(sample(1.5), expectedLength: 16), isTrue);
    });

    test('rejects the wrong length', () {
      expect(validPhysicsSample(List.filled(32, 0), expectedLength: 16), false);
    });

    for (final bad in [double.nan, double.infinity, -double.infinity, 1e12]) {
      test('rejects $bad', () {
        final s = sample()..[3] = bad;
        expect(validPhysicsSample(s, expectedLength: 16), isFalse);
      });
    }
  });

  group('PlayerActionMessage.decodeAction', () {
    test('round trips every action', () {
      for (final action in PaddleAction.values) {
        expect(
          PlayerActionMessage.decodeAction(
            wire(PlayerActionMessage.encodeAction(action)),
          ),
          action,
        );
      }
    });

    test('rejects unknown actions and shapes', () {
      expect(PlayerActionMessage.decodeAction({'action': 'teleport'}), isNull);
      expect(PlayerActionMessage.decodeAction({'action': 1}), isNull);
      expect(PlayerActionMessage.decodeAction('left'), isNull);
    });
  });

  group('PlayerAssignment.tryFromMap', () {
    final valid = PlayerAssignment(
      nodeId: 'node-1',
      nodeName: 'Alice',
      teamId: 1,
      playerId: 'p1',
      isCoordinator: false,
    );

    test('round trips', () {
      final decoded = PlayerAssignment.tryFromMap(wire(valid.toMap()));
      expect(decoded?.toMap(), valid.toMap());
    });

    test('rejects oversized names', () {
      final map = valid.toMap()..['nodeName'] = 'x' * 1000;
      expect(PlayerAssignment.tryFromMap(map), isNull);
    });

    test('rejects a team that does not exist', () {
      final map = valid.toMap()..['teamId'] = 5;
      expect(PlayerAssignment.tryFromMap(map), isNull);
    });

    test('rejects missing ids', () {
      final map = valid.toMap()..remove('playerId');
      expect(PlayerAssignment.tryFromMap(map), isNull);
    });
  });
}
