import 'package:rise_together_game/src/models/player_action.dart';

/// Where the local player's input goes.
///
/// Solo play feeds it straight into the team's action stream
/// ([LocalActionBridge]); online play sends it to the authority
/// ([SessionActionBridge]).
abstract class NetworkBridge {
  Future<void> initialize();
  void sendAction(int teamId, String playerId, PaddleAction action);
  void removePlayer(int teamId, String playerId);
  void dispose();
}
