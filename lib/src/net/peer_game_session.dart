import 'dart:async';

import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Coordination timings. Production defaults; tests shrink them.
class SessionTimings {
  const SessionTimings({
    this.heartbeatInterval = const Duration(seconds: 2),
    this.discoveryInterval = const Duration(seconds: 1),
    this.nodeTimeout = const Duration(seconds: 8),
    this.hostJoinWindow = const Duration(seconds: 3),
    this.joinAttemptWindow = const Duration(seconds: 15),
    this.joinRetryDelay = const Duration(seconds: 1),
  });

  /// `peer_coordinator` hands `join(timeout - 1s)` to the election, so a
  /// window at or under a second leaves it no time at all: discovery returns
  /// empty at once, a joiner gives up and a second host promotes itself.
  static const Duration electionReserve = Duration(seconds: 1);

  final Duration heartbeatInterval;
  final Duration discoveryInterval;

  /// Must be at least twice [heartbeatInterval].
  final Duration nodeTimeout;

  /// The host's `join` timeout. `peer_coordinator` spends all but a second of
  /// it looking for an existing coordinator before promoting itself, so this
  /// is how long a host takes to open its room. Keep it short: joiners who
  /// arrive meanwhile see a coordinator that does not exist yet.
  final Duration hostJoinWindow;

  /// A joiner's `join` timeout for one attempt, retried until the overall
  /// deadline while the host is not there yet.
  ///
  /// Long on purpose. Election discovery returns the moment a host appears,
  /// so a long window costs nothing when one exists. It must also outlast
  /// `peer_coordinator`'s own connect-to-host search (ten discovery
  /// intervals): a shorter window times `join` out while that search runs on
  /// in the background, and it later fails with nobody listening.
  final Duration joinAttemptWindow;

  final Duration joinRetryDelay;
}

/// A [GameSession] over `peer_coordinator`.
///
/// Roles are explicit: exactly one device connects with `host: true` (the
/// lobby decides which) and only it may coordinate. Leaving it to an election
/// raced: two devices arriving together could each defer to the other. The
/// host assigns teams, creates the streams and runs the physics, and its loss
/// ends the match ([CoordinatorLossPolicy.endSession]).
///
/// ## Channels
///
/// - **Input**: a data stream, participants → host, one int channel holding
///   the player's *current* [PaddleAction]. The host attributes each sample
///   by the transport's `sourceId` (the link it arrived on), never by anything
///   in the payload. State is re-sent every [inputResendInterval], so a lost
///   packet — the data channels are lossy — cannot leave a paddle stuck.
/// - **Physics**: a data stream, host → everyone, `PhysicsChannels` floats.
/// - **Setup and events**: user messages, host → everyone.
///
/// Participants ignore every user message from anyone but the host, and the
/// host ignores user messages entirely: nothing it needs travels that way.
class PeerGameSession with AppLogging implements GameSession {
  PeerGameSession._(this._session, this._playerCount);

  static const String matchMessageType = 'rt_match';
  static const String eventMessageType = 'rt_event';
  static const String readyMessageType = 'rt_ready';
  static const String inputStreamName = 'rt_input';
  static const String physicsStreamName = 'rt_physics';

  /// Players a match can hold. Bounded by the float32 press-indicator bits.
  static const int maxPlayers = 8;

  /// Longest nickname kept from another peer.
  static const int maxNicknameLength = 16;

  static const Duration inputResendInterval = Duration(milliseconds: 200);

  /// Samples per second one peer may send before the excess is dropped. The
  /// honest rate is a handful: one per change plus 5 resends.
  static const int maxInputsPerSecond = 60;

  final PeerSession _session;
  final int _playerCount;

  /// Whether this device hosts. Only a `host: true` connect can be.
  bool get _isHost => _session.isCoordinator;

  final _setup = Completer<Map<String, dynamic>>();
  StreamSubscription<UserMessageEvent>? _setupSubscription;

  late final MatchRules _rules;
  late final List<PlayerAssignment> _assignments;
  late final PlayerAssignment _local;

  DataStream? _inputStream;
  DataStream? _physicsStream;

