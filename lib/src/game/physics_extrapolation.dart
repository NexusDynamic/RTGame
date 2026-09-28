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
