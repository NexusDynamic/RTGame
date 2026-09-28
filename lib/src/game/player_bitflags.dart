import 'package:rise_together_game/src/net/player_assignment.dart';

/// One player's press-indicator bit.
class PlayerBitflag {
  const PlayerBitflag({
    required this.nodeId,
    required this.teamId,
    required this.playerId,
    required this.bitflagValue,
    required this.index,
  });

  final String nodeId;
  final int teamId;
  final String playerId;

  /// `1 << index`. Packed into physics channels 6 and 7, so this value is
  /// what appears in recorded data.
  final int bitflagValue;

  /// Position in the deterministic ordering.
  final int index;

  Map<String, dynamic> toMap() => {
    'nodeId': nodeId,
    'teamId': teamId,
    'playerId': playerId,
    'bitflagValue': bitflagValue,
    'index': index,
  };

  @override
  String toString() =>
      'PlayerBitflag($playerId team=$teamId bit=$bitflagValue)';
}

/// Assigns each player a bit for the press indicators.
///
/// The ordering is load-bearing for the recorded data, not just the UI: these
/// values are packed into physics channels 6 and 7 and broadcast every frame,
/// so which player owns which bit determines what a recording means. An
/// unstable ordering would make bitflag columns incomparable across sessions.
///
/// Extracted from `initPlayerBitflags` so that guarantee is stated and tested
/// rather than implied by a sort call in the middle of a game class.
abstract final class PlayerBitflags {
  /// Bits are assigned by team, then by node id.
  ///
  /// Both keys matter. Team first groups a team's bits contiguously; node id
  /// breaks ties deterministically, so two devices computing this list
  /// independently agree — which they must, because each participant runs this
  /// locally against the roster it received.
  ///
  /// Note the index is **global**, not per team: with four players, team 0
  /// gets bits 1 and 2 while team 1 gets 4 and 8. Decoding a recording
  /// therefore needs the roster, not just the team.
  static List<PlayerBitflag> assign(List<PlayerAssignment> players) {
    final sorted = List<PlayerAssignment>.from(players)
      ..sort((a, b) {
        final byTeam = a.teamId.compareTo(b.teamId);
        if (byTeam != 0) return byTeam;
        return a.nodeId.compareTo(b.nodeId);
      });

    return [
      for (var i = 0; i < sorted.length; i++)
        PlayerBitflag(
          nodeId: sorted[i].nodeId,
          teamId: sorted[i].teamId,
          playerId: sorted[i].playerId,
          bitflagValue: 1 << i,
          index: i,
        ),
    ];
  }

  /// How many players can be assigned before the bit no longer survives the
  /// float32 physics channel.
  ///
  /// Channels 6 and 7 are float32, which represents integers exactly only up
  /// to 2^24. `1 << 24` is the first value that could be perturbed, so 24
  /// players is the ceiling. The session cap is 16, so this is headroom rather
  /// than a live constraint — but it is the reason the cap cannot simply be
  /// raised without also changing the channel type.
  static const maxPlayers = 24;

  static bool fitsInChannel(int playerCount) => playerCount <= maxPlayers;
}
