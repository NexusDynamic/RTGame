import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/network_bridge.dart';

/// Sends the local player's input to the session's authority.
class SessionActionBridge implements NetworkBridge {
  SessionActionBridge(this.session);

  final GameSession session;

  @override
  Future<void> initialize() async {}

  /// Only the action is sent: the authority attributes it to whichever peer
  /// the transport says sent it, so [teamId] and [playerId] are not trusted
  /// and not transmitted.
  @override
  void sendAction(int teamId, String playerId, PaddleAction action) =>
      session.sendAction(action);

  /// Players leave by leaving the session; the authority drops their input
  /// when the roster changes.
  @override
  void removePlayer(int teamId, String playerId) {}

  @override
  void dispose() {}
}
