import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../pow.dart';
import '../protocol.dart';
import 'config.dart';
import 'matchmaker.dart';
import 'metered_web_socket.dart';
import 'rate_limiter.dart';
import 'pseudonymizer.dart';
import 'room.dart';
import 'signer.dart';
import 'turn.dart';

final _log = Logger('lobby');

/// Connection-level events, keyed by a pseudonymous client id (see
/// [IpPseudonymizer]) — never the address itself.
final _access = Logger('lobby.access');

/// The lobby: admission, matchmaking, and one signaling hub per match.
///
/// ```text
/// GET  /api/challenge   -> {challenge, difficulty}
/// POST /api/admit       {challenge, counter} -> {token}
/// WS   /api/lobby?token=...   quick match / private rooms (protocol.dart)
/// WS   /room/<id>       proxied to that match's hub
/// GET  /api/stats       -> {searching, playing}
/// GET  /health
/// ```
///
/// Nothing here is authenticated by a key in the app. A client earns a
/// short-lived session token with proof-of-work; a matched player receives
/// its room's secret; everything else is limits.
class LobbyServer {
  LobbyServer(this.config) : _signer = Signer(config.signingKey) {
    _matchmaker = Matchmaker(
      openRoom: _openRoom,
      credentialsFor: _credentialsFor,
      privateRoomTtl: config.privateRoomTtl,
    );
  }

  final LobbyConfig config;
  final Signer _signer;
  late final Matchmaker _matchmaker;
  final IpPseudonymizer _pseudonyms = IpPseudonymizer();

  final Map<String, Room> _rooms = {};

  /// Challenge ids already redeemed, until they would have expired anyway.
  final Map<String, DateTime> _usedChallenges = {};

  /// Session token ids already used to open a lobby socket. A token buys one
  /// connection: reusable, one proof-of-work paid for any number of sockets
  /// from any number of addresses for the token's whole lifetime.
  final Map<String, DateTime> _usedTokens = {};

  /// Rooms being opened, counted against [LobbyConfig.maxRooms] before they
  /// exist so concurrent opens cannot overshoot it.
  int _opening = 0;

  /// Open rooms per member address key, for [LobbyConfig.maxRoomsPerIp].
  final Map<String, int> _roomsByAddress = {};

  final RateLimiter _challengeLimit = RateLimiter(capacity: 10, perSecond: 0.5);
  final RateLimiter _admitLimit = RateLimiter(capacity: 10, perSecond: 0.5);
  final RateLimiter _socketLimit = RateLimiter(capacity: 20, perSecond: 1);

  /// Looser than the others: cheap to answer, and a classroom behind one
  /// address polls it from every open online menu.
  final RateLimiter _statsLimit = RateLimiter(capacity: 30, perSecond: 2);

  final Map<String, int> _lobbyConnectionsByIp = {};
  int _lobbyConnections = 0;

  HttpServer? _server;
  Timer? _janitor;

  int get port => _server!.port;
  int get roomCount => _rooms.length;
  int get lobbyConnectionCount => _lobbyConnections;
  Matchmaker get matchmaker => _matchmaker;

  static const _purposeChallenge = 'pow';
  static const _purposeSession = 'session';

