import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peer_coordinator/testing.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/peer_game_session.dart';
import 'package:webrtc_coordinator/testing.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

import '../helpers/test_helpers.dart';

/// [PeerGameSession] over the real WebRTC transport, with a real hub and the
/// in-process fake RTC adapter. This is the path production takes, including
/// how the transport attributes each sample to its sender.
void main() {
  late TestHub hub;
  late FakeRtcBus bus;
  late List<PeerGameSession> sessions;
  var run = 0;

  setUpAll(silenceLogs);

  setUp(() async {
    hub = await startTestHub();
    bus = FakeRtcBus();
    sessions = [];
  });

  tearDown(() async {
    for (final s in sessions) {
      await s.leave();
    }
    await hub.close();
  });

  const timings = SessionTimings(
    heartbeatInterval: Duration(milliseconds: 100),
    discoveryInterval: Duration(milliseconds: 50),
    nodeTimeout: Duration(milliseconds: 800),
    // Over the second the library reserves: see SessionTimings.
    hostJoinWindow: Duration(milliseconds: 1500),
    // Outlasts the ten-discovery-interval (500 ms) search for the host.
    joinAttemptWindow: Duration(seconds: 3),
    joinRetryDelay: Duration(milliseconds: 100),
  );

  RtcTransportConfig transport() => RtcTransportConfig(
    hubUri: hub.uri,
    credentials: hub.credentials,
    adapterFactory: (self) => FakeRtcPeerAdapter(selfKey: self, bus: bus),
    dataOrdered: false,
    dataMaxRetransmits: 1,
  );

  Future<PeerGameSession> connect(
    String room, {
    required bool host,
    int playerCount = 2,
    String nickname = 'p',
  }) async {
    final session = await PeerGameSession.connect(
      transport: transport(),
      roomName: room,
      nickname: nickname,
      playerCount: playerCount,
      host: host,
      timeout: const Duration(seconds: 10),
      timings: timings,
    );
    sessions.add(session);
    return session;
  }

  /// Join [count] players into one room. The first to join hosts.
  Future<(PeerGameSession, List<PeerGameSession>)> startMatch(
    int count, {
    MatchMode mode = MatchMode.versus,
    List<String>? nicknames,
  }) async {
    final room = 'room-${run++}';
    // Everyone connects at once: roles, not arrival order, decide the host.
    final all = await Future.wait([
      for (var i = 0; i < count; i++)
        connect(
          room,
          host: i == 0,
          playerCount: count,
          nickname: nicknames?[i] ?? 'p$i',
        ),
    ]);
    expect(all.first.isAuthority, isTrue);

    await Future.wait([
      for (final s in all)
        s.startMatch(
          hostRules: MatchRules(
            mode: mode,
            roundDurationSeconds: 60,
            seed: 1234,
          ),
          timeout: const Duration(seconds: 10),
        ),
    ]);
    return (all.first, all.skip(1).toList());
  }

  test('everyone agrees on rules and roster; versus splits teams', () async {
    final (host, followers) = await startMatch(3);

    expect(followers, hasLength(2));
    for (final s in [host, ...followers]) {
      expect(s.rules.seed, 1234);
      expect(s.rules.mode, MatchMode.versus);
      expect(
        s.assignments.map((a) => a.nodeId).toList(),
        host.assignments.map((a) => a.nodeId).toList(),
      );
    }
    expect(host.assignments.map((a) => a.teamId), [0, 1, 0]);
    expect(
      host.assignments.where((a) => a.isCoordinator).single.nodeId,
      host.localAssignment.nodeId,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('co-op puts everyone on one team', () async {
    final (host, _) = await startMatch(2, mode: MatchMode.coop);
    expect(host.assignments.map((a) => a.teamId), [0, 0]);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'a follower\'s input reaches the host attributed to that follower',
    () async {
      final (host, followers) = await startMatch(2);
      final follower = followers.single;

      final received = host.actions.firstWhere(
        (a) => a.action == PaddleAction.left,
      );
      follower.sendAction(PaddleAction.left);
      final action = await received.timeout(const Duration(seconds: 5));

      expect(action.playerId, follower.localAssignment.playerId);
      expect(action.teamId, follower.localAssignment.teamId);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('held input is re-sent, so a lost packet cannot stick', () async {
    final (host, followers) = await startMatch(2);
    final seen = <PaddleAction>[];
    final sub = host.actions.listen((a) => seen.add(a.action));
    addTearDown(sub.cancel);

    followers.single.sendAction(PaddleAction.right);
    await Future<void>.delayed(PeerGameSession.inputResendInterval * 4);

    expect(
      seen.where((a) => a == PaddleAction.right).length,
      greaterThanOrEqualTo(3),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('the host\'s own input is attributed to the host', () async {
    final (host, _) = await startMatch(2);
    final received = host.actions.first;
    host.sendAction(PaddleAction.right);
    final action = await received;
    expect(action.playerId, host.localAssignment.playerId);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('physics and events reach followers', () async {
    final (host, followers) = await startMatch(2);
    final follower = followers.single;

    final physics = follower.physics.first;
    final event = follower.events.first;
    final sample = List<double>.generate(16, (i) => i * 0.5);
    // Samples are lossy by design; keep sending until one lands.
    final pump = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => host.broadcastPhysics(sample),
    );
    addTearDown(pump.cancel);
    host.broadcastEvent(
      const TeamLevelProgression(teamId: 1, levelIndex: 2, seed: 99),
    );

    expect(await physics.timeout(const Duration(seconds: 5)), sample);
    final decoded = await event.timeout(const Duration(seconds: 5));
    expect(decoded, isA<TeamLevelProgression>());
    expect((decoded as TeamLevelProgression).levelIndex, 2);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('hostile nicknames are cleaned before anyone displays them', () async {
    final (host, followers) = await startMatch(
      2,
      nicknames: ['host', 'bad\u0000name${'x' * 100}'],
    );
    final name = host.assignments
        .singleWhere((a) => a.nodeId == followers.single.localAssignment.nodeId)
        .nodeName;
    expect(name.contains('\u0000'), isFalse);
    expect(name.length, lessThanOrEqualTo(PeerGameSession.maxNicknameLength));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('the host waits until every follower is ready', () async {
    final (host, followers) = await startMatch(3);
    expect(
      await host.waitForPlayersReady(const Duration(milliseconds: 300)),
      isFalse,
    );
    for (final f in followers) {
      await f.markReady();
    }
    expect(await host.waitForPlayersReady(const Duration(seconds: 5)), isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('readiness is per round, so a rematch waits again', () async {
    final (host, followers) = await startMatch(2);
    await followers.single.markReady();
    expect(await host.waitForPlayersReady(const Duration(seconds: 5)), isTrue);

    // Round 0's readiness must not count for round 1.
    expect(
      await host.waitForPlayersReady(
        const Duration(milliseconds: 300),
        round: 1,
      ),
      isFalse,
    );
    await followers.single.markReady(round: 1);
    expect(
      await host.waitForPlayersReady(const Duration(seconds: 5), round: 1),
      isTrue,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a rematch reaches followers', () async {
    final (host, followers) = await startMatch(2);
    final rematch = followers.single.events.firstWhere((e) => e is Rematch);
    host.broadcastEvent(const Rematch(round: 1, seed: 42));
    final event = await rematch.timeout(const Duration(seconds: 5)) as Rematch;
    expect(event.round, 1);
    expect(event.seed, 42);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a joiner who arrives before the host waits for it', () async {
    final room = 'room-${run++}';
    final joiner = connect(room, host: false);
    await Future<void>.delayed(const Duration(seconds: 1));
    final host = await connect(room, host: true);
    final guest = await joiner;
    expect(host.isAuthority, isTrue);
    expect(guest.isAuthority, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a second host in the same room is refused', () async {
    final room = 'room-${run++}';
    await connect(room, host: true);
    await expectLater(connect(room, host: true), throwsStateError);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('followers are told when the host leaves', () async {
    final (host, followers) = await startMatch(2);
    final ended = followers.single.ended.first;
    await host.leave();
    expect(
      await ended.timeout(const Duration(seconds: 5)),
      SessionEnd.hostLeft,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
