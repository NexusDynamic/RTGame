import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flame/game.dart' as flame;
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/game/action_provider.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/game/distance_tracker.dart';
import 'package:rise_together_game/src/game/interactive_game.dart';
import 'package:rise_together_game/src/game/level_sequence.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart'
    show GameMode, TimeProvider;
import 'package:rise_together_game/src/game/tournament_manager.dart';
import 'package:rise_together_game/src/levels/solo_progress.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/services/audio_manager.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:rise_together_game/src/ui/audio_toggles.dart';
import 'package:rise_together_game/src/ui/countdown_overlay.dart';
import 'package:rise_together_game/src/ui/in_game_ui.dart';
import 'package:rise_together_game/src/ui/quit_button.dart';
import 'package:rise_together_game/src/ui/results_card.dart';

/// How a solo run ended.
enum _RunEnd { timeUp, completed, quit }

/// Solo play: one player, local physics, the opponent's half blacked out.
class SoloGameScreen extends StatefulWidget {
  const SoloGameScreen({
    super.key,
    this.timed = true,
    this.startLevelIndex = 0,
    this.sequence,
    this.customRunKey,
  });

  /// False plays until the last level is finished or the player quits.
  final bool timed;

  /// Where in the sequence the run starts.
  final int startLevelIndex;

  /// Custom levels to play; null plays the built-in ones.
  final LevelSequence? sequence;

  /// Best-time key for a custom [sequence]; null records no time (e.g. a
  /// test play from the editor).
  final String? customRunKey;

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
  _RunEnd? _end;
  double _elapsed = 0;
  bool _newBest = false;

  final _progress = SoloProgress();

  bool get _builtIn => widget.sequence == null;

  @override
  void initState() {
    super.initState();
    unawaited(AudioManager.instance.enterMusicScene(MusicScene.game));
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final game = InteractiveGame(actionManager: ActionStreamManager());
    setState(() {
      _game = game;
      _result = null;
      _end = null;
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
    game.onTimeUp = () => _onRunEnded(game, _RunEnd.timeUp);
    game.onSequenceCompleted = () => _onRunEnded(game, _RunEnd.completed);
    if (_builtIn) {
      game.onTeamLevelCompleted = (_, levelIndex) =>
          unawaited(_progress.recordCompleted(levelIndex));
    }

    await game.configure(LocalActionProvider(game.actionManager));
    if (!mounted || _game != game) return;

    await game.startGameDirect(
      mode: GameMode.individual,
      durationSeconds: widget.timed
          ? appSettings.getDouble('game.round_duration')
          : null,
      startLevelIndex: widget.startLevelIndex,
      sequence: widget.sequence,
      skipCountdown: false,
    );
  }

  String? get _runKey => _builtIn
      ? SoloProgress.builtInRunKey(widget.startLevelIndex)
      : widget.customRunKey;

  Future<void> _onRunEnded(InteractiveGame game, _RunEnd end) async {
    final result = game.tournamentManager.individualConditionResult;
    if (result == null || !mounted) return;
    final elapsed = game.timeProvider.elapsedTime;

    var isBest = false;
    switch (end) {
      case _RunEnd.timeUp:
        // Only a full run from the bottom counts as a best score.
        if (_builtIn && widget.startLevelIndex == 0) {
          isBest = _recordBestScore(result);
        }
      case _RunEnd.completed:
        final key = _runKey;
        if (key != null) isBest = await _progress.recordTime(key, elapsed);
      case _RunEnd.quit:
        break;
    }

    if (!mounted) return;
    setState(() {
      _result = result;
      _end = end;
      _elapsed = elapsed;
      _newBest = isBest;
    });
  }

  bool _recordBestScore(IndividualConditionResult result) {
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
    return isBest;
  }

  Future<void> _endUntimedRun() async {
    final game = _game;
    if (game == null || !game.isGameRunning) return;
    game.completeIndividualCondition();
    await _onRunEnded(game, _RunEnd.quit);
  }

  void _restart() {
    _detach();
    _generation++;
    unawaited(_boot());
  }

  void _detach() {
    _game
      ?..onTimeUp = null
      ..onSequenceCompleted = null
      ..onTeamLevelCompleted = null;
  }

  @override
  void dispose() {
    _detach();
    unawaited(AudioManager.instance.leaveMusicScene(MusicScene.game));
    super.dispose();
  }

  Widget _results(IndividualConditionResult result, _RunEnd end) {
    final levelCount = _game?.levelSequence.levelCount ?? 1;
    final completed = end == _RunEnd.completed;
    final best = _runKey == null ? null : _progress.bestTime(_runKey!);
    return ResultsCard(
      title: switch (end) {
        _RunEnd.timeUp => 'results.timeUp'.tr(),
        _RunEnd.completed => 'results.completed'.tr(),
        _RunEnd.quit => 'results.runEnded'.tr(),
      },
      highlight: !_newBest
          ? null
          : completed
          ? 'results.newBestTime'.tr()
          : 'results.newBest'.tr(),
      rows: [
        (
          'results.levelReached'.tr(),
          completed
              ? 'results.allLevels'.tr(args: [levelCount.toString()])
              : 'results.level'.tr(
                  args: [
                    (result.finalLevelIndex.clamp(0, levelCount - 1) + 1)
                        .toString(),
                  ],
                ),
        ),
        (
          'results.distance'.tr(),
          '${result.finalDistance.toStringAsFixed(1)} m',
        ),
        if (!widget.timed)
          ('results.time'.tr(), TimeProvider.formatSeconds(_elapsed.floor())),
        if (completed && best != null && !_newBest)
          ('results.bestTime'.tr(), TimeProvider.formatSeconds(best.floor())),
      ],
      onPlayAgain: _restart,
      onBackToMenu: () => Navigator.of(context).pop(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final result = _result;
    final end = _end;
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
          if (result == null || end == null) ...[
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: widget.timed
                    ? const QuitButton()
                    : QuitButton(
                        leaveScreen: false,
                        message: 'game.endRunMessage'.tr(),
                        onQuit: _endUntimedRun,
                      ),
              ),
            ),
            const SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: AudioToggles(),
              ),
            ),
          ] else
            _results(result, end),
        ],
      ),
    );
  }
}
