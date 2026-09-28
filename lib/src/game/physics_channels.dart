/// The PhysicsState channel layout, and the decisions made against it.
///
/// This is a wire contract: these float32 channels appear verbatim in recorded
/// LSL data and in `PHYSICS_STATE_BROADCAST` / `PHYSICS_STATE_RECEIVED` log
/// rows. Changing an index or its meaning invalidates existing analysis — see
/// docs/DATA_COMPAT.md.
///
/// Every documented failure in this area came from logic that lived inline
/// here as bare integer offsets:
///
///  * change detection compared each value against the slot of its *first*
///    occurrence rather than its own, so real input changes read as
///    "unchanged" and were never broadcast;
///  * the snapshot path re-ran the state refresh for its side effect, shifting
///    the change-detection baseline twice in one tick;
///  * a 16-channel outlet surviving into a 32-channel phase produced an
///    `ArgumentError` on every frame.
///
/// Extracted so those decisions are named and testable rather than implied by
/// arithmetic at four call sites.
abstract final class PhysicsChannels {
  // --- layout ---------------------------------------------------------------

  /// Channels describing one team.
  static const perTeam = 8;

  static const teamsPerMatch = 2;

  /// A single match: 2 teams × 8. Joint and individual modes send exactly this.
  static const perMatch = perTeam * teamsPerMatch; // 16

  /// Parallel 1v1 sends two matches side by side.
  static const matchesInOneVOne = 2;
  static const oneVOneTotal = perMatch * matchesInOneVOne; // 32

  // --- channel indices, relative to a team's slice --------------------------

  static const ballX = 0;
  static const ballY = 1;
  static const ballRotation = 2;
  static const paddleY = 3;
  static const paddleAngle = 4;
  static const paddleWidthMultiplier = 5;

  /// Left/right press indicators, packed as bitflags and widened to double.
  static const leftBitflags = 6;
  static const rightBitflags = 7;

  /// Where [teamId]'s slice starts within a match block.
  static int offsetForTeam(int teamId) => teamId * perTeam;

  // --- decisions ------------------------------------------------------------

  /// Whether [length] is a shape this game knows how to read.
  static bool isValidLength(int length) =>
      length == perMatch || length == oneVOneTotal;

  /// The range of [state] belonging to [matchId], or null when the sample is
  /// not a shape we understand.
  ///
  /// A 16-channel sample is a single match and is returned whole; a 32-channel
  /// sample is parallel 1v1 and is sliced. Returning null rather than throwing
  /// keeps a malformed sample from escaping the inbox listener and cancelling
  /// the subscription, which would stop all physics for the rest of the round.
  static ({int start, int end})? sliceForMatch(int length, int matchId) {
    if (length == perMatch) return (start: 0, end: perMatch);
    if (length == oneVOneTotal) {
      if (matchId < 0 || matchId >= matchesInOneVOne) return null;
      final start = matchId * perMatch;
      return (start: start, end: start + perMatch);
    }
    return null;
  }

  /// Whether a team's slice is unchanged, element by element.
  ///
  /// Deliberately exact rather than tolerance-based: the bitflag channels are
  /// integers widened to double, and a tolerance would swallow a single-player
  /// press. The predecessor used `every((v) => v == previous[current.indexOf(v)])`,
  /// which compared each value against the slot of its first occurrence — and
  /// with `0.0` recurring 3–5× at rest, that reported "unchanged" for states
  /// that had genuinely changed.
  static bool sliceUnchanged(List<double> current, List<double> previous) {
    if (current.length != previous.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != previous[i]) return false;
    }
    return true;
  }
}
