import 'package:easy_localization/easy_localization.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/game/countdown_system.dart';
import 'package:rise_together_game/src/services/audio_manager.dart';
import 'package:rise_together_game/src/models/team_context.dart';

/// Interactive version of RiseTogetherGameBase with audio and full UI support
///
/// This class extends RiseTogetherGameBase to add audio functionality for
/// the desktop/GUI version of the game. By separating audio into this subclass,
/// the base class stays free of audio dependencies
/// (flame_audio and platform audio interfaces), which keeps it testable.
class InteractiveGame extends RiseTogetherGameBase {
  InteractiveGame({required super.actionManager});

  @override
  Future<void> onLoad() async {
    // Load base game assets and systems
    await super.onLoad();

    // Initialize audio manager (interactive mode only)
    await AudioManager.instance.initialize();
    appLog.info('Audio initialized for interactive mode');

    // Replace countdown system with one that has audio callbacks. The base
    // class's instance is disposed rather than dropped: it is a ChangeNotifier,
    // and onRemove() will only ever reach whichever one is installed here.
    countdownSystem.dispose();
    countdownSystem = CountdownSystem(
      onPlayLo: AudioManager.instance.playLo,
      onPlayHi: AudioManager.instance.playHi,
    );
    appLog.info('CountdownSystem configured with audio callbacks');
  }

  /// Localized form of the base class's plain-string default.
  @override
  String levelTransitionMessage(int levelIndex) =>
      'levelTransition.getReady'.tr(args: [(levelIndex + 1).toString()]);

  /// The host screen shows the results (see `onTimeUp`); the game just stops.
  @override
  void roundComplete() {
    overlays.remove('inGameUI');
    pauseEngineInternal();
  }

  @override
  Future<void> reset() async {
    await super.reset();
    appLog.info('InteractiveGame reset complete');
  }

  /// Hide the opponent for the individual condition.
  ///
  /// Two mechanisms, chosen by [singleViewOpponent]. The split view blacks out
  /// the opponent's own viewport; the single view has no such viewport, so it
  /// suppresses the ghost, its off-screen cue and its previous-best mark
  /// instead.
  @override
  void addBlackScreenToNonPlayerWorld() {
    super.addBlackScreenToNonPlayerWorld();
    if (!isConfigured) {
      appLog.warning('Cannot add black screen: game not configured');
      return;
    }

    if (singleViewOpponent) {
      _setOpponentSuppressed(true);
      return;
    }

    final opponentWorld = worldControllers[TeamDisplayPosition.right]?.world;
    if (opponentWorld == null) {
      appLog.warning('Cannot add black screen: opponent world not found');
      return;
    }
    opponentWorld.blackout();
  }

  @override
  void removeBlackScreenFromNonPlayerWorld() {
    if (!isConfigured) {
      appLog.warning('Cannot add black screen: game not configured');
      return;
    }

    if (singleViewOpponent) {
      _setOpponentSuppressed(false);
      return;
    }

    final opponentWorld = worldControllers[TeamDisplayPosition.right]?.world;
    if (opponentWorld == null) {
      appLog.warning('Cannot add black screen: opponent world not found');
      return;
    }
    opponentWorld.reveal();
  }

  void _setOpponentSuppressed(bool suppressed) {
    opponentGhost?.suppressed = suppressed;
    opponentIndicator?.suppressed = suppressed;
    // Only the single view needs this one told: in the split view the
    // opponent's mark lives inside the viewport being blacked out.
    opponentBestLine?.suppressed = suppressed;
    appLog.info('Single-view opponent suppressed: $suppressed');
  }

  @override
  String toString() =>
      'InteractiveGame(isGameRunning: $isGameRunning, '
      'isCoordinator: $isCoordinator, isConfigured: $isConfigured)';
}
