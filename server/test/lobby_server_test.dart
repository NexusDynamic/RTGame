import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart' show StreamQueue;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/websocket.dart' show HubCredentials;
import 'package:rise_together_lobby/lobby.dart';
import 'package:rise_together_lobby/pow.dart';
import 'package:rise_together_lobby/protocol.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:webrtc_coordinator/testing.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

void main() {
  Logger.root.level = Level.OFF;

  late LobbyServer server;
  late Uri base;

  Future<void> startServer({
    List<String> origins = const ['https://play.example'],
    int maxRooms = 10,
    List<String> turnUrls = const [],
  }) async {
    server = LobbyServer(
      LobbyConfig(
        signingKey: 'test-signing-key-that-is-long-enough',
        host: '127.0.0.1',
        port: 0,
        allowedOrigins: origins,
        powDifficulty: 6,
        maxRooms: maxRooms,
        turnUrls: turnUrls,
        turnSecret: turnUrls.isEmpty ? null : 'turn-secret',
        stunUrls: const ['stun:stun.example:3478'],
      ),
    );
    await server.start();
    base = Uri.parse('http://127.0.0.1:${server.port}');
  }

  tearDown(() => server.stop());

  Future<String> admit() async {
    final challenge =
        jsonDecode((await http.get(base.resolve('/api/challenge'))).body)
            as Map<String, dynamic>;
    final counter = await solve(
      challenge['challenge'] as String,
      challenge['difficulty'] as int,
    );
    final response = await http.post(
      base.resolve('/api/admit'),
      body: jsonEncode({
        'challenge': challenge['challenge'],
        'counter': counter,
      }),
    );
    expect(response.statusCode, 200, reason: response.body);
    return (jsonDecode(response.body) as Map<String, dynamic>)['token']
        as String;
  }

  /// A lobby client that records every message it receives.
  Future<(WebSocketChannel, StreamQueue<ServerMessage>)> lobby() async {
    final token = await admit();
    final socket = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/api/lobby?token=$token'),
    );
    await socket.ready;
    final messages = StreamQueue(
      socket.stream.map(
        (m) => ServerMessage.fromJson(jsonDecode(m as String))!,
      ),
    );
    return (socket, messages);
  }

  void send(WebSocketChannel socket, ClientMessage message) =>
      socket.sink.add(jsonEncode(message.toJson()));

  Future<T> next<T extends ServerMessage>(StreamQueue<ServerMessage> q) async {
    while (true) {
      final m = await q.next.timeout(const Duration(seconds: 5));
      if (m is T) return m;
    }
  }

  group('admission', () {
    setUp(startServer);

    test('proof of work buys a session token', () async {
      expect(await admit(), isNotEmpty);
    });

    test('a challenge can be redeemed once', () async {
      final c =
          jsonDecode((await http.get(base.resolve('/api/challenge'))).body)
              as Map<String, dynamic>;
      final counter = await solve(c['challenge'] as String, 6);
      final body = jsonEncode({
        'challenge': c['challenge'],
        'counter': counter,
      });
      expect(
        (await http.post(base.resolve('/api/admit'), body: body)).statusCode,
        200,
      );
      expect(
        (await http.post(base.resolve('/api/admit'), body: body)).statusCode,
        403,
      );
    });

    test('a wrong solution or forged challenge is refused', () async {
      final c =
          jsonDecode((await http.get(base.resolve('/api/challenge'))).body)
              as Map<String, dynamic>;
      var wrong = 0;
      while (checkSolution(c['challenge'] as String, wrong, 6)) {
        wrong++;
      }
      for (final body in [
        {'challenge': c['challenge'], 'counter': wrong},
        {'challenge': 'forged.token', 'counter': 0},
        {'challenge': c['challenge']},
      ]) {
        final r = await http.post(
          base.resolve('/api/admit'),
          body: jsonEncode(body),
        );
        expect(r.statusCode, anyOf(400, 403), reason: '$body');
      }
      final huge = await http.post(
        base.resolve('/api/admit'),
        body: 'x' * 5000,
      );
      expect(huge.statusCode, 400);
    });

    test('the lobby needs a valid token', () async {
      for (final token in ['', 'nope']) {
        final r = await http.get(base.resolve('/api/lobby?token=$token'));
        expect(r.statusCode, 401);
      }
    });

    test('browsers from unlisted origins are refused', () async {
      final bad = await http.get(
        base.resolve('/api/challenge'),
        headers: {'origin': 'https://evil.example'},
      );
      expect(bad.statusCode, 403);
      final good = await http.get(
        base.resolve('/api/challenge'),
        headers: {'origin': 'https://play.example'},
      );
      expect(good.statusCode, 200);
      expect(
        good.headers['access-control-allow-origin'],
        'https://play.example',
      );
    });

    test('challenges are rate limited per address', () async {
      final codes = [
        for (var i = 0; i < 15; i++)
          (await http.get(base.resolve('/api/challenge'))).statusCode,
      ];
      expect(codes, contains(429));
    });
  });

  group('matchmaking', () {
    setUp(() => startServer(turnUrls: const ['turn:turn.example:3478']));

    test('quick match pairs two players with one host', () async {
      final (a, qa) = await lobby();
      final (b, qb) = await lobby();
      send(a, const QuickMatch(mode: LobbyMode.versus, players: 2));
      expect((await next<Waiting>(qa)).joined, 1);
      send(b, const QuickMatch(mode: LobbyMode.versus, players: 2));
      final ma = await next<MatchFound>(qa);
      final mb = await next<MatchFound>(qb);

      expect(ma.room, mb.room);
      expect(ma.secret, mb.secret);
      expect([ma.host, mb.host], [true, false]);
      expect(server.roomCount, 1);
      // Short-lived TURN credentials, and STUN.
      final turn = ma.iceServers.singleWhere((s) => s.username != null);
      expect(turn.username, endsWith(':${ma.room}'));
      expect(
        ma.iceServers.any((s) => s.urls.first.startsWith('stun:')),
        isTrue,
      );
    });

    test('different sizes and modes do not mix', () async {
      final (a, qa) = await lobby();
      final (b, qb) = await lobby();
      send(a, const QuickMatch(mode: LobbyMode.versus, players: 2));
      send(b, const QuickMatch(mode: LobbyMode.coop, players: 2));
      expect((await next<Waiting>(qa)).joined, 1);
      expect((await next<Waiting>(qb)).joined, 1);
      expect(server.roomCount, 0);
    });

    test('custom-level players have their own queue', () async {
      final (a, qa) = await lobby();
      final (b, qb) = await lobby();
      final (c, qc) = await lobby();
      send(a, const QuickMatch(mode: LobbyMode.coop, players: 2));
      send(b, const QuickMatch(mode: LobbyMode.coop, players: 2, custom: true));
      expect((await next<Waiting>(qa)).custom, isFalse);
      expect((await next<Waiting>(qb)).custom, isTrue);
      expect(server.roomCount, 0);

      send(c, const QuickMatch(mode: LobbyMode.coop, players: 2, custom: true));
      final mb = await next<MatchFound>(qb);
      final mc = await next<MatchFound>(qc);
      expect([mb.custom, mc.custom], [true, true]);
      expect(mb.room, mc.room);
      expect(server.matchmaker.waitingCount, 1);
    });

    test('joiners learn a private room is custom before it starts', () async {
      final (a, qa) = await lobby();
      final (b, qb) = await lobby();
      send(a, const CreateRoom(mode: LobbyMode.coop, players: 3, custom: true));
      final created = await next<Waiting>(qa);
      expect(created.custom, isTrue);

      send(b, JoinRoom(code: created.code!));
      final joined = await next<Waiting>(qb);
      expect(joined.custom, isTrue);
      expect(joined.joined, 2);
    });

    test('private rooms fill by code, and the creator hosts', () async {
      final (a, qa) = await lobby();
      final (b, qb) = await lobby();
      send(a, const CreateRoom(mode: LobbyMode.coop, players: 2));
      final code = (await next<Waiting>(qa)).code!;
      expect(isValidRoomCode(code), isTrue);

      send(b, JoinRoom(code: code));
      expect((await next<MatchFound>(qa)).host, isTrue);
      expect((await next<MatchFound>(qb)).host, isFalse);
    });

    test('unknown codes and a departed creator are reported', () async {
      final (a, qa) = await lobby();
      final (b, qb) = await lobby();
      send(b, const JoinRoom(code: 'ZZZZZZ'));
      expect((await next<LobbyError>(qb)).code, LobbyErrorCode.roomNotFound);

      send(a, const CreateRoom(mode: LobbyMode.versus, players: 3));
      final code = (await next<Waiting>(qa)).code!;
      final (c, qc) = await lobby();
      send(c, JoinRoom(code: code));
      await next<Waiting>(qc);
      await a.sink.close();
      expect((await next<LobbyError>(qc)).code, LobbyErrorCode.hostLeft);
    });

    test('garbage on the lobby socket is answered, not obeyed', () async {
      final (a, qa) = await lobby();
      a.sink.add('{"t":"quick","mode":"versus","players":1000}');
      expect((await next<LobbyError>(qa)).code, LobbyErrorCode.badRequest);
      expect(server.matchmaker.waitingCount, 0);
    });
  });

  test('logs never contain the client address', () async {
    // The server binds 127.0.0.1 and says so at startup; capture only what
    // client activity logs, where the same address would be the client's.
    await startServer();
    final lines = <String>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen((r) => lines.add(r.message));
    addTearDown(() {
      sub.cancel();
      Logger.root.level = Level.OFF;
    });

    final (a, qa) = await lobby();
    final (b, qb) = await lobby();
    send(a, const QuickMatch(mode: LobbyMode.coop, players: 2));
    send(b, const QuickMatch(mode: LobbyMode.coop, players: 2));
    await next<MatchFound>(qa);
    await next<MatchFound>(qb);
    await http.get(base.resolve('/api/lobby?token=bad'));

    expect(lines.where((l) => l.contains('admitted')), isNotEmpty);
    expect(lines.where((l) => l.contains('127.0.0.1')), isEmpty);
  });

  test('a full server says busy instead of opening a room', () async {
    await startServer(maxRooms: 0);
    final (a, qa) = await lobby();
    final (b, qb) = await lobby();
    send(a, const QuickMatch(mode: LobbyMode.coop, players: 2));
    send(b, const QuickMatch(mode: LobbyMode.coop, players: 2));
    expect((await next<LobbyError>(qa)).code, LobbyErrorCode.busy);
    expect((await next<LobbyError>(qb)).code, LobbyErrorCode.busy);
  });

  test('matched players connect peer to peer through the room hub', () async {
    await startServer();
    final (a, qa) = await lobby();
    final (b, qb) = await lobby();
    send(a, const QuickMatch(mode: LobbyMode.versus, players: 2));
    send(b, const QuickMatch(mode: LobbyMode.versus, players: 2));
    final matches = [await next<MatchFound>(qa), await next<MatchFound>(qb)];

    final bus = FakeRtcBus();
    final sessions = <PeerSession>[];
    addTearDown(() async {
      for (final s in sessions) {
        await s.dispose();
      }
    });
    Future<PeerSession> join(MatchFound match) async {
      final session = PeerSession.create(
        CoordinationConfig(
          name: 'lobby_e2e',
          sessionConfig: CoordinationSessionConfig(
            name: match.room,
            maxNodes: 2,
            heartbeatInterval: const Duration(milliseconds: 100),
            discoveryInterval: const Duration(milliseconds: 50),
            nodeTimeout: const Duration(milliseconds: 800),
          ),
          topologyConfig: HierarchicalTopologyConfig(
            promotionStrategy: PromotionStrategyRandom(),
            maxNodes: 2,
          ),
          transportConfig: RtcTransportConfig(
            hubUri: base.replace(scheme: 'ws', path: match.path),
            credentials: HubCredentials(
              session: match.room,
              secret: match.secret,
            ),
            adapterFactory: (self) =>
                FakeRtcPeerAdapter(selfKey: self, bus: bus),
          ),
        ),
        thisNodeConfig: NodeConfig(
          name: match.host ? 'host' : 'guest',
          id: match.host ? 'host' : 'guest',
          capabilities: match.host
              ? {NodeCapability.coordinator, NodeCapability.participant}
              : {NodeCapability.participant},
          metadata: {PeerMetadataKeys.randomRoll: match.host ? '0' : '1'},
        ),
      );
      sessions.add(session);
      await session.initialize();
      await session.join(const Duration(seconds: 3));
      return session;
    }

    final host = await join(matches.firstWhere((m) => m.host));
    final guest = await join(matches.firstWhere((m) => !m.host));
    await host.waitForMinNodes(2, timeout: const Duration(seconds: 5));
    expect(host.isCoordinator, isTrue);
    expect(guest.coordinatorUId, host.thisNode.uId);
  });

  test('a room hub refuses the wrong secret', () async {
    await startServer();
    final (a, qa) = await lobby();
    final (b, qb) = await lobby();
    send(a, const QuickMatch(mode: LobbyMode.coop, players: 2));
    send(b, const QuickMatch(mode: LobbyMode.coop, players: 2));
    final match = await next<MatchFound>(qa);
    await next<MatchFound>(qb);

    final intruder = PeerSession.create(
      CoordinationConfig(
        name: 'intruder',
        sessionConfig: CoordinationSessionConfig(name: match.room),
        transportConfig: RtcTransportConfig(
          hubUri: base.replace(scheme: 'ws', path: match.path),
          credentials: HubCredentials(session: match.room, secret: 'guess'),
          adapterFactory: (self) =>
              FakeRtcPeerAdapter(selfKey: self, bus: FakeRtcBus()),
        ),
      ),
      thisNodeConfig: NodeConfig(name: 'x', id: 'x'),
    );
    addTearDown(() => intruder.dispose().catchError((_) {}));
    await expectLater(intruder.initialize(), throwsA(anything));
  });
}
