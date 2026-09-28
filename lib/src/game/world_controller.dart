import 'dart:async';
import 'package:flame/components.dart';
import 'package:rise_together_game/src/attributes/resetable.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/game/rise_together_levels.dart';
import 'package:rise_together_game/src/game/rise_together_world.dart';
import 'package:rise_together_game/src/game/level_sequence.dart';
import 'package:rise_together_game/src/components/paddle.dart';
import 'package:rise_together_game/src/models/team_thrust.dart';
import 'package:rise_together_game/src/models/team_context.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Controls the connection between team action streams and world paddles
class WorldController with AppLogging, Resetable {
  final RiseTogetherWorld world;
  TeamActionStream get actionStream => _teamContext.actionStream;
  late StreamSubscription<TeamThrust> _thrustSubscription;
  bool shouldUpdateParallax;
  int configuredTeamPlayerCount;

  /// Control reversal state
  bool _controlsReversed = false;

  /// Nesting depth of countdown locks on the authority. See [lockInput].
  /// A count rather than a flag so overlapping countdowns for the same team
  /// cannot release each other early.
  int _inputLockDepth = 0;
  bool get inputLocked => _inputLockDepth > 0;
  TimerComponent? _controlReversalTimer;

  /// Team context providing consolidated team information
  TeamContext _teamContext;
  TeamContext get team => _teamContext;

  /// Level progression tracking
  LevelSequence? _levelSequence;
  int _currentLevelIndex = 0;

  /// Callback for when team reaches the level-end wall
  /// This is called by Ball's contact callback
  void Function()? onLevelCompleted;

  /// Callback for when a level object is consumed
  /// This is called by LevelObject's consume method
  /// Parameters: teamId, spawnId
  void Function(int teamId, int spawnId)? onLevelObjectConsumed;

  WorldController({
    required this.world,
    this.shouldUpdateParallax = true,
    required this.configuredTeamPlayerCount,
    required TeamContext teamContext,
  }) : _teamContext = teamContext {
    // Vital
    world.setWorldController(this);
    _thrustSubscription = actionStream.thrustStream.listen((thrust) {
      _updatePaddleThrust(thrust);
    });
  }

  // void initialize() {
  //   appLog.fine('Initializing WorldController for team ${actionStream.teamId}');
  // }

  // void setActionStream(TeamActionStream newStream) {
  //   // Cancel existing subscription
  //   _thrustSubscription.cancel();

  //   actionStream = newStream;

  //   // Resubscribe to the new stream
  //   _thrustSubscription = actionStream.thrustStream.listen((thrust) {
  //     _updatePaddleThrust(thrust);
  //   });

  //   appLog.fine('Action stream updated for team ${actionStream.teamId}');
  // }

  /// Update the team context and notify the world
  void setTeamContext(TeamContext teamContext) {
    _thrustSubscription.cancel();
    _teamContext = teamContext;
    world.updateTeamContext(teamContext);
    _thrustSubscription = actionStream.thrustStream.listen((thrust) {
      _updatePaddleThrust(thrust);
    });
    // TODO: Fix hack...
    configuredTeamPlayerCount = _teamContext.players.isNotEmpty
        ? _teamContext.players.length
        : 1;
    actionStream.setConfiguredTeamPlayerCount(configuredTeamPlayerCount);
    appLog.fine(
      'Team context updated: ${teamContext.toString()}, configured player count: $configuredTeamPlayerCount',
    );
  }

  /// Get current team context
  TeamContext get teamContext => _teamContext;

  void _updatePaddleThrust(TeamThrust thrust) {
    if (inputLocked) {
      world.paddle.setThrust(0.0, 0.0);
      return;
    }
    // Apply control reversal if active
    final leftThrust = _controlsReversed
        ? thrust.rightThrust
        : thrust.leftThrust;
    final rightThrust = _controlsReversed
        ? thrust.leftThrust
        : thrust.rightThrust;

    // Update paddle with thrust values (potentially reversed).
    // Parallax is driven by ball Y velocity in RiseTogetherWorld.update() instead.
    world.paddle.setThrust(leftThrust, rightThrust);
  }

  /// Hold the paddle still for the duration of a countdown, on the authority.
  ///
  /// Remote input for a locked team is also dropped before it reaches the
  /// stream (see `RiseTogetherGameBase.withTeamInputLocked`); this covers
  /// anything already in it and whatever arrives by another path.
  ///
  /// Actions keep being recorded while locked; they are just not applied.
  void lockInput() {
    _inputLockDepth++;
    world.paddle.setThrust(0.0, 0.0);
    appLog.fine('Input locked for team ${_teamContext.teamId}');
  }

  /// End a [lockInput] window. Everything recorded while locked is dropped,
  /// so the paddle starts from rest. A remote player still holding a button
  /// is back within one input resend.
  void unlockInput() {
    if (_inputLockDepth == 0) return;
    if (--_inputLockDepth > 0) return;
    actionStream.clearAllActions();
    world.paddle.setThrust(0.0, 0.0);
    appLog.fine('Input unlocked for team ${_teamContext.teamId}');
  }

  void stopMovement() {
    world.ball.body.linearVelocity = Vector2.zero();
    world.ball.body.angularVelocity = 0.0;
    world.paddle.body.linearVelocity = Vector2.zero();
    world.paddle.body.angularVelocity = 0.0;
  }

