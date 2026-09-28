import 'dart:async';

import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';

/// What the game needs from a multiplayer session, and nothing more.
///
/// One peer is the *authority*: it runs the physics and tells everyone else
/// what happened. The others are followers, which send their inputs to the
/// authority and render the state it broadcasts.
///
/// Solo play has no session at all (see `LocalActionProvider`). The game
/// treats a null session as "local and authoritative".
///
/// ## Trust
///
/// Nothing that arrives through a session is trusted, the authority's
/// messages included: any peer can be a modified client. Every decoder in
/// this file therefore validates types *and* ranges and returns null for
/// anything it does not fully understand, and callers drop nulls.
///
/// - No free text crosses the wire for display. Countdown messages carry a
///   level index and each device renders its own translated string.
/// - Nothing received is persisted. [MatchRules] is applied in memory for the
///   one match, never written to the player's settings.
/// - Implementations must fill in who sent an input from the transport's
///   authenticated sender id, never from the message body (see
///   [PlayerActionMessage]).
///
/// What validation cannot prevent is a dishonest authority: it runs the
/// physics, so it can misreport the game. Validation keeps a hostile peer from
/// crashing or reconfiguring *this* device, not from cheating at the game.
abstract class GameSession {
  /// Whether this peer runs the authoritative simulation.
  bool get isAuthority;

  /// This peer's own place in the game.
  PlayerAssignment get localAssignment;

  /// Everyone in the game, this peer included.
  List<PlayerAssignment> get assignments;

  /// Fires whenever [assignments] changes.
  Stream<void> get assignmentsChanged;

  /// The rules the authority chose for this match.
  MatchRules get rules;

  // --- followers -> authority ----------------------------------------------

  /// Send the local player's input to the authority.
  ///
  /// On the authority itself, implementations deliver it to [actions]
  /// directly, so the host's own input takes the same path as everyone else's.
  void sendAction(PaddleAction action);

  /// Inputs from every player, delivered on the authority only.
  ///
  /// [PlayerActionMessage.playerId] and [PlayerActionMessage.teamId] come from
  /// the roster entry of the peer that actually sent the input, so one player
  /// cannot press another's buttons.
  Stream<PlayerActionMessage> get actions;

  // --- authority -> followers ----------------------------------------------

  /// Publish one physics sample (see `PhysicsChannels` for the layout).
  ///
  /// Must copy [state] synchronously: the caller reuses the buffer.
  void broadcastPhysics(List<double> state);

  /// Physics samples, delivered on followers only. Samples are passed through
  /// [validPhysicsSample] before delivery.
  Stream<List<double>> get physics;

  /// Publish a discrete game event to every follower.
  void broadcastEvent(GameEvent event);

  /// Game events, delivered on followers only.
  Stream<GameEvent> get events;

  /// Tell the authority this device's game for [round] is loaded and
  /// listening.
  ///
  /// Followers call this once their game is configured; a no-op on the
  /// authority. Rounds count from 0; a [Rematch] starts the next one.
  Future<void> markReady({int round = 0});

  /// On the authority: wait until every follower has called [markReady] for
  /// [round], or [timeout] passes. Returns whether everyone made it.
  Future<bool> waitForPlayersReady(Duration timeout, {int round = 0});

  /// Fires once if the session ends without this device choosing to leave.
  Stream<SessionEnd> get ended;

  /// Leave the session and release its resources.
  Future<void> leave();
}

/// Why a session ended underneath the player.
enum SessionEnd {
  /// The host left or stopped responding; the match cannot continue.
  hostLeft,

  /// This device lost its connection.
  connectionLost,

  /// The host removed this device.
  removed,
}

/// How players are split across the two teams.
enum MatchMode {
  /// Everyone on one team, racing the clock; the other arena stays empty.
  coop,

  /// Two teams racing each other.
  versus,
}

/// Team ids a message may name. There are always exactly two teams.
bool _isTeamId(Object? value) => value == 0 || value == 1;

/// Highest round number a [Rematch] or ready signal may carry. A session is
/// a handful of rounds; this only bounds what a hostile peer can make us track.
const int maxRound = 999;

bool _isRound(Object? value) => value is int && value >= 0 && value <= maxRound;

/// Upper bound on level indices. The game has far fewer levels; this only
/// keeps a hostile value from reaching list indexing.
const int maxLevelIndex = 99;

bool _isLevelIndex(Object? value) =>
    value is int && value >= 0 && value <= maxLevelIndex;

