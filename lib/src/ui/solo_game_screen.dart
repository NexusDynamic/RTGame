import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flame/game.dart' as flame;
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/game/action_provider.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/game/distance_tracker.dart';
import 'package:rise_together_game/src/game/interactive_game.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart'
    show GameMode, TimeProvider;
import 'package:rise_together_game/src/game/tournament_manager.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:rise_together_game/src/ui/countdown_overlay.dart';
import 'package:rise_together_game/src/ui/in_game_ui.dart';
import 'package:rise_together_game/src/ui/quit_button.dart';
import 'package:rise_together_game/src/ui/results_card.dart';

/// Solo play: one player, local physics, the opponent's half blacked out.
class SoloGameScreen extends StatefulWidget {
  const SoloGameScreen({super.key});

  @override
  State<SoloGameScreen> createState() => _SoloGameScreenState();
}

class _SoloGameScreenState extends State<SoloGameScreen>
    with AppLogging, AppSettings {
  /// Bumped on every restart so the GameWidget gets a fresh key and Flame
  /// tears the old game down.
  int _generation = 0;

  InteractiveGame? _game;
  IndividualConditionResult? _result;
  bool _newBest = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final game = InteractiveGame(actionManager: ActionStreamManager());
    setState(() {
      _game = game;
      _result = null;
      _newBest = false;
    });

    // Flame runs onLoad() once the GameWidget is mounted, so wait for it.
    while (!game.isLoaded) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted || _game != game) return;
    }

    game.setManagers(
      tournamentManager: TournamentManager(),
      timeProvider: TimeProvider(),
      distanceTracker: DistanceTracker(),
    );
    game.onTimeUp = () => _onTimeUp(game);

    await game.configure(LocalActionProvider(game.actionManager));
    if (!mounted || _game != game) return;

    await game.startGameDirect(
      mode: GameMode.individual,
      durationSeconds: appSettings.getDouble('game.round_duration'),
      skipCountdown: false,
    );
  }

  void _onTimeUp(InteractiveGame game) {
    final result = game.tournamentManager.individualConditionResult;
    if (result == null || !mounted) return;

    final bestLevel = appSettings.getInt('player.best_solo_level');
    final bestDistance = appSettings.getDouble('player.best_solo_distance');
    final isBest =
        result.finalLevelIndex > bestLevel ||
        (result.finalLevelIndex == bestLevel &&
            result.finalDistance > bestDistance);
    if (isBest) {
      appSettings.setInt('player.best_solo_level', result.finalLevelIndex);
      appSettings.setDouble('player.best_solo_distance', result.finalDistance);
    }

    setState(() {
      _result = result;
      _newBest = isBest;
    });
  }

  void _restart() {
    _game?.onTimeUp = null;
    _generation++;
    unawaited(_boot());
  }

  @override
  void dispose() {
    _game?.onTimeUp = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final result = _result;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (game == null)
            const Center(child: CircularProgressIndicator())
          else
            flame.GameWidget(
              key: ValueKey('solo_game_$_generation'),
              game: game,
              overlayBuilderMap: {
                InGameUI.overlayID: (context, g) =>
                    InGameUI(g as InteractiveGame),
                CountdownOverlay.overlayID: (context, g) =>
                    CountdownOverlay(g as InteractiveGame),
              },
            ),
          if (result == null)
            const SafeArea(
              child: Align(alignment: Alignment.topLeft, child: QuitButton()),
            )
          else
            ResultsCard(
              title: 'results.timeUp'.tr(),
              highlight: _newBest ? 'results.newBest'.tr() : null,
              rows: [
                (
                  'results.levelReached'.tr(),
                  'results.level'.tr(
                    args: [(result.finalLevelIndex + 1).toString()],
                  ),
                ),
                (
                  'results.distance'.tr(),
                  '${result.finalDistance.toStringAsFixed(1)} m',
                ),
              ],
              onPlayAgain: _restart,
              onBackToMenu: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }
}