  void clearActions() {
    world.clearActions();
    // @TODO: This doesnt belong here
    world.resetBall();
  }

  Paddle get paddle => world.paddle;

  double levelProgress(double position) {
    // Calculate progress based on paddle position.
    // verticalHeight, NOT verticalMultiplier: position is a world-unit length,
    // and the multiplier is dimensionless. The two only coincide while
    // horizontalWidth == 1. See HeightTrigger for the correct form.
    final progress = position.abs() / world.level.verticalHeight;
    return progress.clamp(0.0, 1.0);
  }

  /// Activate control reversal for a duration
  void activateControlReversal(double durationSeconds) {
    appLog.info(
      'Activating control reversal for team ${_teamContext.teamId} for ${durationSeconds}s',
    );

    _controlsReversed = true;

    // Cancel existing timer if any
    _controlReversalTimer?.removeFromParent();

    // Create new timer for deactivation
    _controlReversalTimer = TimerComponent(
      period: durationSeconds,
      onTick: () {
        _controlsReversed = false;
        appLog.info(
          'Control reversal deactivated for team ${_teamContext.teamId}',
        );
        _controlReversalTimer?.removeFromParent();
      },
      repeat: false,
    );

    // Add timer to world so it updates
    world.add(_controlReversalTimer!);
  }

  /// Check if controls are currently reversed
  bool get controlsReversed => _controlsReversed;

  /// Activate control reversal for a zone (no timer — deactivated by zone exit).
  void activateControlReversalZone() {
    if (_controlsReversed) return;
    _controlsReversed = true;
  }

  /// Deactivate control reversal (zone exit or effect reset).
  void deactivateControlReversal() {
    if (!_controlsReversed) return;
    _controlsReversed = false;
    _controlReversalTimer?.removeFromParent();
    _controlReversalTimer = null;
  }

  /// Reset temporary in-level effects (paddle width, control reversal)
  /// without resetting ball/paddle positions. Called on level advance.
  void resetEffects() {
    _controlsReversed = false;
    _controlReversalTimer?.removeFromParent();
    _controlReversalTimer = null;
    world.paddle.resetTempWidth();
  }

  @override
  void reset() {
    world.reset();
    actionStream.clearAllActions();

    // Reset control reversal
    _controlsReversed = false;
    _controlReversalTimer?.removeFromParent();

    // Update distance tracker with ball's start position
    world.gameRef.distanceTracker.setStartingHeight(
      _teamContext.teamId,
      world.ball.startPosition.y,
    );

    appLog.fine('WorldController reset for team ${actionStream.teamId}');
  }

  void updatePaddleWidth(double widthMultiplier) {
    // Update the base width multiplier (from configuration)
    // This will recalculate the paddle shape using the stored original width
    world.paddle.setBaseWidthMultiplier(widthMultiplier);
  }

  // ============================================================================
  // Level Progression Methods
  // ============================================================================

  /// Set the level sequence for this team
  void setLevelSequence(LevelSequence sequence) {
    _levelSequence = sequence;
    _currentLevelIndex = 0; // Reset to first level
    appLog.info(
      'Level sequence set for team ${_teamContext.teamId}: ${sequence.levelCount} levels',
    );
  }

  /// Get the current level index
  int get currentLevelIndex => _currentLevelIndex;

  /// Get the level sequence
  LevelSequence? get levelSequence => _levelSequence;

  /// Get the current level
  RiseTogetherLevel get currentLevel {
    if (_levelSequence == null) {
      return world.lastLoadedLevel ??
          const Level1(); // Fallback; avoids circular call through world.level
    }
    return _levelSequence!.getLevelAt(_currentLevelIndex);
  }

  /// Set the current level index (used by coordinator when synchronizing)
  void setLevelIndex(int index) {
    if (_levelSequence == null) {
      appLog.warning(
        'Attempted to set level index but no level sequence is set',
      );
      return;
    }
    _currentLevelIndex = index;
    appLog.info('Team ${_teamContext.teamId} level index set to $index');
  }

  /// Advance to the next level in the sequence
  /// Returns the new level index, or current index if already at last level
  int advanceLevel() {
    if (_levelSequence == null) {
      appLog.warning('Attempted to advance level but no level sequence is set');
      return _currentLevelIndex;
    }

    final nextIndex = _levelSequence!.getNextLevelIndex(_currentLevelIndex);

    // Check if we're already at the last level
    if (nextIndex == _currentLevelIndex) {
      appLog.info(
        'Team ${_teamContext.teamId} already at last level ($nextIndex)',
      );
      return _currentLevelIndex;
    }

    appLog.info(
      'Team ${_teamContext.teamId} advancing from level $_currentLevelIndex to $nextIndex',
    );

    _currentLevelIndex = nextIndex;
    return _currentLevelIndex;
  }

  /// Reset to the first level in the sequence
  void resetToFirstLevel() {
    _currentLevelIndex = 0;
    appLog.info('Team ${_teamContext.teamId} reset to first level');
  }

  void dispose() {
    _thrustSubscription.cancel();
    _controlReversalTimer?.removeFromParent();
    appLog.fine('WorldController disposed for team ${actionStream.teamId}');
  }
}
