import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rise_together_game/src/components/wall.dart';
import 'package:rise_together_game/src/game/action_provider.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/game/distance_tracker.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/game/tournament_manager.dart';
import 'package:rise_together_game/src/game/world_controller.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_game.dart';
import '../helpers/test_helpers.dart';

class _MockContact extends Mock implements Contact {}

/// A device that draws someone else's physics: an online follower.
class _FollowerActionProvider extends LocalActionProvider {
  _FollowerActionProvider(super.actionManager);

  @override
  bool get isCoordinator => false;
}

/// Countdowns on a real game, Box2D included: what runs where, what is held
/// still, and what is released when the game goes away.
void main() {
  setUpAll(silenceLogs);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.initialize();
  });

  Future<TestGame> loadGame(
    WidgetTester tester, {
    bool follower = false,
  }) async {
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
      () => game.configure(
        follower
            ? _FollowerActionProvider(game.actionManager)
            : LocalActionProvider(game.actionManager),
      ),
    );
    return game;
  }

  WorldController playerController(TestGame game) => game
      .worldControllers
      .values
      .firstWhere((c) => c.teamContext.isPlayerTeam);

  Wall fatalWall(WorldController controller) => controller.world.children
      .whereType<Wall>()
      .firstWhere((wall) => wall.isFatal);

  testWidgets('a follower ignores its own ball contacts', (tester) async {
    final game = await loadGame(tester, follower: true);
    expect(game.isAuthoritativePhysics, isFalse);
    final controller = playerController(game);

    controller.world.ball.beginContact(fatalWall(controller), _MockContact());
    await tester.runAsync(() => controller.world.restartLevel());

    expect(game.countdownSystem.isActive, isFalse);
    expect(controller.inputLocked, isFalse);
    expect(game.tournamentManager.getTeamResets(0), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the authority holds the start pose through a countdown', (
    tester,
  ) async {
    final game = await loadGame(tester);
    final controller = playerController(game);
    final world = controller.world;

    var prepared = false;
    late Future<void> countdown;
    await tester.runAsync(() async {
      countdown = game.runTeamCountdown(
        0,
        reason: 'test',
        prepare: () async {
          // The lock is already in place while the world is prepared.
          expect(controller.inputLocked, isTrue);
          expect(game.acceptsInputFor(0), isFalse);
          prepared = true;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(prepared, isTrue);
    expect(game.countdownSystem.isActive, isTrue);

    // Whatever moves the paddle mid-countdown is undone on the next step.
    world.paddle.body.linearVelocity = Vector2(0, -5);
    world.paddle.setPosition(world.paddle.startPosition + Vector2(0, -1));
    world.paddle.applyPendingTransforms();
    world.update(1 / 60);
    expect(
      world.paddle.position.y,
      closeTo(
        world.paddle.startPosition.y,
        WorldController.lockedPoseTolerance,
      ),
    );
    expect(world.paddle.body.linearVelocity.length, 0);

    game.countdownSystem.cancel();
    await tester.runAsync(() => countdown);
    expect(controller.inputLocked, isFalse);
    expect(game.acceptsInputFor(0), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removing a game frees its physics worlds', (tester) async {
    // Box2D has a fixed table of worlds; a game that keeps its two after it
    // is gone makes roughly the 65th game of an app launch fail to load.
    final game = await loadGame(tester);
    final worlds = [
      game.world,
      for (final controller in game.worldControllers.values) controller.world,
    ].whereType<Forge2DWorld>().map((w) => w.physicsWorld).toList();
    expect(worlds, isNotEmpty);
    expect(worlds.every((w) => w.isValid), isTrue);

    await tester.pumpWidget(const SizedBox());

    expect(worlds.every((w) => !w.isValid), isTrue);
  });
}