/// Largest absolute value a physics channel may carry. Positions, angles and
/// bitflags in this game stay well inside it; anything larger is malformed.
const double maxPhysicsMagnitude = 1e6;

/// Whether [state] is a physics sample this device may apply: the expected
/// length, and every value finite and within [maxPhysicsMagnitude].
///
/// NaN or infinity reaching Box2D would poison the body transform for the rest
/// of the match.
bool validPhysicsSample(List<double> state, {required int expectedLength}) {
  if (state.length != expectedLength) return false;
  for (final value in state) {
    if (!value.isFinite || value.abs() > maxPhysicsMagnitude) return false;
  }
  return true;
}

/// Match settings the authority decides for everyone.
///
/// Deliberately tiny. Physics constants are not negotiable over the network:
/// every build plays with the same ones.
final class MatchRules {
  const MatchRules({
    required this.mode,
    required this.roundDurationSeconds,
    required this.seed,
  });

  final MatchMode mode;

  static const double minRoundSeconds = 30;
  static const double maxRoundSeconds = 600;
  static const int maxSeed = 0x7fffffff;

  final double roundDurationSeconds;

  /// Seed for obstacle placement, shared so every device builds the same
  /// levels.
  final int seed;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'roundDurationSeconds': roundDurationSeconds,
    'seed': seed,
  };

  /// Returns null unless every field is present, typed and in range.
  static MatchRules? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final mode = MatchMode.values
        .where((m) => m.name == json['mode'])
        .firstOrNull;
    final duration = json['roundDurationSeconds'];
    final seed = json['seed'];
    if (mode == null) return null;
    // JSON turns 180.0 into 180, so accept any number for the duration.
    if (duration is! num || !duration.isFinite) return null;
    if (duration < minRoundSeconds || duration > maxRoundSeconds) return null;
    if (seed is! int || seed < 0 || seed > maxSeed) return null;
    return MatchRules(
      mode: mode,
      roundDurationSeconds: duration.toDouble(),
      seed: seed,
    );
  }

  @override
  String toString() =>
      'MatchRules(${mode.name}, ${roundDurationSeconds}s, seed $seed)';
}

/// One player's input, as delivered to the authority.
final class PlayerActionMessage {
  const PlayerActionMessage({
    required this.teamId,
    required this.playerId,
    required this.action,
  });

  final int teamId;
  final String playerId;
  final PaddleAction action;

  /// Only the action goes on the wire; who sent it is the transport's to say.
  static Map<String, dynamic> encodeAction(PaddleAction action) => {
    'action': action.name,
  };

  /// Decode an action from the wire. Returns null for anything unknown.
  static PaddleAction? decodeAction(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['action'];
    if (name is! String) return null;
    for (final action in PaddleAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }

  @override
  String toString() => 'PlayerActionMessage($teamId, $playerId, $action)';
}

/// Something the authority decided that every follower must mirror.
sealed class GameEvent {
  const GameEvent();

  String get type;

  Map<String, dynamic> toJson();

  /// Returns null for an unknown, malformed or out-of-range event.
  static GameEvent? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final teamId = json['teamId'];
    final levelIndex = json['levelIndex'];
    final stateIndex = json['stateIndex'];
    switch (json['type']) {
      case TeamLevelProgression.typeName:
        final seed = json['seed'];
        if (!_isTeamId(teamId) || !_isLevelIndex(levelIndex)) return null;
        if (seed is! int || seed < 0 || seed > MatchRules.maxSeed) return null;
        return TeamLevelProgression(
          teamId: teamId as int,
          levelIndex: levelIndex as int,
          seed: seed,
        );
      case LevelObjectConsumed.typeName:
        final spawnId = json['spawnId'];
        if (!_isTeamId(teamId)) return null;
        if (spawnId is! int || spawnId < 0) return null;
        return LevelObjectConsumed(teamId: teamId as int, spawnId: spawnId);
      case TeamCountdownState.typeName:
        if (!_isTeamId(teamId) || !_isStateIndex(stateIndex)) return null;
        if (levelIndex != null && !_isLevelIndex(levelIndex)) return null;
        return TeamCountdownState(
          teamId: teamId as int,
          stateIndex: stateIndex as int,
          levelIndex: levelIndex as int?,
        );
      case TeamCountdownTrigger.typeName:
        if (!_isTeamId(teamId)) return null;
        if (levelIndex != null && !_isLevelIndex(levelIndex)) return null;
        return TeamCountdownTrigger(
          teamId: teamId as int,
          levelIndex: levelIndex as int?,
        );
      case GlobalCountdownState.typeName:
        if (!_isStateIndex(stateIndex)) return null;
        return GlobalCountdownState(stateIndex: stateIndex as int);
      case Rematch.typeName:
        final seed = json['seed'];
        final round = json['round'];
        if (!_isRound(round) || round == 0) return null;
        if (seed is! int || seed < 0 || seed > MatchRules.maxSeed) return null;
        return Rematch(round: round as int, seed: seed);
      case RoundOver.typeName:
        final levels = json['levels'];
        final distances = json['distances'];
        if (levels is! List || levels.length != 2) return null;
        if (distances is! List || distances.length != 2) return null;
        if (!levels.every(_isLevelIndex)) return null;
        if (!distances.every(_isDistance)) return null;
        return RoundOver(
          levels: [for (final l in levels) l as int],
          distances: [for (final d in distances) (d as num).toDouble()],
        );
      default:
        return null;
    }
  }

