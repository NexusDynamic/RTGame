import 'dart:async';

import 'package:flame/camera.dart';
import 'package:flame/components.dart' hide Timer;
import 'package:flame/events.dart';
import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rise_together_game/src/attributes/resetable.dart';
import 'package:rise_together_game/src/components/opponent_ghost.dart';
import 'package:rise_together_game/src/components/opponent_offscreen_indicator.dart';
import 'package:rise_together_game/src/components/previous_best_line.dart';
import 'package:rise_together_game/src/game/action_provider.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/game/countdown_system.dart';
import 'package:rise_together_game/src/game/distance_tracker.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/level_sequence.dart';
import 'package:rise_together_game/src/game/overlay_port.dart';
import 'package:rise_together_game/src/game/physics_channels.dart';
import 'package:rise_together_game/src/game/player_bitflags.dart';
import 'package:rise_together_game/src/game/snapshot_interpolator.dart';
import 'package:rise_together_game/src/game/rise_together_levels.dart'
    show RiseTogetherLevel;
import 'package:rise_together_game/src/game/tournament_manager.dart';
import 'package:rise_together_game/src/game/world_controller.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/models/team_context.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/physics_state_broadcaster.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';

import 'rise_together_world.dart';

/// Notifier for player input bitflag changes
class BitflagsNotifier with ChangeNotifier {
  final Map<int, int> _leftBitflags = {}; // teamId -> leftBitflags
  final Map<int, int> _rightBitflags = {}; // teamId -> rightBitflags

  int getLeftBitflags(int teamId) => _leftBitflags[teamId] ?? 0;
  int getRightBitflags(int teamId) => _rightBitflags[teamId] ?? 0;

  void updateBitflags(int teamId, int leftBitflags, int rightBitflags) {
    final prevLeft = _leftBitflags[teamId] ?? 0;
    final prevRight = _rightBitflags[teamId] ?? 0;

    if (leftBitflags != prevLeft || rightBitflags != prevRight) {
      _leftBitflags[teamId] = leftBitflags;
      _rightBitflags[teamId] = rightBitflags;
      notifyListeners();
    }
  }

  void clear() {
    _leftBitflags.clear();
    _rightBitflags.clear();
    notifyListeners();
  }

  void notifySegmentsChanged() => notifyListeners();
}

/// How a game is played.
enum GameMode {
  /// One team, no opponent: the opponent's area is blacked out.
  individual,

  /// Two teams side by side, racing each other.
  joint,
}

/// A provider for tracking round time with countdown functionality.
/// Counts down from round duration to show time remaining.
class TimeProvider extends ChangeNotifier with Resetable {
  double _timeRemaining = 0.0;
  double _duration = 240.0; // Default 4 minutes
  double _elapsedTime = 0.0;
  bool _isComplete = false;

  double get timeRemaining => _timeRemaining;
  double get duration => _duration;
  double get elapsedTime => _elapsedTime;
  bool get isComplete => _isComplete;

  void initialize(double duration) {
    _duration = duration;
    _timeRemaining = duration;
    _elapsedTime = 0.0;
    _isComplete = false;
    _lastNotifiedSecond = -1;
    notifyListeners();
  }

  /// Whole seconds remaining at the last notification. Used to suppress
  /// redundant rebuilds — see [updateTime].
  int _lastNotifiedSecond = -1;

  void updateTime(double dt) {
    if (_isComplete) return;

    _timeRemaining -= dt;
    _elapsedTime += dt;

    if (_timeRemaining <= 0) {
      _timeRemaining = 0;
      _elapsedTime = _duration; // Cap at duration
      _isComplete = true;
    }

    // Notify only when the displayed value actually changes. This runs every
    // frame, and the only consumer is a mm:ss label.
    final currentSecond = _timeRemaining.ceil();
    if (currentSecond != _lastNotifiedSecond || _isComplete) {
      _lastNotifiedSecond = currentSecond;
      notifyListeners();
    }
  }

  @override
  void reset() {
    _timeRemaining = _duration;
    _elapsedTime = 0.0;
    _isComplete = false;
    _lastNotifiedSecond = -1;
    notifyListeners();
  }