  Future<void> start() async {
    final origins = config.allowedOrigins.map((o) => o.toLowerCase()).toSet();
    final router = Router()
      ..get('/health', (_) => Response.ok('ok'))
      ..get('/api/challenge', _challenge)
      ..get('/api/stats', _stats)
      ..post('/api/admit', _admit)
      ..get('/api/lobby', (Request request) => _lobbySocket(request, origins))
      ..get(
        '/room/<id>',
        (Request request, String id) => _roomSocket(request, id, origins),
      );

    final handler = const Pipeline()
        .addMiddleware(_originCheck(origins))
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, config.host, config.port);
    _server!.autoCompress = false;
    _janitor = Timer.periodic(const Duration(minutes: 1), (_) => _prune());
    _log.info('Lobby listening on ${config.host}:$port');
  }

  Future<void> stop() async {
    _janitor?.cancel();
    _matchmaker.dispose();
    for (final room in _rooms.values.toList()) {
      await room.close('shutdown');
    }
    await _server?.close(force: true);
  }

  // --- admission -----------------------------------------------------------

  /// What limits count a client by: its address, or for IPv6 its /64. One
  /// subscriber commonly holds a whole /64, so per-address IPv6 limits were
  /// no limits at all.
  static String addressKey(String ip) {
    final address = InternetAddress.tryParse(ip);
    if (address == null || address.type != InternetAddressType.IPv6) {
      return ip;
    }
    final raw = address.rawAddress;
    // An IPv4-mapped address is an IPv4 client.
    final mapped =
        raw.sublist(0, 10).every((b) => b == 0) &&
        raw[10] == 0xff &&
        raw[11] == 0xff;
    if (mapped) return raw.sublist(12).join('.');
    final prefix = [
      for (var i = 0; i < 8; i += 2)
        ((raw[i] << 8) | raw[i + 1]).toRadixString(16),
    ];
    return '${prefix.join(':')}::/64';
  }

  /// The limits key for [request]'s client; see [addressKey].
  String _clientKey(Request request) => addressKey(_clientIp(request));

  String _clientIp(Request request) {
    if (config.trustProxy) {
      final forwarded = request.headers['x-forwarded-for'];
      if (forwarded != null && forwarded.isNotEmpty) {
        // The proxy appends the address it saw, so the last entry is the
        // one it vouches for; earlier entries are client-supplied.
        return forwarded.split(',').last.trim();
      }
    }
    final info =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    return info?.remoteAddress.address ?? 'unknown';
  }

  Response _json(Object body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
  );

  /// The client's log id, from its address.
  String _clientId(Request request) => _pseudonyms.idFor(_clientIp(request));

  /// Player counts for the app's online menu. Counts only, nothing about
  /// who: no token needed, just a rate limit.
  Response _stats(Request request) {
    if (!_statsLimit.allow(_clientKey(request))) {
      return _json({'error': 'rate_limited'}, status: 429);
    }
    var playing = 0;
    for (final room in _rooms.values) {
      playing += room.playerCount;
    }
    return _json(
      LobbyStats(
        searching: _matchmaker.waitingCount,
        playing: playing,
      ).toJson(),
    );
  }

  Response _challenge(Request request) {
    if (!_challengeLimit.allow(_clientKey(request))) {
      _access.info('${_clientId(request)} challenge rate-limited');
      return _json({'error': 'rate_limited'}, status: 429);
    }
    return _json({
      'challenge': _signer.sign(_purposeChallenge, config.challengeTtl),
      'difficulty': config.powDifficulty,
    });
  }

  Future<Response> _admit(Request request) async {
    final client = _clientId(request);
    if (!_admitLimit.allow(_clientKey(request))) {
      _access.info('$client admit rate-limited');
      return _json({'error': 'rate_limited'}, status: 429);
    }
    final body = await _readLimited(request, 1024);
    if (body == null) return _json({'error': 'bad_request'}, status: 400);
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return _json({'error': 'bad_request'}, status: 400);
    }
    if (json is! Map<String, dynamic>) {
      return _json({'error': 'bad_request'}, status: 400);
    }
    final challenge = json['challenge'];
    final counter = json['counter'];
    if (challenge is! String || counter is! int) {
      return _json({'error': 'bad_request'}, status: 400);
    }
    final id = _signer.verify(challenge, _purposeChallenge);
    if (id == null || _usedChallenges.containsKey(id)) {
      _access.info('$client admit refused: invalid or reused challenge');
      return _json({'error': 'invalid_challenge'}, status: 403);
    }
    if (!checkSolution(challenge, counter, config.powDifficulty)) {
      _access.info('$client admit refused: wrong solution');
      return _json({'error': 'invalid_solution'}, status: 403);
    }
    _access.info('$client admitted');
    // Single use: a solved challenge buys exactly one session.
    _usedChallenges[id] = DateTime.now().add(config.challengeTtl);
    return _json({
      'token': _signer.sign(_purposeSession, config.sessionTokenTtl),
    });
  }

  static Future<String?> _readLimited(Request request, int limit) async {
    final declared = request.contentLength;
    if (declared != null && declared > limit) return null;
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > limit) return null;
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Browsers always send Origin; refuse the ones not on the list. Native
  /// clients send none and are unaffected. Allowed origins get CORS headers,
  /// so a web build served elsewhere (development) can call the API.
  Middleware _originCheck(Set<String> origins) =>
      (inner) => (request) async {
        final origin = request.headers['origin']?.toLowerCase();
        if (origin != null && !origins.contains(origin)) {
          return Response.forbidden('origin not allowed');
        }
        final cors = origin == null
            ? const <String, String>{}
            : {
                'access-control-allow-origin': origin,
                'access-control-allow-methods': 'GET, POST',
                'access-control-allow-headers': 'content-type',
                'vary': 'origin',
              };
        if (request.method == 'OPTIONS') {
          return Response.ok(null, headers: cors);
        }
        final response = await inner(request);
        return response.change(headers: cors);
      };

  // --- lobby socket --------------------------------------------------------

  FutureOr<Response> _lobbySocket(Request request, Set<String> origins) {
    final ip = _clientKey(request);
    final client = _clientId(request);
    if (!_socketLimit.allow(ip)) {
      _access.info('$client lobby rate-limited');
      return _json({'error': 'rate_limited'}, status: 429);
    }
    final token = request.url.queryParameters['token'];
    final tokenId = token == null
        ? null
        : _signer.verify(token, _purposeSession);
    if (tokenId == null || _usedTokens.containsKey(tokenId)) {
      _access.info('$client lobby refused: bad or reused token');
      return _json({'error': 'unauthorized'}, status: 401);
    }
    if (_lobbyConnections >= config.maxLobbyConnections ||
        (_lobbyConnectionsByIp[ip] ?? 0) >= config.maxConnectionsPerIp) {
      _access.info('$client lobby refused: at capacity');
      return _json({'error': 'busy'}, status: 503);
    }
    _usedTokens[tokenId] = DateTime.now().add(config.sessionTokenTtl);
    return meteredWebSocketHandler(
      (WebSocketChannel socket) {
        _lobbyConnections++;
        _lobbyConnectionsByIp[ip] = (_lobbyConnectionsByIp[ip] ?? 0) + 1;
        _access.info('$client lobby connected');
        _LobbyConnection(
          socket,
          _matchmaker,
          client: client,
          addressKey: ip,
          onClosed: () {
            _access.info('$client lobby disconnected');
            _lobbyConnections--;
            final left = (_lobbyConnectionsByIp[ip] ?? 1) - 1;
            if (left <= 0) {
              _lobbyConnectionsByIp.remove(ip);
            } else {
              _lobbyConnectionsByIp[ip] = left;
            }
          },
        );
      },
      allowedOrigins: origins,
      pingInterval: const Duration(seconds: 20),
      // Lobby traffic is a few small JSON messages a minute.
      budget: () => ByteBudget(capacity: 16 * 1024, perSecond: 256),
      maxFrameBytes: 16 * 1024,
    )(request);
  }

  // --- rooms ---------------------------------------------------------------

  Future<Room?> _openRoom(
    LobbyMode mode,
    int players,
    List<LobbyPeer> members,
  ) async {
    if (_rooms.length + _opening >= config.maxRooms) return null;
    final addresses = {for (final m in members) m.addressKey};
    if (addresses.any(
      (a) => (_roomsByAddress[a] ?? 0) >= config.maxRoomsPerIp,
    )) {
      _access.info(
        'Room refused for ${members.map((m) => m.client).join(', ')}: '
        'an address is in too many rooms',
      );
      return null;
    }
    for (final a in addresses) {
      _roomsByAddress[a] = (_roomsByAddress[a] ?? 0) + 1;
    }
    void release() {
      for (final a in addresses) {
        final left = (_roomsByAddress[a] ?? 1) - 1;
        if (left <= 0) {
          _roomsByAddress.remove(a);
        } else {
          _roomsByAddress[a] = left;
        }
      }
    }

    _opening++;
    try {
      final room = await Room.open(
        id: _signer.randomHex(16),
        secret: _signer.randomBase64(32),
        mode: mode,
        players: players,
        ttl: config.roomTtl,
        onClosed: (room) {
          _rooms.remove(room.id);
          release();
        },
      );
      _rooms[room.id] = room;
      return room;
    } catch (_) {
      release();
      rethrow;
    } finally {
      _opening--;
    }
  }

  MatchFound _credentialsFor(
    Room room, {
    required bool host,
    required bool custom,
  }) {
    final ice = <IceServer>[
      if (config.stunUrls.isNotEmpty) IceServer(urls: config.stunUrls),
      if (config.turnUrls.isNotEmpty)
        () {
          final creds = turnCredentials(
            secret: config.turnSecret!,
            // Per player, not per room: coturn's user-quota counts
            // allocations per username, and a whole room sharing one ran out
            // of allocations before every relayed connection was up.
            label: '${room.id}.${_signer.randomHex(4)}',
            ttl: config.turnCredentialTtl > config.roomTtl
                ? config.turnCredentialTtl
                : config.roomTtl,
          );
          return IceServer(
            urls: config.turnUrls,
            username: creds.username,
            credential: creds.credential,
          );
        }(),
    ];
    return MatchFound(
      room: room.id,
      secret: room.secret,
      host: host,
      mode: room.mode,
      players: room.players,
      iceServers: ice,
      custom: custom,
    );
  }

  FutureOr<Response> _roomSocket(
    Request request,
    String id,
    Set<String> origins,
  ) {
    final client = _clientId(request);
    if (!_socketLimit.allow(_clientKey(request))) {
      _access.info('$client room rate-limited');
      return _json({'error': 'rate_limited'}, status: 429);
    }
    final room = _rooms[id];
    if (room == null || room.isClosed) {
      _access.info('$client room refused: unknown room');
      return Response.notFound('no room');
    }
    return meteredWebSocketHandler(
      (WebSocketChannel socket) {
        _access.info('$client joined room ${room.id}');
        unawaited(room.attach(socket));
      },
      allowedOrigins: origins,
      // Without it a half-open connection held its room until the TTL.
      pingInterval: const Duration(seconds: 20),
      // Discovery and WebRTC signalling: SDP and ICE candidates, then
      // heartbeats. Game data goes peer to peer, never through here.
      budget: () => ByteBudget(capacity: 256 * 1024, perSecond: 32 * 1024),
      maxFrameBytes: 64 * 1024,
    )(request);
  }

  void _prune() {
    final now = DateTime.now();
    _usedChallenges.removeWhere((_, expires) => now.isAfter(expires));
    _usedTokens.removeWhere((_, expires) => now.isAfter(expires));
    _challengeLimit.prune();
    _admitLimit.prune();
    _socketLimit.prune();
    _statsLimit.prune();
  }
}

