import 'dart:async';
import 'dart:math';

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
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/host_away.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/services/audio_manager.dart';
import 'package:rise_together_game/src/ui/audio_toggles.dart';
import 'package:rise_together_game/src/ui/countdown_overlay.dart';
import 'package:rise_together_game/src/ui/in_game_ui.dart';
import 'package:rise_together_game/src/ui/quit_button.dart';
import 'package:rise_together_game/src/ui/results_card.dart';

/// Plays rounds of an online match on an already started [session], for as
/// long as the host keeps choosing to play again.
///
/// Owns the session from here on: leaving this screen leaves the match.
class OnlineGameScreen extends StatefulWidget {
  const OnlineGameScreen({super.key, required this.session});

  final GameSession session;

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> with AppLogging {
  InteractiveGame? _game;
  int _round = 0;
  RoundOver? _result;

  /// Rounds won per team this session, indexed by team id.
  final List<int> _wins = [0, 0];

  StreamSubscription<SessionEnd>? _ended;
  StreamSubscription<GameEvent>? _events;
  bool _leaving = false;

  /// Followers: how long we still wait for a host that paused the match.
  /// One allowance for the whole match, so it outlives each round's game.
  late final HostAwayTracker _hostAway = HostAwayTracker(
    onExhausted: () => _onEnded(SessionEnd.hostAway),
  );

  GameSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    unawaited(AudioManager.instance.enterMusicScene(MusicScene.game));
    _ended = _session.ended.listen(_onEnded);
    if (!_session.isAuthority) {
      // Only the host decides when to play again.
      _events = _session.events.listen((event) {
        if (event is Rematch && event.round == _round + 1) {
          _startRound(event.round, seed: event.seed);
        }
      });
    }
    _startRound(0);
  }

  /// Build a fresh game for [round] and play it.
  void _startRound(int round, {int? seed}) {
    _game?.onRoundOver = null;
    _game?.matchPaused.removeListener(_onMatchPaused);
    final game = InteractiveGame(actionManager: ActionStreamManager())
      ..matchPaused.addListener(_onMatchPaused);
    _hostAway.hostAway(false);
    setState(() {
      _round = round;
      _result = null;
      _game = game;
    });
    unawaited(_play(game, round, seed));
  }

  Future<void> _play(InteractiveGame game, int round, int? seed) async {
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
    game.onRoundOver = (result) {
      if (!mounted || _game != game) return;
      setState(() {
        _result = result;
        if (_session.rules.mode == MatchMode.versus && result.winner >= 0) {
          _wins[result.winner]++;
        }
      });
    };
    await game.configure(SessionActionProvider(_session, game.actionManager));
    if (!mounted || _game != game) return;

    if (_session.isAuthority) {
      // Followers report in once their game for this round is listening;
      // starting before then would run the countdown past them.
      final allReady = await _session.waitForPlayersReady(
        const Duration(seconds: 30),
        round: round,
      );
      if (!allReady) appLog.warning('Round $round: not every player ready');
      if (!mounted || _game != game) return;
    }
    final rules = _session.rules;
    await game.startGameDirect(
      mode: rules.mode == MatchMode.coop ? GameMode.individual : GameMode.joint,
      durationSeconds: rules.roundDurationSeconds,
      round: round,
      seed: seed,
      skipCountdown: false,
    );
  }

  /// Host only: start the next round for everyone.
  void _playAgain() {
    final next = _round + 1;
    if (next > maxRound) return;
    final seed = Random.secure().nextInt(MatchRules.maxSeed);
    _session.broadcastEvent(Rematch(round: next, seed: seed));
    _startRound(next, seed: seed);
  }

  void _onMatchPaused() {
    if (_session.isAuthority) return;
    _hostAway.hostAway(_game?.matchPaused.value ?? false);
  }

  void _onEnded(SessionEnd reason) {
    if (!mounted || _leaving) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('online.ended.${reason.name}'.tr())));
    // A finished round is still worth reading; only interrupt a live one.
    if (_result == null) unawaited(_leave());
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _session.leave();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(_ended?.cancel());
    unawaited(_events?.cancel());
    _game?.onRoundOver = null;
    _game?.matchPaused.removeListener(_onMatchPaused);
    _hostAway.dispose();
    // Covers the system back gesture as well as the buttons.
    if (!_leaving) unawaited(_session.leave());
    unawaited(AudioManager.instance.leaveMusicScene(MusicScene.game));
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
          if (game != null)
            flame.GameWidget(
              // A new key per round, so Flame tears the old game down.
              key: ValueKey('online_round_$_round'),
              game: game,
              overlayBuilderMap: {
                InGameUI.overlayID: (context, g) =>
                    InGameUI(g as InteractiveGame),
                CountdownOverlay.overlayID: (context, g) =>
                    CountdownOverlay(g as InteractiveGame),
              },
            ),
          if (result == null) ...[
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: QuitButton(
                  onQuit: () async {
                    _leaving = true;
                    await _session.leave();
                  },
                ),
              ),
            ),
            const SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: AudioToggles(),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _hostAway.remaining,
              builder: (context, left, _) => left == null
                  ? const SizedBox.shrink()
                  : _HostAwayBanner(left),
            ),
          ] else
            _buildResults(result),
        ],
      ),
    );
  }

  Widget _buildResults(RoundOver result) {
    final host = _session.isAuthority;
    // Only the host can start the next round; everyone else is told so.
    final playAgain = host ? _playAgain : null;
    final waiting = host ? null : 'results.waitingForHost'.tr();

    if (_session.rules.mode == MatchMode.coop) {
      return ResultsCard(
        title: 'results.timeUp'.tr(),
        highlight: waiting,
        rows: [
          (
            'results.levelReached'.tr(),
            'results.level'.tr(args: [(result.levels[0] + 1).toString()]),
          ),
          (
            'results.distance'.tr(),
            '${result.distances[0].toStringAsFixed(1)} m',
          ),
        ],
        onPlayAgain: playAgain,
        onBackToMenu: _leave,
      );
    }

    String line(int team) =>
        '${'results.level'.tr(args: [(result.levels[team] + 1).toString()])}'
        ' · ${result.distances[team].toStringAsFixed(1)} m';

    final myTeam = _session.localAssignment.teamId;
    final otherTeam = 1 - myTeam;
    final winner = result.winner;
    return ResultsCard(
      title: winner == -1
          ? 'results.tie'.tr()
          : winner == myTeam
          ? 'results.youWin'.tr()
          : 'results.youLose'.tr(),
      highlight: waiting,
      rows: [
        ('results.yourTeam'.tr(), line(myTeam)),
        ('results.otherTeam'.tr(), line(otherTeam)),
        if (_round > 0)
          ('results.series'.tr(), '${_wins[myTeam]} – ${_wins[otherTeam]}'),
      ],
      onPlayAgain: playAgain,
      onBackToMenu: _leave,
    );
  }
}

/// Shown to followers while the host's app is in the background.
class _HostAwayBanner extends StatelessWidget {
  const _HostAwayBanner(this.left);

  final Duration left;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'online.hostAway.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'online.hostAway.waiting'.tr(
                args: [left.inSeconds.clamp(0, 999).toString()],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
