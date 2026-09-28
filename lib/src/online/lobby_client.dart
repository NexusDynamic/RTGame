import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rise_together_lobby/pow.dart' as pow;
import 'package:rise_together_lobby/protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Why talking to the lobby failed, as something the UI can explain.
enum LobbyFailure {
  /// Could not reach the lobby at all.
  unreachable,

  /// The lobby answered with something this app does not understand.
  invalidResponse,

  /// Too many requests from this network; try again shortly.
  rateLimited,

  /// The lobby is full.
  busy,
}

class LobbyException implements Exception {
  const LobbyException(this.failure, [this.detail]);

  final LobbyFailure failure;
  final String? detail;

  @override
  String toString() =>
      'LobbyException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// Talks to the lobby server: earns a session with proof-of-work, then opens
/// the matchmaking socket.
///
/// The lobby is a remote party like any other: every response is validated,
/// and a lobby asking for absurd proof-of-work is refused rather than obeyed.
class LobbyClient {
  LobbyClient(this.baseUrl, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// e.g. `https://play.example.com`.
  final Uri baseUrl;
  final http.Client _http;

  /// Hardest proof-of-work this client will attempt. Each bit doubles the
  /// work; past this a hostile or misconfigured lobby could pin the device.
  static const int maxDifficulty = 22;

  static const Duration _requestTimeout = Duration(seconds: 15);

  /// The lobby's address for WebSockets.
  Uri socketUri(String path, [Map<String, String>? query]) => baseUrl.replace(
    scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws',
    path: path,
    queryParameters: query,
  );

  /// Solve a challenge and return a session token.
  Future<String> admit() async {
    final challenge = await _getJson(baseUrl.resolve('/api/challenge'));
    final token = challenge['challenge'];
    final difficulty = challenge['difficulty'];
    if (token is! String || token.length > 512) {
      throw const LobbyException(LobbyFailure.invalidResponse, 'challenge');
    }
    if (difficulty is! int || difficulty < 1 || difficulty > maxDifficulty) {
      throw const LobbyException(LobbyFailure.invalidResponse, 'difficulty');
    }

    final counter = await _solve(token, difficulty);
    if (counter == null) {
      throw const LobbyException(LobbyFailure.invalidResponse, 'unsolvable');
    }

    final admitted = await _postJson(baseUrl.resolve('/api/admit'), {
      'challenge': token,
      'counter': counter,
    });
    final session = admitted['token'];
    if (session is! String || session.length > 512) {
      throw const LobbyException(LobbyFailure.invalidResponse, 'token');
    }
    return session;
  }

  /// Off the UI thread: an isolate natively, small yielding batches on the
  /// web, where there are no isolates.
  static Future<int?> _solve(String challenge, int difficulty) {
    if (kIsWeb) return pow.solve(challenge, difficulty);
    return Isolate.run(() => pow.solve(challenge, difficulty, batch: 1 << 20));
  }

  /// Open the matchmaking socket with a session [token].
  Future<LobbyConnection> connect(String token) async {
    final channel = WebSocketChannel.connect(
      socketUri('/api/lobby', {'token': token}),
    );
    try {
      await channel.ready.timeout(_requestTimeout);
    } catch (e) {
      throw LobbyException(LobbyFailure.unreachable, '$e');
    }
    return LobbyConnection._(channel);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) => _send(() => _http.get(uri));

  Future<Map<String, dynamic>> _postJson(Uri uri, Object body) => _send(
    () => _http.post(
      uri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(_requestTimeout);
    } catch (e) {
      throw LobbyException(LobbyFailure.unreachable, '$e');
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 429:
        throw const LobbyException(LobbyFailure.rateLimited);
      case 503:
        throw const LobbyException(LobbyFailure.busy);
      default:
        throw LobbyException(
          LobbyFailure.invalidResponse,
          'HTTP ${response.statusCode}',
        );
    }
    if (response.bodyBytes.length > 4096) {
      throw const LobbyException(LobbyFailure.invalidResponse, 'too large');
    }
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) return json;
    } on FormatException {
      // Falls through.
    }
    throw const LobbyException(LobbyFailure.invalidResponse, 'not JSON');
  }

  void close() => _http.close();
}

/// An open matchmaking socket.
class LobbyConnection {
  LobbyConnection._(this._channel) {
    _channel.stream.listen(
      (data) {
        if (data is! String || data.length > maxLobbyMessageLength) return;
        Object? json;
        try {
          json = jsonDecode(data);
        } on FormatException {
          return;
        }
        final message = ServerMessage.fromJson(json);
        if (message != null) _messages.add(message);
      },
      onDone: _messages.close,
      onError: (_) => _messages.close(),
      cancelOnError: true,
    );
  }

  final WebSocketChannel _channel;
  final _messages = StreamController<ServerMessage>.broadcast();

  /// Valid messages from the lobby; anything malformed is dropped. Closes
  /// when the socket does, which the lobby does right after a match.
  Stream<ServerMessage> get messages => _messages.stream;

  void send(ClientMessage message) =>
      _channel.sink.add(jsonEncode(message.toJson()));

  Future<void> close() => _channel.sink.close();
}
