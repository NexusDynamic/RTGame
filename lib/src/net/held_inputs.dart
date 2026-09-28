import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';

/// The host's view of what each remote player is holding, and for how long it
/// has not heard so.
///
/// Players re-send their current action every few hundred milliseconds. One
/// whose app is suspended (backgrounded on a phone, a throttled browser tab)
/// goes quiet mid-press, and without this the host would apply that press
/// until the heartbeat dropped them: a paddle driving itself for seconds.
class HeldInputs {
  HeldInputs({required this.staleAfter});

  /// Silence after which a held press counts as released.
  final Duration staleAfter;

  final Map<String, _Held> _held = {};

  /// [player] reported [action] at [now] (any monotonic clock).
  void record(PlayerAssignment player, PaddleAction action, Duration now) {
    _held[player.nodeId] = _Held(player, action, now);
  }

  /// Players still holding a press with nothing heard for [staleAfter] as of
  /// [now]. Each is returned once and then counts as released, until the
  /// player is heard from again.
  List<PlayerAssignment> takeStale(Duration now) {
    final stale = [
      for (final held in _held.values)
        if (held.action != PaddleAction.none && now - held.heardAt > staleAfter)
          held.player,
    ];
    for (final player in stale) {
      _held[player.nodeId] = _Held(
        player,
        PaddleAction.none,
        _held[player.nodeId]!.heardAt,
      );
    }
    return stale;
  }

  /// Forget [nodeId], e.g. when it leaves.
  void remove(String nodeId) => _held.remove(nodeId);
}

class _Held {
  const _Held(this.player, this.action, this.heardAt);

  final PlayerAssignment player;
  final PaddleAction action;
  final Duration heardAt;
}
