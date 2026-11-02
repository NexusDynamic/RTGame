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
