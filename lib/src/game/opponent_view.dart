import 'dart:ui';

/// The rules governing the single-view opponent display.
///
/// When `ui.single_view_opponent` is on, the opponent is no longer given a
/// viewport of their own: their ball and paddle are drawn as translucent
/// ghosts inside the player's arena, and an edge cue reports them when they
/// are not on screen. Both worlds share one coordinate system (every level is
/// built origin-centred by `RiseTogetherWorld._addBoundaries`), so no
/// remapping is involved -- but two things about that coordinate system make
/// the decisions below easy to get wrong in a way nothing on screen reveals:
///
///  * **y is negative-up.** "Above" is `y < top`, not `y > top`. Written the
///    intuitive way the arrow points at the floor when the opponent is
///    overhead, and passes review because the code reads correctly.
///  * **y is measured from each level's own floor.** Across a level boundary
///    the same y means different progress, so an opponent who has just
///    cleared a level and restarted at the bottom of the next one would be
///    drawn at the floor while being a whole level ahead.
///
/// Extracted here, rather than left inline in the components, so both are
/// named and testable -- the same reason [PhysicsChannels] exists.
abstract final class OpponentView {
  /// Whether the ghost body may be drawn at all.
  ///
  /// Only when both teams are climbing the same level; see the class docs for
  /// why a cross-level ghost is worse than no ghost. The cue takes over in
  /// that case and carries the level delta explicitly.
  static bool shouldShowGhost({
    required int myLevelIndex,
    required int oppLevelIndex,
  }) => myLevelIndex == oppLevelIndex;

  /// The edge cue, or null when the opponent needs no annotation because they
  /// are level-matched and on screen.
  ///
  /// [visibleWorldRect] is the camera's visible region in world space, and
  /// [oppBallY] the opponent ball's world y -- both negative-up. [levelDelta]
  /// and [metresDelta] are opponent-minus-mine, so positive means ahead.
  static OpponentCue? cue({
    required Rect visibleWorldRect,
    required double oppBallY,
    required int levelDelta,
    required double metresDelta,
    required double levelSpanMetres,
  }) {
    if (levelDelta != 0) {
      // The ghost is suppressed, so the cue is the only thing reporting the
      // opponent: always emit it, and take the direction from the level
      // difference rather than from a y that is not comparable. A whole level
      // apart is the top of the colour ramp by definition.
      return (
        up: levelDelta > 0,
        levelDelta: levelDelta,
        metresDelta: metresDelta,
        intensity: 1.0,
      );
    }

    final intensity = _intensity(metresDelta, levelSpanMetres);

    // Negative-up: the top edge of the view is the SMALLER y.
    if (oppBallY < visibleWorldRect.top) {
      return (
        up: true,
        levelDelta: 0,
        metresDelta: metresDelta,
        intensity: intensity,
      );
    }
    if (oppBallY > visibleWorldRect.bottom) {
      return (
        up: false,
        levelDelta: 0,
        metresDelta: metresDelta,
        intensity: intensity,
      );
    }
    return null;
  }

  /// How far along the colour ramp a same-level gap sits, in `[0, 1]`.
  ///
  /// The ramp is normalised against one level's worth of climb
  /// ([levelSpanMetres] = the level's world height times the distance
  /// tracker's multiplier), so it reaches its end exactly where the level
  /// delta would take over and pin it there. Levels differ in height by a
  /// factor of six, so a fixed metre span would saturate on the first stride
  /// of Level 1 and never leave the low end on Level 6.
  static double _intensity(double metresDelta, double levelSpanMetres) {
    if (!levelSpanMetres.isFinite || levelSpanMetres <= 0) return 1.0;
    return (metresDelta.abs() / levelSpanMetres).clamp(0.0, 1.0);
  }

  /// Ahead and only just off screen.
  static const Color aheadNear = Color(0xFFFFD23F); // yellow
  /// Ahead by a level or more.
  static const Color aheadFar = Color(0xFFFF3B30); // red
  /// Behind and only just off screen.
  static const Color behindNear = Color(0xFF2FD3C4); // blue-green
  /// Behind by a level or more.
  static const Color behindFar = Color(0xFF3DDC5C); // green

  /// The cue's colour: hotter the further ahead the opponent is, cooler the
  /// further behind, with the two ends of each ramp fixed by [aheadNear] /
  /// [aheadFar] and [behindNear] / [behindFar].
  static Color colour(OpponentCue cue) => Color.lerp(
    cue.up ? aheadNear : behindNear,
    cue.up ? aheadFar : behindFar,
    cue.intensity,
  )!;

  /// The cue's label, e.g. `+1, 573 m` or just `573 m`.
  ///
  /// The level delta is omitted when zero rather than rendered as `+0`, and
  /// the metre gap is shown unsigned -- the arrow already carries the sign,
  /// and a signed number beside an arrow reads as a contradiction whenever
  /// the two are derived differently (which they are, across a level
  /// boundary: the arrow follows the level, the metres follow the tracker).
  static String label(OpponentCue cue) {
    final metres = '${cue.metresDelta.abs().toStringAsFixed(0)} m';
    if (cue.levelDelta == 0) return metres;
    final sign = cue.levelDelta > 0 ? '+' : '-';
    // Comma, not whitespace: `+1 573 m` reads as one number that has been
    // signed and spaced, which is exactly the misreading to avoid.
    return '$sign${cue.levelDelta.abs()}, $metres';
  }
}

/// A pending edge annotation for the off-screen opponent.
///
/// [up] is the arrow direction -- true when the opponent is ahead of / above
/// the player. [levelDelta] and [metresDelta] are opponent-minus-mine, and
/// [intensity] is the `[0, 1]` position along the colour ramp for whichever
/// direction [up] selects (see [OpponentView.colour]).
typedef OpponentCue = ({
  bool up,
  int levelDelta,
  double metresDelta,
  double intensity,
});