/// One lobby WebSocket. Everything it receives is untrusted.
class _LobbyConnection implements LobbyPeer {
  _LobbyConnection(
    this._socket,
    this._matchmaker, {
    required this.client,
    required this.addressKey,
    required this.onClosed,
  }) {
    _subscription = _socket.stream.listen(
      _onMessage,
      onDone: _onDone,
      onError: (_) => _onDone(),
      cancelOnError: true,
    );
    // Nobody waits in a lobby forever.
    _lifetime = Timer(const Duration(minutes: 20), close);
  }

  final WebSocketChannel _socket;
  final Matchmaker _matchmaker;

  /// Pseudonymous id, for logs only.
  @override
  final String client;
  @override
  final String addressKey;
  final void Function() onClosed;
  late final StreamSubscription<Object?> _subscription;
  late final Timer _lifetime;
  final RateLimiter _messages = RateLimiter(capacity: 5, perSecond: 0.2);
  bool _closed = false;

  void _onMessage(Object? data) {
    if (data is! String || data.length > maxLobbyMessageLength) {
      send(const LobbyError(LobbyErrorCode.badRequest));
      unawaited(close());
      return;
    }
    if (!_messages.allow('')) {
      send(const LobbyError(LobbyErrorCode.rateLimited));
      unawaited(close());
      return;
    }
    Object? json;
    try {
      json = jsonDecode(data);
    } on FormatException {
      json = null;
    }
    final message = ClientMessage.fromJson(json);
    if (message == null) {
      send(const LobbyError(LobbyErrorCode.badRequest));
      return;
    }
    unawaited(_matchmaker.handle(this, message));
  }

  @override
  void send(ServerMessage message) {
    if (_closed) return;
    _socket.sink.add(jsonEncode(message.toJson()));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    // Released first: until the sink finished closing this connection still
    // handled messages (and could join a queue), and a second close() raced
    // the first through the same await.
    _onDone();
    await _socket.sink.close();
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    _lifetime.cancel();
    unawaited(_subscription.cancel());
    _matchmaker.remove(this);
    onClosed();
  }
}
