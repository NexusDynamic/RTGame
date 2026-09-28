import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/action_provider.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/models/team_context.dart';
import 'package:rise_together_game/src/net/game_session.dart';

import '../helpers/test_helpers.dart';
import 'fake_game_session.dart';

void main() {
  setUpAll(silenceLogs);

  late FakeGameSession session;
  late ActionStreamManager actions;
  late SessionActionProvider provider;

  setUp(() async {
    session = FakeGameSession();
    actions = ActionStreamManager();
    for (final (pos, id) in [
      (TeamDisplayPosition.left, 0),
      (TeamDisplayPosition.right, 1),
    ]) {
      actions.createTeamStream(pos, 5, getPlayerBitflags: () => {}).teamId = id;
    }
    provider = SessionActionProvider(session, actions);
    await provider.initialize();
  });

  tearDown(() async {
    provider.dispose();
    await session.leave();
  });

  /// Team 1's (left, right) thrust after the guest sends [sent].
  Future<(double, double)> thrustAfter(PaddleAction sent) async {
    session.actionsIn.add(
      PlayerActionMessage(teamId: 1, playerId: 'guest', action: sent),
    );
    await Future<void>.delayed(Duration.zero);
    final thrust = actions.getTeamStream(1)!.getCurrentThrust();
    return (thrust.leftThrust, thrust.rightThrust);
  }

  test('remote input reaches the player\'s team stream', () async {
    final (left, right) = await thrustAfter(PaddleAction.left);
    expect(left, greaterThan(0));
    expect(right, 0);
  });

  test('input for a locked team is dropped', () async {
    provider.acceptInput = (teamId) => teamId != 1;
    final (left, right) = await thrustAfter(PaddleAction.right);
    expect(left + right, 0);
  });

  test('local input goes to the session, not straight to physics', () {
    provider.networkBridge.sendAction(0, 'host', PaddleAction.right);
    expect(session.sentActions, [PaddleAction.right]);
  });
}