  /// Metres climbed. Generous: the levels are nowhere near this tall.
  static bool _isDistance(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 1e6;

  /// Countdown states are an enum index; the game re-checks it against the
  /// enum, this only rules out nonsense.
  static bool _isStateIndex(Object? value) =>
      value is int && value >= 0 && value < 16;
}

/// A team finished a level; followers load [levelIndex] with [seed].
final class TeamLevelProgression extends GameEvent {
  const TeamLevelProgression({
    required this.teamId,
    required this.levelIndex,
    required this.seed,
  });

  static const typeName = 'team_level_progression';

  final int teamId;
  final int levelIndex;
  final int seed;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'teamId': teamId,
    'levelIndex': levelIndex,
    'seed': seed,
  };
}

/// A power-up or obstacle was used up and must disappear everywhere.
final class LevelObjectConsumed extends GameEvent {
  const LevelObjectConsumed({required this.teamId, required this.spawnId});

  static const typeName = 'level_object_consumed';

  final int teamId;
  final int spawnId;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'teamId': teamId,
    'spawnId': spawnId,
  };
}

/// One step of a team's countdown, mirrored as the authority runs it.
///
/// [levelIndex] is set when the countdown announces a new level; followers
/// render that announcement themselves.
final class TeamCountdownState extends GameEvent {
  const TeamCountdownState({
    required this.teamId,
    required this.stateIndex,
    this.levelIndex,
  });

  static const typeName = 'team_countdown_state';

  final int teamId;
  final int stateIndex;
  final int? levelIndex;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'teamId': teamId,
    'stateIndex': stateIndex,
    'levelIndex': levelIndex,
  };
}

/// Start a whole countdown locally; the authority waits the same duration.
final class TeamCountdownTrigger extends GameEvent {
  const TeamCountdownTrigger({required this.teamId, this.levelIndex});

  static const typeName = 'team_countdown_trigger';

  final int teamId;
  final int? levelIndex;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'teamId': teamId,
    'levelIndex': levelIndex,
  };
}

/// One step of the game-wide start countdown.
final class GlobalCountdownState extends GameEvent {
  const GlobalCountdownState({required this.stateIndex});

  static const typeName = 'countdown_state';

  final int stateIndex;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'type': type, 'stateIndex': stateIndex};
}

/// The authority's final result for a round, so every screen agrees.
///
/// Followers do not simulate, so their own tallies cannot be trusted to match;
/// they show this instead.
final class RoundOver extends GameEvent {
  const RoundOver({required this.levels, required this.distances});

  static const typeName = 'round_over';

  /// Level reached per team, indexed by team id.
  final List<int> levels;

  /// Metres climbed per team, indexed by team id.
  final List<double> distances;

  /// 0 or 1 for the winning team, -1 for a tie: higher level first, then the
  /// greater distance, matching `RoundResult.roundWinner`.
  int get winner {
    if (levels[0] != levels[1]) return levels[0] > levels[1] ? 0 : 1;
    if (distances[0] != distances[1]) {
      return distances[0] > distances[1] ? 0 : 1;
    }
    return -1;
  }

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'levels': levels,
    'distances': distances,
  };
}

/// The authority starts another round on the same connection.
///
/// Every device builds a fresh game for [round] with obstacles from [seed].
final class Rematch extends GameEvent {
  const Rematch({required this.round, required this.seed});

  static const typeName = 'rematch';

  final int round;
  final int seed;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'type': type, 'round': round, 'seed': seed};
}
