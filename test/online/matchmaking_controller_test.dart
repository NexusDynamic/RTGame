import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/peer_game_session.dart';
import 'package:rise_together_game/src/online/lobby_client.dart';
import 'package:rise_together_game/src/online/matchmaking_controller.dart';
import 'package:rise_together_lobby/lobby.dart';
import 'package:rise_together_lobby/protocol.dart';
import 'package:webrtc_coordinator/testing.dart';

import '../helpers/test_helpers.dart';

/// The whole online path the app takes: proof-of-work admission, the lobby,
/// the per-match hub behind it, and a peer-to-peer [GameSession] — with a
/// real lobby server in-process and the fake WebRTC adapter.
void main() {
  setUpAll(silenceLogs);

  late LobbyServer server;
  late FakeRtcBus bus;
  final controllers = <MatchmakingController>[];
  final sessions = <GameSession>[];

  Future<void> startServer({int difficulty = 6}) async {
    server = LobbyServer(
      LobbyConfig(
        signingKey: 'test-signing-key-that-is-long-enough',
        host: '127.0.0.1',
        port: 0,
        powDifficulty: difficulty,
      ),
    );
    await server.start();
  }

  setUp(() => bus = FakeRtcBus());

  tearDown(() async {
    for (final c in controllers) {
      await c.cancel();
    }
    controllers.clear();
    for (final s in sessions) {
      await s.leave();
    }
    sessions.clear();
    await server.stop();
  });

  const timings = SessionTimings(
    heartbeatInterval: Duration(milliseconds: 100),
    discoveryInterval: Duration(milliseconds: 50),
    nodeTimeout: Duration(milliseconds: 800),
    hostJoinWindow: Duration(milliseconds: 1500),
    joinAttemptWindow: Duration(seconds: 3),
    joinRetryDelay: Duration(milliseconds: 100),
  );

  MatchmakingController controller({Uri? lobbyUrl}) {
    final c = MatchmakingController(
      lobby: LobbyClient(
        lobbyUrl ?? Uri.parse('http://127.0.0.1:${server.port}'),
      ),
      adapterFactory: (self) => FakeRtcPeerAdapter(selfKey: self, bus: bus),
      timings: timings,
    );
    controllers.add(c);
    return c;
  }

  Future<MatchmakingState> run(
    MatchmakingController c,
    ClientMessage request,
  ) async {
    await c.start(
      request: request,
      nickname: 'player',
      roundDurationSeconds: 90,
    );
    final state = c.state;
    if (state is MatchReady) sessions.add(state.session);
    return state;
  }

  /// Resolves once [c] reaches a state matching [test].
  Future<T> reach<T extends MatchmakingState>(MatchmakingController c) {
    if (c.state is T) return Future.value(c.state as T);
    final done = Completer<T>();
    void listener() {
      if (c.state is T && !done.isCompleted) done.complete(c.state as T);
    }

    c.addListener(listener);
    return done.future
        .timeout(const Duration(seconds: 10))
        .whenComplete(() => c.removeListener(listener));
  }

  test('quick match ends with two connected players and one host', () async {
    await startServer();
    const request = QuickMatch(mode: LobbyMode.versus, players: 2);
    final results = await Future.wait([
      run(controller(), request),
      run(controller(), request),
    ]);

    expect(results, everyElement(isA<MatchReady>()));
    final a = (results[0] as MatchReady).session;
    final b = (results[1] as MatchReady).session;
    expect([a.isAuthority, b.isAuthority], unorderedEquals([true, false]));
    expect(a.rules.seed, b.rules.seed);
    expect(a.rules.mode, MatchMode.versus);
    expect(a.rules.roundDurationSeconds, 90);
    expect(a.localAssignment.teamId, isNot(b.localAssignment.teamId));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a private room fills by code, and its creator hosts', () async {
    await startServer();
    final creator = controller();
    final created = run(
      creator,
      const CreateRoom(mode: LobbyMode.coop, players: 2),
    );
    final code = (await reach<Gathering>(creator).then((_) async {
      // The first Gathering is local; wait for the lobby's, with the code.
      while ((creator.state as Gathering).code == null) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return creator.state as Gathering;
    })).code!;

    final joined = await run(controller(), JoinRoom(code: code));
    final hostState = await created;

    expect(hostState, isA<MatchReady>());
    expect(joined, isA<MatchReady>());
    expect((hostState as MatchReady).session.isAuthority, isTrue);
    expect((joined as MatchReady).session.rules.mode, MatchMode.coop);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('an unknown room code is reported', () async {
    await startServer();
    final state = await run(controller(), const JoinRoom(code: 'ZZZZZZ'));
    expect(
      (state as MatchmakingFailed).reason,
      MatchmakingFailure.roomNotFound,
    );
  });

  test('an unreachable lobby is reported, not thrown', () async {
    await startServer();
    final state = await run(
      controller(lobbyUrl: Uri.parse('http://127.0.0.1:1')),
      const QuickMatch(mode: LobbyMode.coop, players: 2),
    );
    expect((state as MatchmakingFailed).reason, MatchmakingFailure.unreachable);
  });

  test('a lobby demanding absurd proof-of-work is refused', () async {
    await startServer(difficulty: LobbyClient.maxDifficulty + 1);
    final state = await run(
      controller(),
      const QuickMatch(mode: LobbyMode.coop, players: 2),
    );
    expect(
      (state as MatchmakingFailed).reason,
      MatchmakingFailure.invalidResponse,
    );
  });

  test('cancelling while waiting leaves the lobby', () async {
    await startServer();
    final c = controller();
    unawaited(run(c, const QuickMatch(mode: LobbyMode.versus, players: 2)));
    await reach<Gathering>(c);
    // Let the lobby register us before cancelling.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.matchmaker.waitingCount, 1);
    await c.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.matchmaker.waitingCount, 0);
  });
}