  final _actions = StreamController<PlayerActionMessage>.broadcast();
  final _physics = StreamController<List<double>>.broadcast();
  final _events = StreamController<GameEvent>.broadcast();
  final _ended = StreamController<SessionEnd>.broadcast();
  final _assignmentsChanged = StreamController<void>.broadcast();

  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Followers that have reported ready, per round, host only.
  final Map<int, Set<String>> _readyPlayers = {};
  final _readyChanged = StreamController<void>.broadcast();
  Timer? _resendTimer;
  PaddleAction _localAction = PaddleAction.none;
  bool _closed = false;

  /// Per-sender input budget for the current second, host only.
  final Map<String, int> _inputBudget = {};
  Timer? _budgetReset;

  // --- setup --------------------------------------------------------------

  /// Join [roomName] as its host or as a player. Call [startMatch] next.
  ///
  /// A joiner retries until the host is there or [timeout] passes; a host
  /// fails straight away if the room already has one. Throws on failure, with
  /// the session already torn down.
  static Future<PeerGameSession> connect({
    required ITransportConfig transport,
    required String roomName,
    required String nickname,
    required int playerCount,
    required bool host,
    Duration timeout = const Duration(seconds: 30),
    SessionTimings timings = const SessionTimings(),
  }) async {
    if (playerCount < 2 || playerCount > maxPlayers) {
      throw ArgumentError.value(playerCount, 'playerCount');
    }
    for (final window in [timings.hostJoinWindow, timings.joinAttemptWindow]) {
      if (window <= SessionTimings.electionReserve) {
        throw ArgumentError.value(
          window,
          'timings',
          'join windows must exceed ${SessionTimings.electionReserve}',
        );
      }
    }
    final name = _sanitizeNickname(nickname, fallback: 'Player');
    final deadline = DateTime.now().add(timeout);

    while (true) {
      final game = PeerGameSession._(
        _createSession(transport, roomName, name, playerCount, host, timings),
        playerCount,
      );
      try {
        await game._join(
          host ? timings.hostJoinWindow : timings.joinAttemptWindow,
        );
        if (host && !game.isAuthority) {
          throw StateError('Room "$roomName" already has a host');
        }
        return game;
      } catch (e) {
        await game.leave();
        // Only a joiner waits for a host that has not arrived yet.
        final retry =
            !host &&
            (e is StateError || e is TimeoutException) &&
            DateTime.now().add(timings.joinRetryDelay).isBefore(deadline);
        if (!retry) rethrow;
        await Future<void>.delayed(timings.joinRetryDelay);
      }
    }
  }

  static PeerSession _createSession(
    ITransportConfig transport,
    String roomName,
    String name,
    int playerCount,
    bool host,
    SessionTimings timings,
  ) => PeerSession.create(
    CoordinationConfig(
      name: 'rise_together',
      sessionConfig: CoordinationSessionConfig(
        name: roomName,
        maxNodes: playerCount,
        heartbeatInterval: timings.heartbeatInterval,
        discoveryInterval: timings.discoveryInterval,
        nodeTimeout: timings.nodeTimeout,
        // The host's own messages are not needed back.
        consumeCoordinationStreamAsCoordinator: false,
        coordinatorLossPolicy: CoordinatorLossPolicy.endSession,
      ),
      // Rolls are fixed, not random, to make the election deterministic: a
      // node defers to any peer with a lower roll or to a live coordinator.
      // The host (0) therefore defers only to an existing host, and joiners
      // (1) defer to the host even while it is still electing. Start-time
      // ordering, the alternative, lets a host defer to an earlier *joiner*,
      // which cannot coordinate.
      topologyConfig: HierarchicalTopologyConfig(
        promotionStrategy: PromotionStrategyRandom(),
        maxNodes: playerCount,
      ),
      transportConfig: transport,
    ),
    thisNodeConfig: NodeConfig(
      name: name,
      id: name,
      // A joiner can never be promoted, so it can never take over a room.
      capabilities: host
          ? {NodeCapability.coordinator, NodeCapability.participant}
          : {NodeCapability.participant},
      metadata: {PeerMetadataKeys.randomRoll: host ? '0' : '1'},
    ),
  );

