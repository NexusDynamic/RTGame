import 'dart:async';

import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';

/// An in-process [GameSession] whose streams tests drive directly.
class FakeGameSession implements GameSession {
  FakeGameSession({this.isAuthority = true, List<PlayerAssignment>? players})
    : assignments =
          players ??
          [
            PlayerAssignment(
              nodeId: 'host',
              nodeName: 'Host',
              teamId: 0,
              playerId: 'host',
              isCoordinator: true,
            ),
            PlayerAssignment(
              nodeId: 'guest',
              nodeName: 'Guest',
              teamId: 1,
              playerId: 'guest',
              isCoordinator: false,
            ),
          ];

  @override
  final bool isAuthority;

  @override
  final List<PlayerAssignment> assignments;

  @override
  PlayerAssignment get localAssignment =>
      assignments.firstWhere((a) => a.isCoordinator == isAuthority);

  final actionsIn = StreamController<PlayerActionMessage>.broadcast();
  final sentActions = <PaddleAction>[];
  final sentEvents = <GameEvent>[];

  @override
  MatchRules rules = const MatchRules(
    mode: MatchMode.versus,
    roundDurationSeconds: 60,
    seed: 1,
  );

  @override
  CustomLevelPack? customLevels;

  @override
  Stream<PlayerActionMessage> get actions => actionsIn.stream;

  @override
  void sendAction(PaddleAction action) => sentActions.add(action);

  @override
  void broadcastEvent(GameEvent event) => sentEvents.add(event);

  @override
  void broadcastPhysics(List<double> state) {}

  @override
  Stream<List<double>> get physics => const Stream.empty();

  @override
  Stream<GameEvent> get events => const Stream.empty();

  @override
  Stream<void> get assignmentsChanged => const Stream.empty();

  @override
  Stream<SessionEnd> get ended => const Stream.empty();

  @override
  Future<void> markReady({int round = 0}) async {}

  @override
  Future<bool> waitForPlayersReady(Duration timeout, {int round = 0}) async =>
      true;

  @override
  Future<void> leave() async => actionsIn.close();
}
