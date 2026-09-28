import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/tournament_manager.dart';
import '../helpers/test_helpers.dart';

void main() {
  setUpAll(() {
    silenceLogs();
  });
  group('TournamentManager — reset counting', () {
    late TournamentManager tm;

    setUp(() {
      tm = TournamentManager();
      tm.initialize(rounds: 3, roundDurationSeconds: 60);
      tm.startRound();
    });

    test('initial reset count is zero for both teams', () {
      // After startRound the round state is fresh
      tm.completeRound(roundIndex: 0);
      final result = tm.roundResults.last;
      expect(result.teamResults[0]!.resets, equals(0));
      expect(result.teamResults[1]!.resets, equals(0));
    });

    test('incrementTeamResets increments only the specified team', () {
      tm.incrementTeamResets(0);
      tm.completeRound(roundIndex: 0);
      final result = tm.roundResults.last;
      expect(result.teamResults[0]!.resets, equals(1));
      expect(result.teamResults[1]!.resets, equals(0));
    });

    test('multiple increments accumulate correctly', () {
      tm.incrementTeamResets(0);
      tm.incrementTeamResets(0);
      tm.incrementTeamResets(0);
      tm.incrementTeamResets(1);
      tm.incrementTeamResets(1);
      tm.completeRound(roundIndex: 0);
      final result = tm.roundResults.last;
      expect(result.teamResults[0]!.resets, equals(3));
      expect(result.teamResults[1]!.resets, equals(2));
    });

    test('resets reset to zero at the start of each new round', () {
      tm.incrementTeamResets(0);
      tm.incrementTeamResets(0);
      tm.completeRound(roundIndex: 0); // round 1 ends

      tm.startRound();
      // No increments in round 2
      tm.completeRound(roundIndex: 0);

      final round2 = tm.roundResults.last;
      expect(round2.teamResults[0]!.resets, equals(0));
    });

    test('resets from previous round do not bleed into next round', () {
      tm.incrementTeamResets(0);
      tm.completeRound(roundIndex: 0); // round 1: 1 reset for team 0

      tm.startRound();
      tm.incrementTeamResets(0);
      tm.incrementTeamResets(0);
      tm.completeRound(roundIndex: 0); // round 2: 2 resets for team 0

      final round1 = tm.roundResults[0];
      final round2 = tm.roundResults[1];
      expect(round1.teamResults[0]!.resets, equals(1));
      expect(round2.teamResults[0]!.resets, equals(2));
    });

    test('TeamRoundResult.toString includes resets', () {
      tm.incrementTeamResets(1);
      tm.completeRound(roundIndex: 0);
      final result = tm.roundResults.last;
      expect(result.teamResults[1]!.toString(), contains('resets: 1'));
    });
  });

  group('TournamentManager — round winner (existing logic unaffected)', () {
    late TournamentManager tm;

    setUp(() {
      tm = TournamentManager();
      tm.initialize(rounds: 3, roundDurationSeconds: 60);
      tm.startRound();
    });

    test('team with higher final level wins', () {
      tm.teamCompletedLevel(
        teamId: 0,
        completedLevelIndex: 1,
        distanceAchieved: 10,
      );
      tm.completeRound(roundIndex: 0);
      expect(tm.roundResults.last.roundWinner, equals(0));
    });

    test('team with greater distance wins on tied level', () {
      tm.updateTeamDistance(0, 50.0);
      tm.updateTeamDistance(1, 30.0);
      tm.completeRound(roundIndex: 0);
      expect(tm.roundResults.last.roundWinner, equals(0));
    });

    test('tied result returns -1', () {
      tm.completeRound(roundIndex: 0);
      expect(tm.roundResults.last.roundWinner, equals(-1));
    });

    test('team0RoundWins and team1RoundWins track correctly across rounds', () {
      // Round 1: team 0 wins
      tm.teamCompletedLevel(
        teamId: 0,
        completedLevelIndex: 2,
        distanceAchieved: 10,
      );
      tm.completeRound(roundIndex: 0);

      // Round 2: team 1 wins
      tm.startRound();
      tm.teamCompletedLevel(
        teamId: 1,
        completedLevelIndex: 2,
        distanceAchieved: 10,
      );
      tm.completeRound(roundIndex: 0);

      expect(tm.team0RoundWins, equals(1));
      expect(tm.team1RoundWins, equals(1));
    });
  });
}