  Future<void> _join(Duration window) async {
    // Subscribe before joining: `events` buffers nothing, and the host's
    // setup can arrive the moment the join completes.
    _setupSubscription = _session.events.userMessages.listen((event) {
      if (event is! UserCoordinationEvent) return;
      if (event.messageType != matchMessageType) return;
      if (event.fromNodeUId != _session.coordinatorUId) return;
      if (!_setup.isCompleted) _setup.complete(event.payload);
    });
    await _session.initialize();
    await _session.join(window);
  }

  /// Wait until the match is ready to play.
  ///
  /// The host waits for everyone to arrive, then assigns teams and creates the
  /// streams using [hostRules]. Everyone else waits for the host's setup and
  /// validates it. Throws [TimeoutException] or [StateError] on failure, with
  /// the session already torn down.
  Future<void> startMatch({
    required MatchRules hostRules,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      if (isAuthority) {
        await _hostSetup(hostRules, _playerCount, timeout);
      } else {
        await _participantSetup(await _setup.future.timeout(timeout));
      }
      await _setupSubscription?.cancel();
      _setupSubscription = null;
      _listen();
    } catch (_) {
      await leave();
      rethrow;
    }
  }

  /// Players in the room so far, this device included.
  int get memberCount => _members().length;

  static String _sanitizeNickname(String raw, {required String fallback}) {
    // Printable characters only: this is shown on other players' screens.
    final cleaned = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (cleaned.isEmpty) return fallback;
    return cleaned.length > maxNicknameLength
        ? cleaned.substring(0, maxNicknameLength)
        : cleaned;
  }

  /// Everyone in the room, this device first, by uId.
  Map<String, Node> _members() => {
    _session.thisNode.uId: _session.thisNode,
    for (final node in _session.connectedNodes) node.uId: node,
  };

