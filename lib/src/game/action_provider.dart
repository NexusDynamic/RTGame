import 'dart:async';

import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/local_action_bridge.dart';
import 'package:rise_together_game/src/net/network_bridge.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';
import 'package:rise_together_game/src/net/session_action_bridge.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Connects the game to its players: where local input goes, who is playing,
/// and whether this device runs the physics.
abstract class ActionProvider {
  ActionStreamManager get actionManager;
  NetworkBridge get networkBridge;

  /// The multiplayer session, or null for solo play.
  GameSession? get session;

  /// Whether this device runs the authoritative physics.
  bool get isCoordinator;

  /// This device's player.
  PlayerAssignment get currentPlayerAssignment;

  /// Every player in the game.
  List<PlayerAssignment> get playerAssignments;

  Future<void> initialize();

  void dispose();
}

/// Solo play: one player, local physics, no network.
class LocalActionProvider implements ActionProvider {
  LocalActionProvider(
    ActionStreamManager? actionManager, {
    PlayerAssignment? assignment,
  }) : _actionManager = actionManager ?? ActionStreamManager(),
       _assignment =
           assignment ??
           PlayerAssignment(
             nodeId: 'local',
             nodeName: 'Local Player',
             teamId: 0,
             playerId: 'local_player',
             isCoordinator: true,
           );

  final ActionStreamManager _actionManager;
  final PlayerAssignment _assignment;
  late final NetworkBridge _networkBridge = LocalActionBridge(
    actionManager: _actionManager,
  );
  bool _initialized = false;

  @override
  ActionStreamManager get actionManager => _actionManager;

  @override
  NetworkBridge get networkBridge => _networkBridge;

  @override
  GameSession? get session => null;

  @override
  bool get isCoordinator => true;

  @override
  PlayerAssignment get currentPlayerAssignment => _assignment;

  @override
  List<PlayerAssignment> get playerAssignments => [_assignment];

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _networkBridge.initialize();
  }

  @override
  void dispose() => _networkBridge.dispose();
}

/// Online play over a [GameSession].
///
/// On the authority, every player's input (its own included) arrives through
/// [GameSession.actions] and is fed into the matching team stream, exactly as
/// [LocalActionBridge] does for solo play.
class SessionActionProvider with AppLogging implements ActionProvider {
  SessionActionProvider(this._session, ActionStreamManager actionManager)
    : _actionManager = actionManager,
      _networkBridge = SessionActionBridge(_session);

  final GameSession _session;
  final ActionStreamManager _actionManager;

  /// Consulted before a remote input is applied; false drops it. The game
  /// uses this to lock a team's paddle during its countdown, which a
  /// follower's own client would otherwise be trusted to respect.
  bool Function(int teamId)? acceptInput;
  final NetworkBridge _networkBridge;
  StreamSubscription<PlayerActionMessage>? _actionSubscription;
  bool _initialized = false;

  @override
  ActionStreamManager get actionManager => _actionManager;

  @override
  NetworkBridge get networkBridge => _networkBridge;

  @override
  GameSession get session => _session;

  @override
  bool get isCoordinator => _session.isAuthority;

  @override
  PlayerAssignment get currentPlayerAssignment => _session.localAssignment;

  @override
  List<PlayerAssignment> get playerAssignments => _session.assignments;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _networkBridge.initialize();
    if (_session.isAuthority) {
      _actionSubscription = _session.actions.listen(_applyRemoteAction);
    }
  }

  void _applyRemoteAction(PlayerActionMessage message) {
    if (acceptInput?.call(message.teamId) == false) return;
    final teamStream = _actionManager.getTeamStream(message.teamId);
    if (teamStream == null) {
      appLog.warning('Action for unknown team ${message.teamId}, dropped');
      return;
    }
    teamStream.addAction(GameAction(message.playerId, message.action));
  }

  @override
  void dispose() {
    _actionSubscription?.cancel();
    _actionSubscription = null;
    _networkBridge.dispose();
  }
}
