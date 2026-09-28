/// Action types that players can contribute to the paddle
enum PaddleAction { left, right, none }

/// Represents a game action from a specific player
class GameAction {
  final String playerId;
  final PaddleAction action;
  final DateTime timestamp;

  GameAction(this.playerId, this.action) : timestamp = DateTime.now();

  @override
  String toString() => 'GameAction($playerId, $action)';
}
