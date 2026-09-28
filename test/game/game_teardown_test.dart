import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rise_together_game/src/game/action_system.dart';
import '../helpers/test_game.dart';
import '../helpers/test_helpers.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';

/// Teardown of a game the phase system is finished with.
///
/// A phase drops its game reference and lets it be collected. Anything the game
/// still owns that holds a callback into the wider app therefore has to be
/// released in onRemove(), or it outlives the phase that created it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    silenceLogs();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.initialize();
  });

  test('onRemove disposes the countdown system', () {
    // Regression: onRemove() left the countdown's Timer.periodic running, so a
    // countdown in flight went on ticking against the torn-down game and kept
    // it reachable.
    final game = TestGame(actionManager: ActionStreamManager());
    final countdown = game.countdownSystem;

    game.onRemove();

    // A disposed ChangeNotifier rejects new listeners; an undisposed one does not.
    expect(() => countdown.addListener(() {}), throwsFlutterError);
  });
}