  Future<void> _hostSetup(
    MatchRules rules,
    int playerCount,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (_members().length < playerCount) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException('Waiting for $playerCount players', timeout);
      }
      await _session.events.nodeJoined.first.timeout(remaining);
    }
    await _session.pauseAcceptingNodes();

    final members = _members().values.take(playerCount).toList();
    _rules = rules;
    _assignments = [
      for (var i = 0; i < members.length; i++)
        PlayerAssignment(
          nodeId: members[i].uId,
          nodeName: _sanitizeNickname(
            members[i].name,
            fallback: 'Player ${i + 1}',
          ),
          // Co-op: everyone lifts the same paddle. Versus: alternate, so
          // teams differ in size by at most one.
          teamId: rules.mode == MatchMode.coop ? 0 : i % 2,
          playerId: members[i].uId,
          isCoordinator: i == 0,
        ),
    ];
    _local = _assignments.first;

    // Created before the setup message goes out: participants build their
    // ends on the create command, and the input stream's creation waits for
    // them to report ready.
    _inputStream = await _session.createDataStream(
      DataStreamConfig(
        name: inputStreamName,
        channels: 1,
        sampleRate: 20,
        dataType: StreamDataType.int32,
        participationMode:
            StreamParticipationMode.sendParticipantsReceiveCoordinator,
        precisePolling: false,
      ),
    );
    _physicsStream = await _session.createDataStream(
      DataStreamConfig(
        name: physicsStreamName,
        channels: 16,
        sampleRate: 60,
        dataType: StreamDataType.float32,
        participationMode: StreamParticipationMode.coordinatorOnly,
        precisePolling: false,
      ),
    );
    await _session.startStream(inputStreamName);
    await _session.startStream(physicsStreamName);

    await _session.sendUserMessage(matchMessageType, 'match setup', {
      'rules': rules.toJson(),
      'players': [for (final a in _assignments) a.toMap()],
    });
    appLog.info('Hosting match: $rules, ${_assignments.length} players');
  }

  Future<void> _participantSetup(Map<String, dynamic> payload) async {
    final rules = MatchRules.fromJson(payload['rules']);
    if (rules == null) throw StateError('Host sent invalid match rules');

    final rawPlayers = payload['players'];
    if (rawPlayers is! List || rawPlayers.length > maxPlayers) {
      throw StateError('Host sent an invalid roster');
    }
    final players = <PlayerAssignment>[];
    final seen = <String>{};
    for (final raw in rawPlayers) {
      final player = PlayerAssignment.tryFromMap(raw);
      if (player == null || !seen.add(player.nodeId)) {
        throw StateError('Host sent an invalid roster entry');
      }
      players.add(player);
    }
    final self = players.where((p) => p.nodeId == _session.thisNode.uId);
    final hosts = players.where((p) => p.isCoordinator);
    if (self.length != 1 ||
        hosts.length != 1 ||
        hosts.single.nodeId != _session.coordinatorUId) {
      throw StateError('Roster does not match this session');
    }

    _rules = rules;
    _assignments = List.unmodifiable(players);
    _local = self.single;

    _inputStream = await _awaitStream(inputStreamName);
    _physicsStream = await _awaitStream(physicsStreamName);
    appLog.info('Joined match: $rules as team ${_local.teamId}');
  }

  /// Participants build their streams on the host's command; poll until ours
  /// exists.
  Future<DataStream> _awaitStream(String name) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      try {
        return await _session.getDataStream(name);
      } on ArgumentError {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Stream $name never appeared');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  }

  void _listen() {
    if (_isHost) {
      _subscriptions.add(_inputStream!.inbox.listen(_onInputSample));
      _subscriptions.add(_session.events.nodeLeft.listen(_onNodeLeft));
      _subscriptions.add(
        _session.events.userMessages.listen(_onParticipantMessage),
      );
      _budgetReset = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _inputBudget.clear(),
      );
    } else {
      _subscriptions.add(_physicsStream!.inbox.listen(_onPhysicsSample));
      _subscriptions.add(_session.events.userMessages.listen(_onUserMessage));
      _resendTimer = Timer.periodic(
        inputResendInterval,
        (_) => _publishLocalAction(),
      );
    }
    _subscriptions.add(_session.events.sessionEnded.listen(_onSessionEnded));
  }

  // --- host: incoming ----------------------------------------------------

  PlayerAssignment? _playerFor(String? nodeUId) {
    if (nodeUId == null) return null;
    for (final player in _assignments) {
      if (player.nodeId == nodeUId) return player;
    }
    return null;
  }

  void _onInputSample(IMessage message) {
    // The transport's view of who sent this, not the sender's claim.
    final player = _playerFor(message.timing?.sourceId);
    if (player == null || player.isCoordinator) return;

    final used = _inputBudget[player.nodeId] ?? 0;
    if (used >= maxInputsPerSecond) return;
    _inputBudget[player.nodeId] = used + 1;

    if (message.data.length != 1) return;
    final index = message.data.first;
    if (index is! int || index < 0 || index >= PaddleAction.values.length) {
      return;
    }
    _actions.add(
      PlayerActionMessage(
        teamId: player.teamId,
        playerId: player.playerId,
        action: PaddleAction.values[index],
      ),
    );
  }

  /// The only message the host accepts from a participant: "I'm ready".
  ///
  /// Readiness can only unblock the start, so a spoofed sender (the WebRTC
  /// control path takes the sender id from the message) can at worst start
  /// the round a moment early for someone who is still loading.
  void _onParticipantMessage(UserMessageEvent event) {
    if (event is! UserParticipantEvent) return;
    if (event.messageType != readyMessageType) return;
    final player = _playerFor(event.fromNodeUId);
    if (player == null || player.isCoordinator) return;
    final round = event.payload['round'];
    if (round is! int || round < 0 || round > maxRound) return;
    // Only the current round and the next are worth remembering; this bounds
    // what a peer spamming round numbers can make the host store.
    _readyPlayers.removeWhere((r, _) => r < round - 1);
    if (_readyPlayers.length > 4) return;
    if ((_readyPlayers[round] ??= {}).add(player.nodeId)) {
      _readyChanged.add(null);
    }
  }

  /// A player who leaves stops pressing.
  void _onNodeLeft(NodeLeftEvent event) {
    final player = _playerFor(event.node.uId);
    if (player == null) return;
    _actions.add(
      PlayerActionMessage(
        teamId: player.teamId,
        playerId: player.playerId,
        action: PaddleAction.none,
      ),
    );
  }

  // --- participant: incoming -------------------------------------------------

  void _onPhysicsSample(IMessage message) {
    if (message.timing?.sourceId != _session.coordinatorUId) return;
    final values = <double>[];
    for (final value in message.data) {
      if (value is! num) return;
      values.add(value.toDouble());
    }
    _physics.add(values);
  }

  void _onUserMessage(UserMessageEvent event) {
    if (event is! UserCoordinationEvent) return;
    if (event.fromNodeUId != _session.coordinatorUId) return;
    if (event.messageType != eventMessageType) return;
    final decoded = GameEvent.fromJson(event.payload);
    if (decoded != null) _events.add(decoded);
  }

  void _onSessionEnded(SessionEndedEvent event) {
    if (_closed) return;
    _ended.add(switch (event.reason) {
      SessionEndReason.coordinatorLeft ||
      SessionEndReason.coordinatorTimedOut => SessionEnd.hostLeft,
      SessionEndReason.coordinatorTransportLost => SessionEnd.connectionLost,
      SessionEndReason.evicted => SessionEnd.removed,
    });
  }

  // --- GameSession --------------------------------------------------------

  @override
  bool get isAuthority => _isHost;

  @override
  PlayerAssignment get localAssignment => _local;

  @override
  List<PlayerAssignment> get assignments => _assignments;

  @override
  Stream<void> get assignmentsChanged => _assignmentsChanged.stream;

  @override
  MatchRules get rules => _rules;

  @override
  void sendAction(PaddleAction action) {
    if (_closed) return;
    if (_isHost) {
      _actions.add(
        PlayerActionMessage(
          teamId: _local.teamId,
          playerId: _local.playerId,
          action: action,
        ),
      );
      return;
    }
    _localAction = action;
    _publishLocalAction();
  }

  void _publishLocalAction() {
    final stream = _inputStream;
    if (_closed || stream == null) return;
    unawaited(
      stream.sendData([_localAction.index]).catchError((Object e) {
        appLog.fine('Input send failed: $e');
      }),
    );
  }

  @override
  Future<void> markReady({int round = 0}) async {
    if (_closed || _isHost) return;
    await _session.sendUserMessage(readyMessageType, 'ready', {'round': round});
  }

  @override
  Future<bool> waitForPlayersReady(Duration timeout, {int round = 0}) async {
    if (!_isHost) return true;
    final followers = _assignments.where((a) => !a.isCoordinator).length;
    bool allReady() => (_readyPlayers[round]?.length ?? 0) >= followers;
    if (allReady()) return true;
    try {
      await _readyChanged.stream.firstWhere((_) => allReady()).timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Stream<PlayerActionMessage> get actions => _actions.stream;

  @override
  void broadcastPhysics(List<double> state) {
    final stream = _physicsStream;
    if (_closed || !_isHost || stream == null) return;
    // Copied now: the caller reuses its buffer before the send completes.
    unawaited(
      stream.sendData(List<double>.of(state)).catchError((Object e) {
        appLog.fine('Physics send failed: $e');
      }),
    );
  }

  @override
  Stream<List<double>> get physics => _physics.stream;

  @override
  void broadcastEvent(GameEvent event) {
    if (_closed || !_isHost) return;
    unawaited(
      _session
          .sendUserMessage(eventMessageType, event.type, event.toJson())
          .catchError((Object e) {
            appLog.warning('Event send failed: $e');
          }),
    );
  }

  @override
  Stream<GameEvent> get events => _events.stream;

  @override
  Stream<SessionEnd> get ended => _ended.stream;

  @override
  Future<void> leave() async {
    if (_closed) return;
    _closed = true;
    await _setupSubscription?.cancel();
    _resendTimer?.cancel();
    _budgetReset?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await _session.dispose();
    } catch (e) {
      appLog.warning('Session teardown: $e');
    }
    await Future.wait([
      _actions.close(),
      _physics.close(),
      _events.close(),
      _ended.close(),
      _assignmentsChanged.close(),
      _readyChanged.close(),
    ]);
  }
}
