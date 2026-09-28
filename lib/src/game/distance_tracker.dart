import 'package:flutter/foundation.dart';
import 'package:rise_together_game/src/attributes/resetable.dart';
import 'package:rise_together_game/src/models/team.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Tracks distance traveled by teams based on ball position
class DistanceTracker extends ChangeNotifier with AppLogging, Resetable {
  double _distanceMultiplier = 100.0; // Default: 100 meters per game unit

  /// Whether [initialize] has been called on this instance.
  ///
  /// The default above is a trap, and it sprang once: under a world scale the
  /// correct multiplier is `raw / scale`, so an uninitialised tracker reports
  /// distances inflated by the scale factor. The phase system injects a fresh
  /// tracker that replaces the one the game initialised, and in individual mode
  /// nothing re-initialised it — every individual-condition distance in the
  /// 2026-08-14 recording is 10x too large. Joint mode happened to re-initialise
  /// milliseconds later and so was always correct, which is what made it look
  /// like a scaling bug rather than an ordering one.
  ///
  /// `setManagers` now initialises whatever tracker it is handed, so this is a
  /// backstop: it makes the same mistake loud instead of silent.
  bool _initialized = false;

  void _warnIfUninitialized() {
    if (_initialized) return;
    _initialized = true; // report once, not once per frame
    appLog.severe(
      'DistanceTracker read before initialize() — using the class default '
      'multiplier $_distanceMultiplier. Under a world scale this reports '
      'distances inflated by the scale factor. See docs/DATA_COMPAT.md.',
    );
  }

  final Map<int, double> _maxDistances =
      {}; // team ID -> max distance in meters
  final Map<int, double> _startingHeights = {}; // team ID -> starting height

  // For throttling UI updates
  DateTime _lastUpdate = DateTime.now();
  // Update UI at most 10x/second. Duration.zero (the previous value) made the
  // throttle check always true, so notifyListeners() fired twice per frame and
  // rebuilt every listening widget at frame rate.
  static const _updateThreshold = Duration(milliseconds: 100);

  // Accumulated distance from all levels completed so far this round
  final Map<int, double> _completedDistance = {};

  double get distanceMultiplier => _distanceMultiplier;
  Map<int, double> get maxDistances => Map.unmodifiable(_maxDistances);

  void initialize(double multiplier) {
    _distanceMultiplier = multiplier;
    _initialized = true;
    appLog.info(
      'Distance tracker initialized with multiplier: $_distanceMultiplier',
    );
  }

  /// Set the starting height for a team when a new level begins.
  /// Does NOT reset cumulative distance — call [saveCompletedDistance] first
  /// to lock in the previous level's contribution before calling this.
  void setStartingHeight(int teamId, double height) {
    _startingHeights[teamId] = height;
    appLog.info('Team $teamId starting height set to $height');
  }

  /// Lock in the current accumulated distance before transitioning to the next
  /// level. Must be called before [setStartingHeight] on level change.
  void saveCompletedDistance(int teamId) {
    _completedDistance[teamId] = _maxDistances[teamId] ?? 0.0;
    appLog.info(
      'Team $teamId completed level distance saved: ${_completedDistance[teamId]?.toStringAsFixed(1)}m',
    );
  }

  /// The team's distance at [currentHeight] right now, in metres, with no
  /// high-water mark applied.
  ///
  /// [getTeamDistance] reports the best the team has ever reached, which is
  /// the right number to score and to log. It is the wrong number for anything
  /// that answers "where are they *now*", because it does not come back down
  /// when the ball does. Levels already completed are still folded in, so two
  /// teams' live distances stay comparable across a level boundary in the way
  /// their raw y coordinates do not.
  double getLiveTeamDistance(int teamId, double currentHeight) {
    final startHeight = _startingHeights[teamId] ?? 0.0;
    final relativeHeight = currentHeight.abs() - startHeight.abs();
    final currentLevelDist = relativeHeight > 0
        ? relativeHeight * _distanceMultiplier
        : 0.0;
    return (_completedDistance[teamId] ?? 0.0) + currentLevelDist;
  }

  /// Update the current ball position for a team and track cumulative distance
  void updateBallPosition(int teamId, double currentHeight) {
    _warnIfUninitialized();
    final totalDist = getLiveTeamDistance(teamId, currentHeight);

    if (totalDist > (_maxDistances[teamId] ?? 0.0)) {
      _maxDistances[teamId] = totalDist;
      _pendingNotify = true;
    }

    // Throttle UI updates to avoid excessive redraws.
    //
    // The change flag must not bypass the throttle: while a ball is climbing,
    // the distance increases on virtually every frame, so an "OR changed"
    // condition notified at frame rate no matter what the interval was.
    if (!_pendingNotify) return;
    final now = DateTime.now();
    if (now.difference(_lastUpdate) < _updateThreshold) return;

    _lastUpdate = now;
    _pendingNotify = false;
    notifyListeners();
  }

  /// True when a distance change has not yet been published to listeners.
  bool _pendingNotify = false;

  /// Publish any throttled change immediately.
  ///
  /// Call at round end so the final distance is not left sitting in the
  /// throttle window when updates stop arriving.
  void flushPendingNotification() {
    if (!_pendingNotify) return;
    _pendingNotify = false;
    _lastUpdate = DateTime.now();
    notifyListeners();
  }

  /// Get the current max distance for a team in meters
  double getTeamDistance(int teamId) {
    return _maxDistances[teamId] ?? 0.0;
  }

  /// Get formatted distance string for display
  String getFormattedDistance(int teamId, {bool includeUnit = false}) {
    final distance = getTeamDistance(teamId);
    if (!includeUnit) {
      return distance.toStringAsFixed(1);
    }
    return '${distance.toStringAsFixed(1)} m';
  }

  /// Get the current max distance for a team by Team enum
  double getDistanceForTeam(Team team) {
    return getTeamDistance(team.id);
  }

  /// Get formatted distance string for display by Team enum
  String getFormattedDistanceForTeam(Team team) {
    return getFormattedDistance(team.id);
  }

  /// Set starting height by Team enum
  void setStartingHeightForTeam(Team team, double height) {
    setStartingHeight(team.id, height);
  }

  /// Update ball position by Team enum
  void updateBallPositionForTeam(Team team, double currentHeight) {
    updateBallPosition(team.id, currentHeight);
  }

  /// Get both team distances for level completion
  Map<int, double> getAllDistances() {
    return Map.from(_maxDistances);
  }

  @override
  void reset() {
    _maxDistances.clear();
    _startingHeights.clear();
    _completedDistance.clear();
    for (final team in Team.values) {
      _maxDistances[team.id] = 0.0;
      _startingHeights[team.id] = 0.0;
      _completedDistance[team.id] = 0.0;
    }
    appLog.info('Distance tracker reset');
    notifyListeners();
  }

  /// Full reset of distance state (used for forced level advance).
  void resetDistances() {
    for (final team in Team.values) {
      _maxDistances[team.id] = 0.0;
      _completedDistance[team.id] = 0.0;
    }
    appLog.info(
      'Distance tracker distances reset - startingHeights: $_startingHeights',
    );
    notifyListeners();
  }
}
