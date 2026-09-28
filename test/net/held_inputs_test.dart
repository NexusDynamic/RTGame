import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/net/held_inputs.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';

void main() {
  final alice = PlayerAssignment(
    nodeId: 'a',
    nodeName: 'Alice',
    teamId: 0,
    playerId: 'p1',
    isCoordinator: false,
  );
  final bob = PlayerAssignment(
    nodeId: 'b',
    nodeName: 'Bob',
    teamId: 1,
    playerId: 'p2',
    isCoordinator: false,
  );

  Duration ms(int value) => Duration(milliseconds: value);

  late HeldInputs held;
  setUp(() => held = HeldInputs(staleAfter: ms(1000)));

  test('a press still being re-sent is never stale', () {
    for (var t = 0; t <= 5000; t += 200) {
      held.record(alice, PaddleAction.left, ms(t));
      expect(held.takeStale(ms(t + 100)), isEmpty);
    }
  });

  test('a press gone quiet is released once', () {
    held.record(alice, PaddleAction.left, ms(0));
    expect(held.takeStale(ms(1000)), isEmpty);
    expect(held.takeStale(ms(1001)), [alice]);
    expect(held.takeStale(ms(5000)), isEmpty);
  });

  test('a released player going quiet needs nothing', () {
    held.record(alice, PaddleAction.none, ms(0));
    expect(held.takeStale(ms(5000)), isEmpty);
  });

  test('hearing from the player again re-arms it', () {
    held.record(alice, PaddleAction.right, ms(0));
    expect(held.takeStale(ms(2000)), [alice]);
    held.record(alice, PaddleAction.right, ms(3000));
    expect(held.takeStale(ms(3500)), isEmpty);
    expect(held.takeStale(ms(4500)), [alice]);
  });

  test('players are judged separately', () {
    held
      ..record(alice, PaddleAction.left, ms(0))
      ..record(bob, PaddleAction.right, ms(800));
    expect(held.takeStale(ms(1500)), [alice]);
    expect(held.takeStale(ms(1900)), [bob]);
  });

  test('a removed player is forgotten', () {
    held
      ..record(alice, PaddleAction.left, ms(0))
      ..remove(alice.nodeId);
    expect(held.takeStale(ms(5000)), isEmpty);
  });
}
