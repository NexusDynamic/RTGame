import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/distance_tracker.dart';
import '../helpers/test_helpers.dart';

/// The off-screen opponent cue asks "how far apart are the two balls *right
/// now*", which is not the question [DistanceTracker.getTeamDistance] answers:
/// that one is a high-water mark, and it does not come back down when the ball
/// does. An opponent who peaked high and then fell would otherwise keep both
/// the large gap and the hot colour until the player climbed past them.
void main() {
  setUpAll(() {
    silenceLogs();
  });

  const teamId = 0;

  DistanceTracker trackerAt(double startHeight) => DistanceTracker()
    ..initialize(10.0)
    ..setStartingHeight(teamId, startHeight);

  test('reports the height the ball is at, not the height it reached', () {
    final tracker = trackerAt(-0.5);

    tracker.updateBallPosition(teamId, -20.5); // climb: 20 units above spawn
    expect(tracker.getTeamDistance(teamId), 200.0);

    tracker.updateBallPosition(teamId, -5.5); // fall back to 5 units
    expect(
      tracker.getTeamDistance(teamId),
      200.0,
      reason: 'the high-water mark holds',
    );
    expect(tracker.getLiveTeamDistance(teamId, -5.5), 50.0);
  });

  test('agrees with the high-water mark while the ball is at its best', () {
    final tracker = trackerAt(-0.5);
    tracker.updateBallPosition(teamId, -20.5);
    expect(
      tracker.getLiveTeamDistance(teamId, -20.5),
      tracker.getTeamDistance(teamId),
    );
  });

  test('folds in levels already completed, so it survives a level change', () {
    final tracker = trackerAt(-0.5);
    tracker.updateBallPosition(teamId, -10.5); // 100 m on level one
    tracker.saveCompletedDistance(teamId);
    tracker.setStartingHeight(teamId, -0.5); // level two, floor reset

    // Standing at the bottom of the new level is still 100 m of climb.
    expect(tracker.getLiveTeamDistance(teamId, -0.5), 100.0);
    expect(tracker.getLiveTeamDistance(teamId, -3.5), 130.0);
  });

  test('never goes negative below the spawn height', () {
    final tracker = trackerAt(-5.0);
    expect(tracker.getLiveTeamDistance(teamId, -1.0), 0.0);
  });

  test('is the same arithmetic updateBallPosition uses', () {
    // The two must not drift apart: updateBallPosition is the recorded
    // distance, and this is the live view of the same quantity.
    final tracker = trackerAt(-0.5);
    for (final y in [-0.5, -3.0, -12.75, -40.0]) {
      tracker.updateBallPosition(teamId, y);
      expect(
        tracker.getLiveTeamDistance(teamId, y),
        tracker.getTeamDistance(teamId),
        reason: 'climbing monotonically, so the mark is the live value at y=$y',
      );
    }
  });
}