  String get formattedTime {
    final totalSeconds = _timeRemaining.ceil();
    final minutes = (totalSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

abstract class RiseTogetherGameBase<T extends RiseTogetherWorld>
    extends Forge2DGame
    with AppLogging, AppSettings, Resetable, KeyboardEvents {
  final int nTeams = 2;

  // Managers are injected by the host screen (see [setManagers]) so results
  // outlive a single game instance; created on demand otherwise.
  TimeProvider? _timeProvider;
  TournamentManager? _tournamentManager;
  DistanceTracker? _distanceTracker;

  TimeProvider get timeProvider => _timeProvider ??= TimeProvider();

  TournamentManager get tournamentManager =>
      _tournamentManager ??= TournamentManager();

  DistanceTracker get distanceTracker => _distanceTracker ??= DistanceTracker();

  // Field-initialised rather than `late`: onRemove() has to dispose this, and
  // a game removed before onLoad finished would otherwise throw there instead
  // of cleaning up. Subclasses replace it (see InteractiveGame.onLoad).
  CountdownSystem countdownSystem = CountdownSystem();

  ActionProvider? _actionProvider;
  ActionProvider? get actionProvider => _actionProvider;
  bool get isConfigured => _actionProvider != null;

  /// The multiplayer session, or null for solo play.
  GameSession? get session => _actionProvider?.session;

  bool _gameRunning = false;
  bool get isGameRunning => _gameRunning;

  /// The player's team takes the TOP half and the opponent the bottom --
  /// `_buildCamera` gives TeamDisplayPosition.left the 0.0 offset.
  final bool verticalOrientation = true;

  /// Draw the opponent inside the player's own full-screen arena instead of
  /// giving them a viewport of their own. See `ui.single_view_opponent`.
  ///
  /// Read once in [onLoad]: the cameras are built there and never rebuilt.
  bool _singleViewOpponent = false;
  bool get singleViewOpponent => _singleViewOpponent;

  /// The opponent's ghost and its off-screen cue, non-null only when
  /// [singleViewOpponent] is on.
  OpponentGhost? opponentGhost;
  OpponentOffscreenIndicator? opponentIndicator;

  /// The dashed previous-best marks, one per team.
  PreviousBestLine? playerBestLine;
  PreviousBestLine? opponentBestLine;

  // Cached player bitflags mapping to avoid recalculation
  List<Map<String, dynamic>> get playerBitFlagsList =>
      List.unmodifiable(_playerBitflagsList);
  final List<Map<String, dynamic>> _playerBitflagsList = [];
  final Map<String, int> _cachedPlayerBitflags = {};
  int? _cachedPlayerCount;

  // Notifier for bitflag changes (for UI reactivity)
  final BitflagsNotifier _bitflagsNotifier = BitflagsNotifier();

  @override
  bool get pauseWhenBackgrounded => false;

  // --- authority / follower ------------------------------------------------

  bool _isAuthoritativePhysics = false;
  bool get isAuthoritativePhysics => _isAuthoritativePhysics;

  /// Sends physics state to followers, on the authority of an online game.
  PhysicsStateBroadcaster? _physicsBroadcaster;

  /// Minimum gap between physics broadcasts: ~60 Hz, which is plenty for
  /// followers that only render, and half the traffic of the 120 Hz LAN
  /// setting this game grew out of.
  static const int physicsBroadcastIntervalMs = 16;

  final List<StreamSubscription<Object?>> _sessionSubscriptions = [];

  /// Smooths the authority's state for display, on followers.
  final SnapshotInterpolator _interpolator = SnapshotInterpolator();

  // Reused across every apply tick — avoids 2 Vector2 allocations per frame.
  final Vector2 _physicsApplyVec = Vector2.zero();

  final List<CameraComponent> cameras = [];
  final Map<TeamDisplayPosition, WorldController> worldControllers = {};

  final ActionStreamManager actionManager;

  /// The authority's rules for an online match; null offline.
  MatchRules? _matchRules;

  /// Teams whose input the authority is ignoring, during their countdown.
  final Set<int> _inputLockedTeams = {};

  /// Whether the authority applies input for [teamId] right now.
  bool acceptsInputFor(int teamId) => !_inputLockedTeams.contains(teamId);

  /// Run [body] with [teamId]'s input ignored and held input dropped.
  ///
  /// Local players are already blocked by the countdown check in
  /// [sendAction]; remote players' clients cannot be trusted to do the same,
  /// and their held state is re-sent periodically, so the authority enforces
  /// it. Held buttons take effect again within one resend after the lock.
  Future<R> withTeamInputLocked<R>(
    int teamId,
    Future<R> Function() body,
  ) async {
    _inputLockedTeams.add(teamId);
    actionManager.getTeamStream(teamId)?.clearAllActions();
    try {
      return await body();
    } finally {
      _inputLockedTeams.remove(teamId);
    }
  }

  /// Round and trial being played, passed through to [TournamentManager].
  int _currentRound = 0;
  int _currentTrial = 0;

  /// Where overlays go.
  late final OverlayPort overlay = FlameOverlayPort(
    addOverlay: overlays.add,
    removeOverlay: overlays.remove,
    overlayIsActive: overlays.isActive,
  );

  /// Called when the round timer runs out.
  VoidCallback? onTimeUp;

  /// Online only: the round's official result, from the authority. Fires on
  /// every device, the authority included.
  void Function(RoundOver result)? onRoundOver;

  /// A follower waiting for the authority's start countdown to reach GO.
  Completer<void>? _awaitingStart;

  bool get _isOnlineFollower => session != null && !_isAuthoritativePhysics;

  RiseTogetherGameBase({required this.actionManager})
    // box2d v3 takes gravity and the pixel scale at construction. The worlds
    // override gravity with the configured value.
    : super(
        gravity: Vector2(0, GameGeometry.gravity(9.81)),
        metersToPixels: 10,
      ) {
    isPaused = true; // Start paused
  }

  /// Must always be called internally when gameplay is paused or stopped
  /// This does not apply when the app is backgrounded (but pauseEngine()
  /// is called)
  @protected
  void pauseEngineInternal() {
    super.pauseEngine();
    _gameRunning = false;
  }

  /// Must always be called internally when gameplay is started or resumed
  /// When app is foregrounded, resumeEngine() is called automatically
  void _resumeEngine() {
    super.resumeEngine();
    _gameRunning = true;
  }

  bool _tempLeftDown = false;
  bool _tempRightDown = false;
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final isKeyDown = event is KeyDownEvent;
    final isKeyUp = event is KeyUpEvent;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (isKeyDown) {
        sendAction(0, 'keyboard_player', PaddleAction.left);
        _tempLeftDown = true;
        return KeyEventResult.handled;
      } else if (isKeyUp) {
        _tempLeftDown = false;
        if (!_tempRightDown) {
          sendAction(0, 'keyboard_player', PaddleAction.none);
        }
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (isKeyDown) {
        sendAction(0, 'keyboard_player', PaddleAction.right);
        _tempRightDown = true;
        return KeyEventResult.handled;
      } else if (isKeyUp) {
        _tempRightDown = false;
        if (!_tempLeftDown) {
          sendAction(0, 'keyboard_player', PaddleAction.none);
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Configure the game with an action provider
  /// This separates asset loading from networking configuration
  Future<void> configure(ActionProvider actionProvider) async {
    if (_actionProvider != null && _actionProvider != actionProvider) {
      _actionProvider!.dispose();
    }
    _cancelSessionSubscriptions();
    _actionProvider = actionProvider;

    // Invalidate cached bitflags when changing providers
    _cachedPlayerBitflags.clear();
    _cachedPlayerCount = null;
    _bitflagsNotifier.clear();

    await actionProvider.initialize();
    if (actionProvider is SessionActionProvider) {
      actionProvider.acceptInput = acceptsInputFor;
    }

    _isAuthoritativePhysics = actionProvider.isCoordinator;
    appLog.info(
      'Physics mode: ${_isAuthoritativePhysics ? "Authoritative" : "Follower"}',
    );

    for (final controller in worldControllers.values) {
      controller.shouldUpdateParallax = _isAuthoritativePhysics;
      if (_isAuthoritativePhysics) {
        controller.world.ball.toDynamic();
        controller.world.paddle.toKinematic();
      } else {
        controller.world.ball.toStatic();
        controller.world.paddle.toStatic();
      }
    }

    // Level completion and object consumption are decided by the authority
    // only; followers learn of them through session events.
    for (final controller in worldControllers.values) {
      controller.onLevelCompleted = () {
        controller.clearActions();
        if (_isAuthoritativePhysics) _handleTeamLevelCompletion(controller);
      };
      controller.onLevelObjectConsumed = _isAuthoritativePhysics
          ? _handleLevelObjectConsumed
          : null;
    }

    final levelSequence = LevelSequence.defaultSequence();
    for (final controller in worldControllers.values) {
      controller.setLevelSequence(levelSequence);
    }
    appLog.info(
      'Level sequences initialized with ${levelSequence.levelCount} levels',
    );

    for (final controller in worldControllers.values) {
      await controller.world.loadLevel(controller.currentLevel);
    }

    final session = actionProvider.session;
    if (session != null) {
      _matchRules = session.rules;
      _sessionSubscriptions.add(
        session.assignmentsChanged.listen((_) => _updateTeamContexts()),
      );
      if (_isAuthoritativePhysics) {
        _physicsBroadcaster =
            PhysicsStateBroadcaster(
                sendSample: session.broadcastPhysics,
                isPlaying: () => isGameRunning,
                minIntervalMs: physicsBroadcastIntervalMs,
              )
              ..setProvider(_getCurrentPhysicsState)
              ..start();
      } else {
        _sessionSubscriptions
          ..add(session.physics.listen(_handleIncomingPhysicsState))
          ..add(session.events.listen(_handleGameEvent));
      }
    }

    // Team streams must exist before the first action is sent.
    _updateTeamContexts();

    appLog.info('Game configured with action provider');
  }

  void _cancelSessionSubscriptions() {
    for (final subscription in _sessionSubscriptions) {
      subscription.cancel();
    }
    _sessionSubscriptions.clear();
    _physicsBroadcaster?.reset();
    _physicsBroadcaster = null;
  }

  /// Inject managers owned by the host screen.
  void setManagers({
    required TournamentManager tournamentManager,
    required TimeProvider timeProvider,
    required DistanceTracker distanceTracker,
  }) {
    _tournamentManager = tournamentManager;
    _timeProvider = timeProvider;
    _distanceTracker = distanceTracker;

    // The injected tracker arrives with DistanceTracker's own default, not the
    // scale-compensated multiplier onLoad computed for the previous tracker.
    distanceTracker.initialize(
      GameGeometry.distanceMultiplier(
        appSettings.getDouble('game.distance_multiplier'),
      ),
    );
  }

  /// Start a round.
  ///
  /// - [mode]: individual (opponent hidden) or joint (two teams).
  /// - [durationSeconds]: round length.
  /// - [round] / [trial]: indices recorded with the round's result. A new
  ///   tournament of [trialsPerRound] rounds starts whenever [trial] is 0.
  ///   Online, [round] is also what this device reports ready for.
  /// - [seed]: obstacle layout; defaults to the match's.
  Future<void> startGameDirect({
    required GameMode mode,
    required double durationSeconds,
    int round = 0,
    int trial = 0,
    int trialsPerRound = 1,
    bool skipCountdown = true,
    int? seed,
  }) async {
    if (!isConfigured) {
      throw StateError('Game must be configured before starting');
    }

    _currentRound = round;
    _currentTrial = trial;
    // Explicit seed (online rematch) > the match's > settings/random.
    final matchSeed = seed ?? _matchRules?.seed;

    appLog.info(
      'Starting game: mode=$mode, duration=${durationSeconds}s, '
      'round=$round, trial=$trial',
    );

    timeProvider.initialize(durationSeconds);

    if (mode == GameMode.individual) {
      // Online, every device must build the same obstacles; offline a null
      // seed picks a fresh one.
      tournamentManager.startIndividualCondition(
        durationSeconds: durationSeconds,
        seed: matchSeed,
      );
      addBlackScreenToNonPlayerWorld();
    } else {
      // Idempotent: leaves individual mode if a previous game set it.
      tournamentManager.exitIndividualCondition();

      if (trial == 0) {
        // Online, every device must build the same obstacles, so the seed is
        // the authority's. Offline, 0 means "pick one".
        final seedValue =
            matchSeed ?? appSettings.getInt('game.experiment_seed');
        tournamentManager.initialize(
          rounds: trialsPerRound,
          roundDurationSeconds: durationSeconds,
          seed: seedValue > 0 ? seedValue : null,
        );
      }

      if (!tournamentManager.isTournamentComplete) {
        tournamentManager.startRound();
      }

      removeBlackScreenFromNonPlayerWorld();
      await advanceLevel();
    }

    await startGame(skipCountdown: skipCountdown);
  }

  /// Start the game, optionally after the 3-2-1 countdown.
  Future<void> startGame({bool skipCountdown = false}) async {
    if (!isConfigured) {
      throw StateError('Game must be configured before starting');
    }

    if (skipCountdown) {
      overlay.add('inGameUI');
      _resumeEngine();
      appLog.info('Game started');
      return;
    }

    if (_isOnlineFollower) {
      // The authority runs the countdown; this device mirrors it and starts
      // its clock at GO, so both round timers end together.
      final start = _awaitingStart = Completer<void>();
      await session!.markReady(round: _currentRound);
      try {
        await start.future.timeout(const Duration(seconds: 60));
      } on TimeoutException {
        appLog.warning('Never saw the host start the round');
        return;
      } finally {
        _awaitingStart = null;
      }
      overlay.remove('countdown');
      overlay.add('inGameUI');
      _resumeEngine();
      return;
    }

    overlay.add('countdown');

    // Mirror the countdown to followers as it runs.
    void broadcastListener() => broadcastEvent(
      GlobalCountdownState(stateIndex: countdownSystem.currentState.index),
    );
    final mirror = _isAuthoritativePhysics && session != null;
    if (mirror) countdownSystem.addListener(broadcastListener);

    try {
      await countdownSystem.startCountdown();
      // Run-scoped: a superseding countdown completes this wait instead of
      // leaving the game paused behind a countdown that will never finish.
      await countdownSystem.runCompletion;
    } finally {
      if (mirror) countdownSystem.removeListener(broadcastListener);
    }

    overlay.remove('countdown');
    overlay.add('inGameUI');

    _resumeEngine();
    appLog.info('Game started');
  }

  /// Stop the game.
  Future<void> stopGame() async {
    if (!isConfigured) return;
    _physicsBroadcaster?.stop();
    pauseEngineInternal();
    appLog.info('Game stopped');
  }

  /// Send the local player's action.
  void sendAction(int _, String _, PaddleAction action) {
    if (!isConfigured) {
      appLog.warning('Attempted to send action but game not configured');
      return;
    }
    // Block input during countdown
    if (countdownSystem.isActive) return;
    // Block input when game is not running
    if (!isGameRunning) return;

    final assignment = _actionProvider!.currentPlayerAssignment;
    _actionProvider!.networkBridge.sendAction(
      assignment.teamId,
      assignment.playerId,
      action,
    );
  }

  /// Publish [event] to followers. A no-op off the authority or offline.
  void broadcastEvent(GameEvent event) {
    if (!_isAuthoritativePhysics) return;
    session?.broadcastEvent(event);
  }

  /// Whether this device runs the authoritative simulation.
  bool get isCoordinator =>
      isConfigured ? _actionProvider!.isCoordinator : false;

  /// Get current player's team assignment
  PlayerAssignment? get currentPlayerAssignment {
    if (!isConfigured) return null;
    return _actionProvider!.currentPlayerAssignment;
  }

  /// Assign each player a press-indicator bit.
  void initPlayerBitflags() {
    if (!isConfigured) return;

    final assigned = PlayerBitflags.assign(_actionProvider!.playerAssignments);

    if (!PlayerBitflags.fitsInChannel(assigned.length)) {
      // The bit would not survive the float32 physics channel, so the press
      // indicators for the last players would silently be wrong.
      appLog.severe(
        '${assigned.length} players exceeds the ${PlayerBitflags.maxPlayers} '
        'that fit in a float32 bitflag channel',
      );
    }

    _playerBitflagsList
      ..clear()
      ..addAll(assigned.map((b) => b.toMap()));
    _bitflagsNotifier.notifySegmentsChanged();
  }

  /// Get bitflag value for current device/player
  int? getCurrentPlayerBitflag() {
    final currentAssignment = currentPlayerAssignment;
    if (currentAssignment == null) return null;

    for (final player in _playerBitflagsList) {
      if (player['nodeId'] == currentAssignment.nodeId) {
        return player['bitflagValue'] as int;
      }
    }
    return null;
  }

  /// Update current bitflags from local team streams (authority only)
  void _updateCurrentBitflags() {
    if (!_isAuthoritativePhysics) return;

    for (final worldController in worldControllers.values) {
      final teamId = worldController.teamContext.teamId;
      final thrust = worldController.actionStream.getCurrentThrust();
      _bitflagsNotifier.updateBitflags(
        teamId,
        thrust.leftBitflags,
        thrust.rightBitflags,
      );
    }
  }

  /// Update team contexts for all world controllers when assignments change
  void _updateTeamContexts() {
    if (!isConfigured) return;
    final myTeamId = _actionProvider!.currentPlayerAssignment.teamId;
    final opponentTeamId = myTeamId == 0 ? 1 : 0;

    final players = _actionProvider!.playerAssignments;
    final myTeamPlayers = players.where((p) => p.teamId == myTeamId).toList();
    final opponentTeamPlayers = players
        .where((p) => p.teamId == opponentTeamId)
        .toList();

    final myTeamStream =
        actionManager.getTeamStream(myTeamId) ??
        (actionManager.createTeamStream(
          TeamDisplayPosition.left,
          5,
          getPlayerBitflags: _getPlayerBitflagsMap,
        )..teamId = myTeamId);
    final opponentTeamStream =
        actionManager.getTeamStream(opponentTeamId) ??
        (actionManager.createTeamStream(
          TeamDisplayPosition.right,
          5,
          getPlayerBitflags: _getPlayerBitflagsMap,
        )..teamId = opponentTeamId);

    // The local team always renders on the left/top.
    myTeamStream.position = TeamDisplayPosition.left;
    opponentTeamStream.position = TeamDisplayPosition.right;

    worldControllers[TeamDisplayPosition.left]!.setTeamContext(
      TeamContext(
        teamId: myTeamId,
        displayPosition: TeamDisplayPosition.left,
        isPlayerTeam: true,
        players: myTeamPlayers,
        actionStream: myTeamStream,
      ),
    );
    worldControllers[TeamDisplayPosition.right]!.setTeamContext(
      TeamContext(
        teamId: opponentTeamId,
        displayPosition: TeamDisplayPosition.right,
        isPlayerTeam: false,
        players: opponentTeamPlayers,
        actionStream: opponentTeamStream,
      ),
    );

    appLog.info(
      'Updated team contexts: Left=Team$myTeamId (${myTeamPlayers.length} '
      'players), Right=Team$opponentTeamId '
      '(${opponentTeamPlayers.length} players)',
    );

    _cachedPlayerCount = null;
    initPlayerBitflags();

    // Force re-linking of overlays
    if (overlay.isActive('inGameUI')) {
      overlay.remove('inGameUI');
      overlay.add('inGameUI');
    }
  }

  /// Player id → press-indicator bit, for the action system.
  Map<String, int> _getPlayerBitflagsMap() {
    if (!isConfigured) return const {};

    final playerCount = _actionProvider!.playerAssignments.length;
    if (_cachedPlayerCount != playerCount) {
      initPlayerBitflags();
      _cachedPlayerBitflags.clear();
      for (final player in _playerBitflagsList) {
        final bitflagValue = player['bitflagValue'] as int;
        _cachedPlayerBitflags[player['playerId'] as String] = bitflagValue;
        _cachedPlayerBitflags[player['nodeId'] as String] = bitflagValue;
      }
      _cachedPlayerCount = playerCount;
    }

    return _cachedPlayerBitflags;
  }

  /// Get current left input bitflags for a team (for visual indicators)
  int getTeamLeftBitflags(int teamId) =>
      _bitflagsNotifier.getLeftBitflags(teamId);

  /// Get current right input bitflags for a team (for visual indicators)
  int getTeamRightBitflags(int teamId) =>
      _bitflagsNotifier.getRightBitflags(teamId);

  /// Drop every held input for [world]'s team (the ball hit a fatal wall).
  ///
  /// Only the authority holds the inputs that drive physics; players have to
  /// press again after a reset.
  void clearTeamActions(RiseTogetherWorld world) {
    if (!isConfigured || !_isAuthoritativePhysics) return;
    final teamId = world.controller.teamContext.teamId;
    actionManager.getTeamStream(teamId)?.clearAllActions();
  }

  /// Get notifier for bitflag changes (for UI reactivity)
  BitflagsNotifier get bitflagsNotifier => _bitflagsNotifier;

  /// Get a distinct color for a player based on their index
  Color getPlayerColor(int playerIndex) {
    const colors = [
      Colors.green,
      Colors.blue,
      Colors.red,
      Colors.orange,
      Colors.purple,
      Colors.yellow,
      Colors.teal,
      Colors.pink,
    ];
    return colors[playerIndex % colors.length];
  }

  RectangleComponent viewportRimGenerator(
    Vector2 viewportSize, {
    bool overlay = false,
  }) => RectangleComponent(size: viewportSize, anchor: Anchor.topLeft)
    ..paint.color = overlay
        ? Color.fromARGB(255, 0, 0, 0)
        : Color.fromARGB(255, 0, 200, 255)
    ..paint.strokeWidth = 2.0
    ..paint.style = overlay ? PaintingStyle.fill : PaintingStyle.stroke
    ..paint.blendMode = overlay ? BlendMode.color : BlendMode.srcOver;

  Vector2 alignedVector({
    required double longMultiplier,
    double shortMultiplier = 1.0,
  }) {
    return !verticalOrientation
        ? Vector2(canvasSize.x * longMultiplier, canvasSize.y * shortMultiplier)
        : Vector2(
            canvasSize.x * shortMultiplier,
            canvasSize.y * longMultiplier,
          );
  }

  CameraComponent _buildCamera(
    RiseTogetherWorld world,
    TeamDisplayPosition pos,
  ) {
    // Single-view: one camera, the whole canvas. The viewport width is the
    // full canvas either way; what changes is the height, and therefore how
    // much of the climb is visible.
    final viewportSize = alignedVector(
      longMultiplier: _singleViewOpponent ? 1.0 : 1 / 2,
    );
    final zoomLevel = viewportSize.x / RiseTogetherLevel.horizontalWidth;
    final cameraPos = _singleViewOpponent
        ? Vector2.zero()
        : alignedVector(
            longMultiplier: pos == TeamDisplayPosition.left ? 0.0 : 0.5,
            shortMultiplier: 0.0,
          );

    final List<RectangleComponent> cameraOverlays = [];
    RectangleComponent? cameraOverlay;

    // The blackout rectangle belongs to the opponent's own viewport in the
    // split view. The single view has no such viewport; individual mode hides
    // the ghost instead (see InteractiveGame).
    if (!_singleViewOpponent && pos == TeamDisplayPosition.right) {
      cameraOverlay = viewportRimGenerator(viewportSize, overlay: true);
      cameraOverlays.add(cameraOverlay);
    }

    final worldCamera =
        CameraComponent(
            world: world,
            viewport: FixedSizeViewport(viewportSize.x, viewportSize.y)
              ..position = cameraPos
              ..addAll(cameraOverlays),
          )
          ..viewfinder.anchor = Anchor.center
          ..viewfinder.zoom = zoomLevel;
    world.setWorldCamera(worldCamera, cameraOverlay: cameraOverlay);
    return worldCamera;
  }

  Future<void> _buildComponents(WorldController worldController) async {
    final widthMultiplier = appSettings.getDouble(
      'physics.paddle_width_multiplier',
    );
    await worldController.world.buildPaddle(widthMultiplier: widthMultiplier);
    final ball = await worldController.world.buildBall();
    distanceTracker.setStartingHeight(
      worldController.teamContext.teamId,
      ball.body.position.y,
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    await initSettings();

    // Must be read before _setupWorld runs: it decides how many cameras exist.
    _singleViewOpponent = appSettings.getBool('ui.single_view_opponent');

    final roundDuration = appSettings.getDouble('game.round_duration');
    timeProvider.initialize(roundDuration);

    final seedCfg = appSettings.getInt('game.experiment_seed');
    tournamentManager.initialize(
      rounds: appSettings.getInt('game.tournament_rounds'),
      roundDurationSeconds: roundDuration,
      seed: seedCfg > 0 ? seedCfg : null,
    );

    // Inversely proportional to the world scale, so reported metres are
    // unchanged when the scale changes.
    distanceTracker.initialize(
      GameGeometry.distanceMultiplier(
        appSettings.getDouble('game.distance_multiplier'),
      ),
    );

    final gravity = GameGeometry.gravity(
      appSettings.getDouble('physics.gravity'),
    );

    camera.removeFromParent();
    world.removeFromParent();
    children.register<CameraComponent>();
    children.register<RiseTogetherWorld>();

    await Flame.images.loadAll([
      'assets/images/ball.png',
      // Loaded here, not in RiseTogetherWorld.onLoad: configure() calls
      // loadLevel() as soon as the game reports isLoaded, before the worlds
      // have run their own onLoad.
      'assets/images/ground_floor.png',
      'assets/images/obstacle_fatal.png',
      'assets/images/powerup_paddle_width.png',
      'assets/images/trigger_control_reversal.png',
    ]);

    await _setupWorld(TeamDisplayPosition.left, gravity);
    await _setupWorld(TeamDisplayPosition.right, gravity);

    appLog.fine('Game assets loaded, ready for configuration');
  }

  Future<void> _setupWorld(TeamDisplayPosition pos, double gravity) async {
    final worldController = await _buildWorldController(
      pos,
      Vector2(0, gravity),
    );
    worldControllers[pos] = worldController;

    // Single-view: the opponent's world is still built, stepped and positioned
    // every frame -- the ghost reads from it -- it just gets no camera, so
    // nothing under it renders.
    final skipCamera = _singleViewOpponent && pos == TeamDisplayPosition.right;

    CameraComponent? worldCamera;
    if (!skipCamera) {
      worldCamera = _buildCamera(worldController.world, pos);
      add(worldCamera);
      cameras.add(worldCamera);
    }
    add(worldController.world);
    // The components rely on the world and camera (for following the paddle).
    await _buildComponents(worldController);
    await worldController.world.loadLevel(worldController.currentLevel);

    // The ghost goes in the player's world so the player's camera draws it;
    // the cue goes in that camera's viewport so it stays pinned to the edge.
    if (_singleViewOpponent &&
        pos == TeamDisplayPosition.left &&
        worldCamera != null) {
      final ghost = OpponentGhost();
      opponentGhost = ghost;
      worldController.world.add(ghost);

      final indicator = OpponentOffscreenIndicator(camera: worldCamera);
      opponentIndicator = indicator;
      worldCamera.viewport.add(indicator);
    }

    // Previous-best marks, each in the world whose camera draws its team.
    if (worldCamera != null) {
      if (pos == TeamDisplayPosition.left) {
        final own = PreviousBestLine(
          source: TeamDisplayPosition.left,
          label: 'Your previous best',
          camera: worldCamera,
        );
        playerBestLine = own;
        worldController.world.add(own);

        if (_singleViewOpponent) {
          final theirs = PreviousBestLine(
            source: TeamDisplayPosition.right,
            label: "Opponent's previous best",
            camera: worldCamera,
            captionOnRight: true,
            crossLevelAware: true,
          );
          opponentBestLine = theirs;
          worldController.world.add(theirs);
        }
      } else if (!_singleViewOpponent) {
        final theirs = PreviousBestLine(
          source: TeamDisplayPosition.right,
          label: "Opponent's previous best",
          camera: worldCamera,
          captionOnRight: true,
        );
        opponentBestLine = theirs;
        worldController.world.add(theirs);
      }
    }
  }

  Future<WorldController> _buildWorldController(
    TeamDisplayPosition pos,
    Vector2 gravity,
  ) async {
    final world = RiseTogetherWorld(pos: pos, game: this, gravity: gravity);

    final teamStream = actionManager.createTeamStream(
      pos,
      5, // max 5 players per team
      getPlayerBitflags: _getPlayerBitflagsMap,
    );

    teamStream.teamId = pos == TeamDisplayPosition.left ? 0 : 1;

    final teamContext = TeamContext.byPosition(pos, actionStream: teamStream);
    return WorldController(
      world: world,
      shouldUpdateParallax: _isAuthoritativePhysics,
      configuredTeamPlayerCount: 1, // will be updated later
      teamContext: teamContext,
    );
  }

  /// Longest step handed to the physics engine, in seconds.
  ///
  /// A backgrounded or occluded window stops the render ticker without pausing
  /// the game ([pauseWhenBackgrounded] is false), so the first frame after it
  /// resumes carries the whole elapsed wall time as a single dt. Integrated as
  /// one step, the ball tunnels through the floor and falls forever. 1/30s is
  /// a frame the game must already survive, so bounding to it cannot change a
  /// healthy frame.
  static const double maxPhysicsStep = 1 / 30;

  /// [dt] bounded to [maxPhysicsStep].
  static double boundPhysicsStep(double dt) =>
      dt > maxPhysicsStep ? maxPhysicsStep : dt;

  @override
  void update(double dt) {
    if (!isLoaded) return;

    // Physics gets a bounded step; the round clock below still gets the real
    // dt, so a stalled device's round ends on wall time rather than drifting.
    super.update(boundPhysicsStep(dt));
    if (!_isAuthoritativePhysics) {
      for (final worldController in worldControllers.values) {
        worldController.stopMovement();
      }
      _applyPhysicsState();
    } else {
      _updateCurrentBitflags();
      // The step's own dt rate-limits the broadcast, not wall time.
      _physicsBroadcaster?.broadcastOnChange(dt);
    }

    timeProvider.updateTime(dt);
    tournamentManager.updateRoundTime(timeProvider.elapsedTime);
    _updateDistanceTracking();

    if (timeProvider.isComplete && isGameRunning) {
      _handleRoundComplete();
    }
  }

  void roundComplete();

  void _handleRoundComplete() {
    appLog.info('Round completed - time is up!');
    _physicsBroadcaster?.stop();

    if (_isOnlineFollower) {
      // This device did not simulate the round; the authority's RoundOver
      // carries the result.
      pauseEngineInternal();
      overlay.remove('inGameUI');
      return;
    }

    if (tournamentManager.isIndividualConditionMode) {
      completeIndividualCondition();
      _announceRoundOver();
      onTimeUp?.call();
      return;
    }

    tournamentManager.completeRound(
      roundIndex: _currentRound,
      trialIndex: _currentTrial,
      authoritative: _isAuthoritativePhysics,
    );

    roundComplete();
    _announceRoundOver();
    onTimeUp?.call();
  }

  /// Online authority: publish the result and report it locally.
  void _announceRoundOver() {
    if (session == null) return;
    final RoundOver result;
    final individual = tournamentManager.individualConditionResult;
    if (tournamentManager.isIndividualConditionMode && individual != null) {
      result = RoundOver(
        levels: [individual.finalLevelIndex, 0],
        distances: [individual.finalDistance, 0],
      );
    } else if (tournamentManager.roundResults.isNotEmpty) {
      final teams = tournamentManager.roundResults.last.teamResults;
      result = RoundOver(
        levels: [
          for (final id in const [0, 1]) teams[id]?.finalLevelIndex ?? 0,
        ],
        distances: [
          for (final id in const [0, 1]) teams[id]?.finalDistance ?? 0,
        ],
      );
    } else {
      return;
    }
    broadcastEvent(result);
    onRoundOver?.call(result);
  }

  /// Record the solo result and stop.
  void completeIndividualCondition() {
    if (!tournamentManager.isIndividualConditionMode) return;

    final playerTeam = currentPlayerAssignment?.teamId ?? 0;
    tournamentManager.completeIndividualCondition(
      playerId: currentPlayerAssignment?.playerId ?? 'unknown',
      finalLevelIndex: tournamentManager.getTeamLevelIndex(playerTeam),
      finalDistance: distanceTracker.getTeamDistance(playerTeam),
    );

    pauseEngineInternal();
    removeBlackScreenFromNonPlayerWorld();
    overlay.remove('inGameUI');
  }

  /// Hide the opponent's area (individual mode). Overridden by
  /// [InteractiveGame], which owns the visuals.
  void addBlackScreenToNonPlayerWorld() {}

  /// Reveal the opponent's area again.
  void removeBlackScreenFromNonPlayerWorld() {}

  // --- follower: session events ---------------------------------------------

  void _handleGameEvent(GameEvent event) {
    switch (event) {
      case TeamLevelProgression(:final teamId, :final levelIndex, :final seed):
        _handleTeamLevelProgressionUpdate(teamId, levelIndex, seed: seed);
      case LevelObjectConsumed(:final teamId, :final spawnId):
        _handleLevelObjectConsumedUpdate(teamId, spawnId);
      case TeamCountdownState(
        :final teamId,
        :final stateIndex,
        :final levelIndex,
      ):
        _handleTeamCountdownState(teamId, stateIndex, levelIndex);
      case TeamCountdownTrigger(:final teamId, :final levelIndex):
        _handleTeamCountdownTrigger(teamId, levelIndex);
      case GlobalCountdownState(:final stateIndex):
        _applyCountdownFromNetwork(stateIndex, null);
        if (stateIndex == CountdownState.finished.index) {
          final start = _awaitingStart;
          if (start != null && !start.isCompleted) start.complete();
        }
      case RoundOver():
        onRoundOver?.call(event);
      case Rematch():
        // The host screen starts the next round with a fresh game; this one
        // is finished.
        break;
    }
  }

  /// A team countdown step from the authority; only this player's team shows it.
  void _handleTeamCountdownState(int teamId, int stateIndex, int? levelIndex) {
    final myTeamId = currentPlayerAssignment?.teamId;
    if (myTeamId != null && myTeamId != teamId) return;
    _applyCountdownFromNetwork(stateIndex, _levelMessage(levelIndex));
  }

  /// The announcement for [levelIndex], rendered locally: no text displayed
  /// here ever comes off the network.
  String? _levelMessage(int? levelIndex) =>
      levelIndex == null ? null : levelTransitionMessage(levelIndex);

  /// Apply an authority-driven countdown state to the local CountdownSystem
  /// and manage the countdown overlay.
  void _applyCountdownFromNetwork(int stateIndex, String? message) {
    if (stateIndex < 0 || stateIndex >= CountdownState.values.length) return;
    final state = CountdownState.values[stateIndex];
    if (state != CountdownState.finished) {
      if (!overlay.isActive('countdown')) overlay.add('countdown');
    } else {
      overlay.remove('countdown');
    }
    countdownSystem.setStateFromNetwork(state, message: message);
  }

  WorldController? _controllerForTeam(int teamId) {
    for (final controller in worldControllers.values) {
      if (controller.teamContext.teamId == teamId) return controller;
    }
    return null;
  }

  /// A team advanced a level on the authority; mirror it.
  void _handleTeamLevelProgressionUpdate(
    int teamId,
    int levelIndex, {
    int seed = 0,
  }) {
    if (_isAuthoritativePhysics) return;

    // The authority's seed is the one it actually generated, not just the
    // settings value, so obstacles spawn identically here.
    tournamentManager.applySeed(seed);

    final controller = _controllerForTeam(teamId);
    if (controller == null) {
      appLog.warning('No world for team $teamId; level progression dropped');
      return;
    }

    controller.setLevelIndex(levelIndex);
    final newLevel = controller.currentLevel;
    Future.microtask(() async {
      await controller.world.loadLevel(newLevel);
      // Lock in completed distance then set new baseline for the next level
      distanceTracker.saveCompletedDistance(teamId);
      distanceTracker.setStartingHeight(
        teamId,
        controller.world.ball.position.y,
      );
    });
  }

  /// A level object was used up on the authority; remove it here too.
  void _handleLevelObjectConsumedUpdate(int teamId, int spawnId) {
    if (_isAuthoritativePhysics) return;
    final controller = _controllerForTeam(teamId);
    if (controller == null) return;
    if (!controller.world.removeLevelObjectBySpawnId(spawnId)) {
      appLog.warning('No object $spawnId on team $teamId to remove');
    }
  }

  // --- authority: level progression ------------------------------------------

  /// Handle when a team completes a level (ball reaches top wall)
  void _handleTeamLevelCompletion(WorldController controller) {
    final teamId = controller.teamContext.teamId;
    final currentLevelIndex = controller.currentLevelIndex;

    tournamentManager.teamCompletedLevel(
      teamId: teamId,
      completedLevelIndex: currentLevelIndex,
      distanceAchieved: distanceTracker.getTeamDistance(teamId),
    );

    final nextLevelIndex = controller.advanceLevel();
    if (nextLevelIndex == currentLevelIndex) {
      // Already at the last level.
      return;
    }

    final nextLevel = controller.currentLevel;
    final isPlayerTeam = currentPlayerAssignment?.teamId == teamId;

    // Scheduled for after the contact callback: the world must not change
    // during the physics step.
    Future.microtask(() async {
      await controller.world.loadLevel(nextLevel);

      distanceTracker.saveCompletedDistance(teamId);
      distanceTracker.setStartingHeight(
        teamId,
        controller.world.ball.position.y,
      );

      broadcastEvent(
        TeamLevelProgression(
          teamId: teamId,
          levelIndex: nextLevelIndex,
          seed: tournamentManager.currentTournamentSeed ?? 0,
        ),
      );

      // The engine keeps running -- the other team must continue playing.
      // Input is blocked while countdownSystem.isActive.
      final levelMessage = levelTransitionMessage(nextLevelIndex);

      await withTeamInputLocked(teamId, () async {
        if (isPlayerTeam) {
          overlay.add('countdown');

          void broadcastListener() => broadcastEvent(
            TeamCountdownState(
              teamId: teamId,
              stateIndex: countdownSystem.currentState.index,
              levelIndex: nextLevelIndex,
            ),
          );
          countdownSystem.addListener(broadcastListener);

          try {
            await countdownSystem.startCountdown(
              message: levelMessage,
              messageDuration: 2.0,
            );
            await countdownSystem.runCompletion;
          } finally {
            countdownSystem.removeListener(broadcastListener);
            overlay.remove('countdown');
          }
        } else {
          // The other team: trigger their countdown without touching ours, so
          // two teams finishing at once cannot conflict.
          await broadcastTeamCountdownDirect(teamId, nextLevelIndex);
        }
      });
    });
  }

  /// Send a single countdown trigger for [teamId] and wait the equivalent
  /// duration, so the ball resumes only after that team's local countdown
  /// finishes.
  ///
  /// [levelIndex], when set, makes the countdown announce that level first.
  Future<void> broadcastTeamCountdownDirect(int teamId, int? levelIndex) async {
    broadcastEvent(
      TeamCountdownTrigger(teamId: teamId, levelIndex: levelIndex),
    );
    if (levelIndex != null) {
      await Future.delayed(const Duration(seconds: 2)); // message phase
    }
    await Future.delayed(const Duration(seconds: 4)); // 3-2-1-GO + brief GO
  }

  /// A one-shot countdown trigger from the authority: run it locally.
  void _handleTeamCountdownTrigger(int teamId, int? levelIndex) {
    final myTeamId = currentPlayerAssignment?.teamId;
    if (myTeamId != null && myTeamId != teamId) return;
    final message = _levelMessage(levelIndex);
    countdownSystem.startCountdown(
      message: message,
      messageDuration: message != null ? 2.0 : 0.0,
      onSuccessfulStart: () async {
        if (!overlay.isActive('countdown')) overlay.add('countdown');
      },
      onAnyComplete: () async {
        if (overlay.isActive('countdown')) overlay.remove('countdown');
      },
    );
  }

  /// A level object was consumed on the authority: tell the followers.
  void _handleLevelObjectConsumed(int teamId, int spawnId) {
    broadcastEvent(LevelObjectConsumed(teamId: teamId, spawnId: spawnId));
  }

  // --- reset / settings -------------------------------------------------------

  @override
  Future<void> reset() async {
    await _clearStateBuffer();
    await _reloadSettings();

    for (final controller in worldControllers.values) {
      (controller as Resetable).reset();
    }
    timeProvider.reset();
    tournamentManager.reset();
    distanceTracker.reset();
    pauseEngineInternal();
  }

  Future<void> _clearStateBuffer() async => _interpolator.clear();

  Future<void> resumeGame() async {
    if (!isConfigured) return;
    _physicsBroadcaster?.start();
    _resumeEngine();
  }

  /// Reload settings from storage and update components
  Future<void> _reloadSettings({bool reset = true}) async {
    // Only reinitialize timer and tournament on a full reset. advanceLevel()
    // passes reset=false so it keeps the duration startGameDirect() set.
    if (reset) {
      final roundDuration = appSettings.getDouble('game.round_duration');
      timeProvider.initialize(roundDuration);
      tournamentManager.initialize(
        rounds: appSettings.getInt('game.tournament_rounds'),
        roundDurationSeconds: roundDuration,
      );
    }

    distanceTracker.initialize(
      GameGeometry.distanceMultiplier(
        appSettings.getDouble('game.distance_multiplier'),
      ),
    );

    final widthMultiplier = appSettings.getDouble(
      'physics.paddle_width_multiplier',
    );
    for (final controller in worldControllers.values) {
      controller.updatePaddleWidth(widthMultiplier);
    }
  }

  /// Public method to reload settings without full reset
  Future<void> reloadSettings() => _reloadSettings();

  /// Reset the worlds for the next round, keeping tournament progress.
  Future<void> advanceLevel() async {
    // Drop stale snapshots so a follower doesn't apply the previous round's
    // positions when the new one starts.
    await _clearStateBuffer();
    await _reloadSettings(reset: false);

    for (final controller in worldControllers.values) {
      (controller as Resetable).reset();
    }
    timeProvider.reset();
    distanceTracker.resetDistances();
    pauseEngineInternal();
  }

  /// Update distance tracking for all teams
  void _updateDistanceTracking() {
    for (final worldController in worldControllers.values) {
      final teamId = worldController.teamContext.teamId;
      distanceTracker.updateBallPosition(
        teamId,
        worldController.world.ball.position.y,
      );
      tournamentManager.updateTeamDistance(
        teamId,
        distanceTracker.getTeamDistance(teamId),
      );
    }
  }

  // --- authority: physics broadcast ---------------------------------------------

  final List<List<double>> _aStateBuffer = List.generate(
    2,
    (_) => List.filled(PhysicsChannels.perTeam, 0.0, growable: false),
    growable: false,
  );

  // Pre-allocated output buffer — avoids an allocation per broadcast.
  final List<double> _physicsSnapshotOut = List.filled(
    PhysicsChannels.perMatch,
    0.0,
  );

  final List<List<double>> _lastStateBuffer = List.generate(
    2,
    (_) => List.filled(PhysicsChannels.perTeam, 0.0, growable: false),
    growable: false,
  );

  /// Current physics state, or null when nothing changed since the last call.
  List<double>? _getCurrentPhysicsState() {
    if (!_isAuthoritativePhysics || !isGameRunning) return null;

    for (final worldController in worldControllers.values) {
      final teamId = worldController.teamContext.teamId;
      final world = worldController.world;

      _lastStateBuffer[teamId].setAll(0, _aStateBuffer[teamId]);

      final slot = _aStateBuffer[teamId];
      slot[PhysicsChannels.ballX] = world.ball.position.x;
      slot[PhysicsChannels.ballY] = world.ball.position.y;
      slot[PhysicsChannels.ballRotation] = world.ball.body.angle;
      slot[PhysicsChannels.paddleY] = world.paddle.position.y;
      slot[PhysicsChannels.paddleAngle] = world.paddle.body.angle;
      slot[PhysicsChannels.paddleWidthMultiplier] =
          world.paddle.widthMultiplier;

      // Player input bitflags, widened to double for a float32 stream.
      final thrust = worldController.actionStream.getCurrentThrust();
      slot[PhysicsChannels.leftBitflags] = thrust.leftBitflags.toDouble();
      slot[PhysicsChannels.rightBitflags] = thrust.rightBitflags.toDouble();
    }

    if (PhysicsChannels.sliceUnchanged(_aStateBuffer[0], _lastStateBuffer[0]) &&
        PhysicsChannels.sliceUnchanged(_aStateBuffer[1], _lastStateBuffer[1])) {
      return null;
    }

    // Team 0 first, team 1 second.
    _physicsSnapshotOut.setRange(0, PhysicsChannels.perTeam, _aStateBuffer[0]);
    _physicsSnapshotOut.setRange(
      PhysicsChannels.perTeam,
      PhysicsChannels.perMatch,
      _aStateBuffer[1],
    );
    return _physicsSnapshotOut;
  }

  /// The "get ready for level N" text shown on level progression.
  /// [InteractiveGame] overrides this with the localized form.
  @protected
  String levelTransitionMessage(int levelIndex) => 'Level ${levelIndex + 1}';

  // --- follower: physics apply ------------------------------------------------

  static double _nowSeconds() => DateTime.now().microsecondsSinceEpoch / 1e6;

  void _handleIncomingPhysicsState(List<double> stateData) {
    // Untrusted: a malformed sample is dropped, never applied.
    if (!validPhysicsSample(
      stateData,
      expectedLength: PhysicsChannels.perMatch,
    )) {
      appLog.warning('Dropped invalid physics sample');
      return;
    }
    _interpolator.add(stateData, _nowSeconds());
  }

  /// Write the authority's (smoothed) state into the local worlds.
  void _applyPhysicsState() {
    final state = _interpolator.sample(_nowSeconds());
    if (state == null) return;

    for (final worldController in worldControllers.values) {
      final world = worldController.world;
      final teamId = worldController.teamContext.teamId;
      final offset = PhysicsChannels.offsetForTeam(teamId);

      if (offset + PhysicsChannels.perTeam > state.length ||
          !world.ball.isMounted ||
          !world.paddle.isMounted) {
        continue;
      }

      double channel(int index) => state[offset + index];

      _physicsApplyVec.setValues(
        channel(PhysicsChannels.ballX),
        channel(PhysicsChannels.ballY),
      );
      world.ball.setPosition(_physicsApplyVec);
      world.ball.body.setTransform(
        world.ball.body.position,
        Rot.fromAngle(channel(PhysicsChannels.ballRotation)),
      );

      _physicsApplyVec.setValues(
        world.paddle.position.x,
        channel(PhysicsChannels.paddleY),
      );
      world.paddle.setPosition(_physicsApplyVec);
      world.paddle.setAngle(channel(PhysicsChannels.paddleAngle));

      // Synchronizes obstacle effects on the paddle width.
      world.paddle.syncWidthMultiplier(
        channel(PhysicsChannels.paddleWidthMultiplier),
      );

      final leftBitflags = channel(PhysicsChannels.leftBitflags).toInt();
      final rightBitflags = channel(PhysicsChannels.rightBitflags).toInt();
      _bitflagsNotifier.updateBitflags(teamId, leftBitflags, rightBitflags);

      // Parallax from the same thrust formula as the authoritative path.
      final teamPlayerCount = worldController.configuredTeamPlayerCount > 0
          ? worldController.configuredTeamPlayerCount
          : 1;
      final totalThrust =
          (_countSetBits(leftBitflags) + _countSetBits(rightBitflags)) /
          teamPlayerCount;
      world.parallax?.parallax?.baseVelocity.setFrom(
        parallaxVelocityForThrust(
          totalThrust,
          appSettings.getDouble('physics.thrust_multiplier'),
        ),
      );
    }
  }

  /// Count the set bits in [value] (players pressing, from bitflags).
  int _countSetBits(int value) {
    int count = 0;
    while (value != 0) {
      count += value & 1;
      value >>= 1;
    }
    return count;
  }

  @override
  void onRemove() {
    _cancelSessionSubscriptions();
    onRoundOver = null;

    // The countdown owns a Timer.periodic that nothing else cancels; left
    // running it outlives the game and ticks through a torn-down world.
    countdownSystem.dispose();

    for (final controller in worldControllers.values) {
      controller.dispose();
    }
    // Cleared, not just disposed: a disposed controller left here would still
    // be painted, making a dead game look alive.
    worldControllers.clear();

    if (isConfigured) {
      _actionProvider!.dispose();
      _actionProvider = null;
    }

    super.onRemove();
  }
}
