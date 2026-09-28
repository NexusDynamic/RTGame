import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/distance_tracker.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/game/tournament_manager.dart';
import '../helpers/test_game.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import '../helpers/test_helpers.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Distances recorded during the individual condition were exactly 10x too
/// large in the 2026-08-14 session, while joint distances in the same session
/// were correct.
///
/// The cause was initialisation order, not scaling. `onLoad` initialises the
/// game's own tracker with the scale-compensated multiplier; `setManagers` then
/// *replaces* that tracker with the phase system's, which still carries
/// `DistanceTracker`'s own 100.0 default. Joint mode hid it because
/// `_loadNetworkConfiguration` re-initialises the tracker moments later.
/// Individual mode takes the LocalActionProvider branch and never did.
///
/// The error is a clean factor of [GameGeometry.scale], which makes it easy to
/// mistake for a scaling bug and hard to notice at a glance in a distance
/// column — which is exactly why it is pinned here.
void main() {
  setUpAll(() {
    silenceLogs();
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.initialize();
  });

  test('the configured multiplier is compensated for world scale', () {
    // The raw setting is expressed in pre-scale units, so every consumer must
    // divide by scale rather than using the setting directly.
    expect(GameGeometry.distanceMultiplier(100.0), 100.0 / GameGeometry.scale);
  });

  test('an uninitialised tracker is wrong by exactly the world scale', () {
    final raw = Settings.instance.appSettings.getDouble(
      'game.distance_multiplier',
    );

    final uninitialised = DistanceTracker();
    final initialised = DistanceTracker()
      ..initialize(GameGeometry.distanceMultiplier(raw));

    expect(
      uninitialised.distanceMultiplier,
      initialised.distanceMultiplier * GameGeometry.scale,
      reason:
          'the class default is the raw setting, not the scaled one — so '
          'skipping initialize() overstates every distance by `scale`',
    );

    // The same climb, measured by both.
    for (final tracker in [uninitialised, initialised]) {
      tracker.setStartingHeight(0, -0.5);
      tracker.updateBallPosition(0, -9.846);
    }
    expect(
      uninitialised.getTeamDistance(0),
      closeTo(initialised.getTeamDistance(0) * GameGeometry.scale, 1e-6),
    );
  });

  test('setManagers initialises the tracker it is handed', () {
    // The regression site. A tracker injected by the phase system must not be
    // left on the class default, whichever action provider the phase goes on
    // to use.
    final game = TestGame(actionManager: ActionStreamManager());
    final injected = DistanceTracker();
    expect(
      injected.distanceMultiplier,
      isNot(
        GameGeometry.distanceMultiplier(
          Settings.instance.appSettings.getDouble('game.distance_multiplier'),
        ),
      ),
    );

    game.setManagers(
      tournamentManager: TournamentManager(),
      timeProvider: TimeProvider(),
      distanceTracker: injected,
    );

    expect(
      injected.distanceMultiplier,
      GameGeometry.distanceMultiplier(
        Settings.instance.appSettings.getDouble('game.distance_multiplier'),
      ),
    );
    expect(identical(game.distanceTracker, injected), isTrue);
  });
}
