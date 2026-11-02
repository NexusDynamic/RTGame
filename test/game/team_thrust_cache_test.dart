import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/models/team_context.dart';

/// The thrust is cached between changes; it must still follow every change.
void main() {
  late Map<String, int> bitflags;
  late TeamActionStream stream;

  setUp(() {
    bitflags = {'a': 1, 'b': 2};
    stream = TeamActionStream(
      position: TeamDisplayPosition.left,
      maxPlayers: 4,
      getPlayerBitflags: () => bitflags,
    )..setConfiguredTeamPlayerCount(2);
  });

  tearDown(() => stream.dispose());

  test('repeated reads without a change return the same result', () {
    stream.addAction(GameAction('a', PaddleAction.left));
    expect(
      identical(stream.getCurrentThrust(), stream.getCurrentThrust()),
      isTrue,
    );
  });

  test('actions, clears and removals are reflected', () {
    stream.addAction(GameAction('a', PaddleAction.left));
    expect(stream.getCurrentThrust().leftThrust, 0.5);
    expect(stream.getCurrentThrust().leftBitflags, 1);

    stream.addAction(GameAction('b', PaddleAction.right));
    expect(stream.getCurrentThrust().rightThrust, 0.5);
    expect(stream.getCurrentThrust().rightBitflags, 2);

    stream.clearAllActions();
    expect(stream.getCurrentThrust().activePlayerCount, 0);

    stream.addAction(GameAction('a', PaddleAction.left));
    stream.removePlayer('a');
    expect(stream.getCurrentThrust().leftThrust, 0);
  });

  test('a new roster (a replaced bitflag map) is reflected', () {
    stream.addAction(GameAction('a', PaddleAction.left));
    expect(stream.getCurrentThrust().leftBitflags, 1);
    bitflags = {'a': 4, 'b': 8};
    expect(stream.getCurrentThrust().leftBitflags, 4);
  });

  test('a new configured team size is reflected', () {
    stream.addAction(GameAction('a', PaddleAction.left));
    expect(stream.getCurrentThrust().leftThrust, 0.5);
    stream.setConfiguredTeamPlayerCount(4);
    expect(stream.getCurrentThrust().leftThrust, 0.25);
  });
}
