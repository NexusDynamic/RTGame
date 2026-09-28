import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/action_provider.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/game/distance_tracker.dart';
import 'package:rise_together_game/src/game/level_sequence.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/game/rise_together_levels.dart';
import 'package:rise_together_game/src/game/tournament_manager.dart';
import 'package:rise_together_game/src/components/level_object.dart';
import 'package:rise_together_game/src/levels/custom_level.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_game.dart';
import '../helpers/test_helpers.dart';

/// A real game, Box2D included, started part-way up a sequence.
void main() {
  setUpAll(silenceLogs);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.initialize();
  });

  Future<TestGame> loadGame(WidgetTester tester) async {
    final game = TestGame(actionManager: ActionStreamManager());
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(
          game: game,
          overlayBuilderMap: {
            for (final id in const ['inGameUI', 'countdown'])
              id: (_, _) => const SizedBox(),
          },
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 500 && !game.isLoaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(game.isLoaded, isTrue);
    game.setManagers(
      tournamentManager: TournamentManager(),
      timeProvider: TimeProvider(),
      distanceTracker: DistanceTracker(),
    );
    await tester.runAsync(
      () => game.configure(LocalActionProvider(game.actionManager)),
    );
    return game;
  }

  testWidgets('an untimed solo run can start at a later level', (tester) async {
    final game = await loadGame(tester);
    await tester.runAsync(
      () => game.startGameDirect(
        mode: GameMode.individual,
        durationSeconds: null,
        startLevelIndex: 4,
        seed: 7,
      ),
    );

    expect(game.timeProvider.isTimed, isFalse);
    expect(game.tournamentManager.getTeamLevelIndex(0), 4);
    for (final controller in game.worldControllers.values) {
      expect(controller.currentLevelIndex, 4);
      expect(controller.world.lastLoadedLevel, isA<Level5>());
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a custom sequence is built exactly as authored', (tester) async {
    final game = await loadGame(tester);
    final level = CustomLevel.create(
      heightMultiplier: 3,
      objects: [
        CustomObject.create(
          type: CustomObjectType.powerupWidth,
          x: -3,
          y: 20,
          param: 1.5,
          levelHeight: 30,
        )!,
      ],
    )!;
    await tester.runAsync(
      () => game.startGameDirect(
        mode: GameMode.individual,
        durationSeconds: 60,
        sequence: LevelSequence.custom([level, level]),
      ),
    );
    await tester.pump();

    expect(game.levelSequence.isCustom, isTrue);
    final world = game.worldControllers.values.first.world;
    final objects = world.children.whereType<LevelObject>().toList();
    expect(objects, hasLength(1));
    expect(objects.single, isA<PaddleWidthPowerup>());
    expect(objects.single.position.x, -3);
    expect(objects.single.position.y, -20);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('finishing the last level ends an untimed run', (tester) async {
    final game = await loadGame(tester);
    var finished = 0;
    final completed = <int>[];
    game.onSequenceCompleted = () => finished++;
    game.onTeamLevelCompleted = (_, level) => completed.add(level);
    await tester.runAsync(
      () => game.startGameDirect(
        mode: GameMode.individual,
        durationSeconds: null,
        sequence: LevelSequence.custom([
          CustomLevel.create(heightMultiplier: 1)!,
        ]),
      ),
    );
    final controller = game.worldControllers.values.firstWhere(
      (c) => c.teamContext.teamId == 0,
    );

    await tester.runAsync(() async {
      controller.onLevelCompleted!();
      await Future<void>.delayed(Duration.zero);
    });

    expect(completed, [0]);
    expect(finished, 1);
    expect(game.tournamentManager.individualConditionResult, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a timed run stays on the last level', (tester) async {
    final game = await loadGame(tester);
    var finished = 0;
    game.onSequenceCompleted = () => finished++;
    await tester.runAsync(
      () => game.startGameDirect(
        mode: GameMode.individual,
        durationSeconds: 60,
        sequence: LevelSequence.custom([
          CustomLevel.create(heightMultiplier: 1)!,
        ]),
      ),
    );
    final controller = game.worldControllers.values.firstWhere(
      (c) => c.teamContext.teamId == 0,
    );
    await tester.runAsync(() async {
      controller.onLevelCompleted!();
      await Future<void>.delayed(Duration.zero);
    });
    expect(finished, 0);
    expect(game.isGameRunning, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
