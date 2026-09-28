import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

import 'package:rise_together_game/src/net/network_bridge.dart';

/// Local network implementation for testing without LSL
/// Allows multiple players on the same device
class LocalActionBridge with AppLogging implements NetworkBridge {
  final ActionStreamManager actionManager;

  LocalActionBridge({required this.actionManager});

  /// Initialize local network (no-op for local testing)
  @override
  Future<void> initialize() async {
    appLog.info('Initializing LocalNetworkBridge for local testing');
  }

  /// Send action locally (directly to action stream)
  @override
  void sendAction(int teamId, String playerId, PaddleAction action) {
    appLog.fine('Local action: team=$teamId, player=$playerId, action=$action');

    final teamStream = actionManager.getTeamStream(teamId);
    if (teamStream != null) {
      teamStream.addAction(GameAction(playerId, action));
    } else {
      appLog.warning('No team stream found for team $teamId');
    }
  }

  /// Remove player from local tracking
  @override
  void removePlayer(int teamId, String playerId) {
    appLog.fine('Removing local player: team=$teamId, player=$playerId');
    final teamStream = actionManager.getTeamStream(teamId);
    teamStream?.removePlayer(playerId);
  }

  /// Dispose resources (no-op for local)
  @override
  void dispose() {
    appLog.info('Disposing LocalNetworkBridge');
  }
}
