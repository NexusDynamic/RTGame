import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:peer_coordinator/websocket.dart' show HubCredentials;
import 'package:rise_together_lobby/protocol.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/peer_game_session.dart';
import 'package:rise_together_game/src/online/lobby_client.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

/// Where matchmaking has got to.
sealed class MatchmakingState {
  const MatchmakingState();
}

/// Solving the lobby's proof-of-work.
final class Admitting extends MatchmakingState {
  const Admitting();
}

/// In the lobby, gathering players. [code] is set for a private room.
final class Gathering extends MatchmakingState {
  const Gathering({required this.joined, required this.players, this.code});

  final int joined;
  final int players;
  final String? code;
}

/// Matched; connecting to the other players.
final class ConnectingToPlayers extends MatchmakingState {
  const ConnectingToPlayers({required this.host});

  final bool host;
}

/// Connected and set up: ready to play.
final class MatchReady extends MatchmakingState {
  const MatchReady(this.session);

  final GameSession session;
}

/// Matchmaking stopped. [reason] says why.
final class MatchmakingFailed extends MatchmakingState {
  const MatchmakingFailed(this.reason);

  final MatchmakingFailure reason;
}

enum MatchmakingFailure {
  unreachable,
  rateLimited,
  busy,
  roomNotFound,
  roomFull,
  hostLeft,
  couldNotConnect,
  invalidResponse,
}

/// Runs one trip from "find me a game" to a started [GameSession].
///
/// Lobby → match details → peer-to-peer session. Owns everything it opens
/// until [MatchReady], when the session passes to the caller.
class MatchmakingController extends ChangeNotifier with AppLogging {
  MatchmakingController({
    required this.lobby,
    required this.adapterFactory,
    this.timings = const SessionTimings(),
  });

  final LobbyClient lobby;

  /// Builds the WebRTC adapter; `flutterWebrtcAdapterFactory` in the app.
  final RtcPeerAdapter Function(String selfNodeUId) adapterFactory;
  final SessionTimings timings;

  MatchmakingState _state = const Admitting();
  MatchmakingState get state => _state;

  LobbyConnection? _connection;
  PeerGameSession? _pending;
  bool _cancelled = false;
  bool _handedOver = false;

  void _set(MatchmakingState state) {
    if (_cancelled) return;
    _state = state;
    notifyListeners();
  }

  /// Ask the lobby for a match and follow it through.
  Future<void> start({
    required ClientMessage request,
    required String nickname,
    required double roundDurationSeconds,
  }) async {
    try {
      final token = await lobby.admit();
      if (_cancelled) return;
      final connection = _connection = await lobby.connect(token);
      if (_cancelled) {
        await connection.close();
        return;
      }

      final match = await _awaitMatch(connection, request);
      if (match == null || _cancelled) return;

      _set(ConnectingToPlayers(host: match.host));
      final session = _pending = await PeerGameSession.connect(
        transport: RtcTransportConfig(
          hubUri: lobby.socketUri(match.path),
          credentials: HubCredentials(
            session: match.room,
            secret: match.secret,
          ),
          adapterFactory: adapterFactory,
          iceServers: [for (final s in match.iceServers) s.toJson()],
          // Physics goes out 60 times a second: a late sample is worthless,
          // so don't wait for retransmits or reorder.
          dataOrdered: false,
          dataMaxRetransmits: 1,
        ),
        roomName: match.room,
        nickname: nickname,
        playerCount: match.players,
        host: match.host,
        timings: timings,
      );
      if (_cancelled) return;
      await session.startMatch(
        hostRules: MatchRules(
          mode: match.mode == LobbyMode.coop
              ? MatchMode.coop
              : MatchMode.versus,
          roundDurationSeconds: roundDurationSeconds.clamp(
            MatchRules.minRoundSeconds,
            MatchRules.maxRoundSeconds,
          ),
          seed: Random.secure().nextInt(MatchRules.maxSeed),
        ),
      );
      if (_cancelled) return;
      _pending = null;
      _handedOver = true;
      _set(MatchReady(session));
    } on LobbyException catch (e) {
      appLog.warning('Lobby: $e');
      _set(
        MatchmakingFailed(switch (e.failure) {
          LobbyFailure.unreachable => MatchmakingFailure.unreachable,
          LobbyFailure.rateLimited => MatchmakingFailure.rateLimited,
          LobbyFailure.busy => MatchmakingFailure.busy,
          LobbyFailure.invalidResponse => MatchmakingFailure.invalidResponse,
        }),
      );
    } catch (e) {
      appLog.warning('Matchmaking failed: $e');
      _set(const MatchmakingFailed(MatchmakingFailure.couldNotConnect));
    } finally {
      await _connection?.close();
      _connection = null;
    }
  }

  /// Send [request], report progress, and return the match (or null after
  /// reporting a failure).
  Future<MatchFound?> _awaitMatch(
    LobbyConnection connection,
    ClientMessage request,
  ) async {
    _set(switch (request) {
      QuickMatch(:final players) ||
      CreateRoom(:final players) => Gathering(joined: 0, players: players),
      JoinRoom() => const Gathering(joined: 0, players: minPlayers),
    });
    final done = Completer<MatchFound?>();
    final subscription = connection.messages.listen(
      (message) {
        switch (message) {
          case Waiting(:final joined, :final players, :final code):
            _set(Gathering(joined: joined, players: players, code: code));
          case MatchFound():
            if (!done.isCompleted) done.complete(message);
          case LobbyError(:final code):
            _set(
              MatchmakingFailed(switch (code) {
                LobbyErrorCode.roomNotFound => MatchmakingFailure.roomNotFound,
                LobbyErrorCode.roomFull => MatchmakingFailure.roomFull,
                LobbyErrorCode.hostLeft => MatchmakingFailure.hostLeft,
                LobbyErrorCode.busy => MatchmakingFailure.busy,
                LobbyErrorCode.rateLimited => MatchmakingFailure.rateLimited,
                LobbyErrorCode.badRequest => MatchmakingFailure.invalidResponse,
              }),
            );
            if (!done.isCompleted) done.complete(null);
        }
      },
      onDone: () {
        if (done.isCompleted) return;
        if (!_cancelled) {
          _set(const MatchmakingFailed(MatchmakingFailure.unreachable));
        }
        done.complete(null);
      },
    );
    connection.send(request);
    try {
      return await done.future;
    } finally {
      await subscription.cancel();
    }
  }

  /// Stop, releasing anything not yet handed over.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _connection?.close();
    await _pending?.leave();
    _pending = null;
  }

  @override
  void dispose() {
    if (!_handedOver) unawaited(cancel());
    super.dispose();
  }
}
