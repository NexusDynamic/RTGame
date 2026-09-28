import 'package:rise_together_game/src/game/game_geometry.dart';

/// A team's "previous best": the highest point they reached before their most
/// recent reset, frozen there until they reset again.
///
/// The freeze is the whole point. The best height a team has reached is
/// available live from [DistanceTracker], but a line drawn at a live best sits
/// on the ball for the entire climb -- it only ever moves while the team is at
/// their best, which is exactly when it is under them. Publishing it on reset
/// instead gives the mark the meaning the player expects: *last time, you got
/// this far.*
///
/// Everything here is in world y, which is negative-up, so "higher" is
/// `<`. That is per-level: y is measured from each level's own floor, so the
/// mark is cleared whenever the level changes (see [clear]).
class HighWaterMark {
  HighWaterMark({double? armHeight, double? spawnTolerance})
    : armHeight = armHeight ?? GameGeometry.levelWidth * 0.1,
      spawnTolerance = spawnTolerance ?? GameGeometry.ballRadius * 2;

  /// How far above spawn the ball must climb before a return to spawn counts
  /// as a reset.
  ///
  /// The reset counter is the primary signal, but it is raised by the contact
  /// handler on whichever devices run that contact, and a follower's ball is
  /// positioned from the network rather than by its own collisions. The
  /// teleport back to spawn, on the other hand, is visible on every device in
  /// every mode, so it backs the counter up. It needs this arming band to tell
  /// a reset from a ball merely bouncing on the paddle, which is at spawn
  /// height and does it constantly.
  final double armHeight;

  /// How close to spawn y counts as being at spawn.
  final double spawnTolerance;

  double? _best;
  double? _mark;
  bool _armed = false;
  bool _awaitingSpawn = false;
  int? _lastResetCount;

  /// The y to draw the line at, or null when the team has no previous attempt
  /// on this level.
  double? get mark => _mark;

  /// The best height reached so far, published or not. Exposed for tests and
  /// for callers that want the live figure.
  double? get best => _best;

  /// Feed one frame.
  ///
  /// [resetCount] is the team's running reset tally (`TournamentManager
  /// .getTeamResets`); any change to it publishes.
  void observe({
    required double ballY,
    required double spawnY,
    required int resetCount,
  }) {
    final atSpawn = (ballY - spawnY).abs() <= spawnTolerance;

    // After a [clear] the ball may still be sitting at the top of the level it
    // just finished: the level index changes a frame or two before the world
    // is rebuilt and the ball put back. Recording that height would publish a
    // mark from the old level -- drawn near the ceiling of the new one -- at
    // the very next teleport. Wait for the ball to come home first.
    if (_awaitingSpawn) {
      _lastResetCount = resetCount;
      if (!atSpawn) return;
      _awaitingSpawn = false;
    }

    if (_best == null || ballY < _best!) _best = ballY;

    final countChanged =
        _lastResetCount != null && resetCount != _lastResetCount;
    _lastResetCount = resetCount;

    if (ballY < spawnY - armHeight) _armed = true;
    final returnedToSpawn = _armed && atSpawn;
    if (returnedToSpawn) _armed = false;

    if (countChanged || returnedToSpawn) _publish(spawnY);
  }

  /// Snapshot the best reached so far as the line to draw.
  ///
  /// A best that never cleared the arming band is not worth a line: at the
  /// start of a level, and after a reset that killed the ball on the way up,
  /// it would be drawn across the paddle.
  void _publish(double spawnY) {
    final best = _best;
    if (best == null || best > spawnY - armHeight) return;
    _mark = best;
  }

  /// Drop everything: a new level, or a new round on the same level. The old
  /// y is not comparable to the new one in either case.
  void clear() {
    _best = null;
    _mark = null;
    _armed = false;
    _awaitingSpawn = true;
  }
}
