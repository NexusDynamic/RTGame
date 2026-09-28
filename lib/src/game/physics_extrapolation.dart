/// Projecting a follower's physics state forward when samples run out.
///
/// Used by `SnapshotInterpolator` once its render time passes the newest
/// sample. A free function over doubles so the arithmetic is testable without
/// a game.
library;

/// [value] advanced by the velocity implied by [previousValue] over [span].
///
/// Returns [value] unchanged when there is nothing to project from: no lead, a
/// non-positive span (two samples sharing a timestamp, which the inlet's
/// per-tick clock makes ordinary), or a non-finite input. Never invents motion
/// from a single sample.
double projectChannel({
  required double value,
  required double previousValue,
  required double span,
  required double lead,
}) {
  if (lead <= 0.0 || span <= 0.0) return value;
  if (!value.isFinite || !previousValue.isFinite) return value;
  final projected = value + ((value - previousValue) / span) * lead;
  return projected.isFinite ? projected : value;
}

/// Whether two consecutive samples are a teleport rather than motion.
///
/// Resets and level loads move the ball and paddle straight back to the start,
/// and the "velocity" between the samples either side of that is the whole
/// jump over one broadcast period. Projecting it is never right. [dx], [dy] are
/// the displacement between the two samples, in world units; anything longer
/// than [maxJump] counts. Non-finite input counts too, since projecting from it
/// cannot produce anything sensible.
bool isDiscontinuity({
  required double dx,
  required double dy,
  required double maxJump,
}) {
  if (!dx.isFinite || !dy.isFinite) return true;
  return dx * dx + dy * dy > maxJump * maxJump;
}
