import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:peer_coordinator/hub.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol.dart';

final _log = Logger('lobby.room');

/// One match's signaling hub.
///
/// A `peer_coordinator` [CoordinationHub] on a loopback port, with its own
/// random secret that only the matched players receive. Players reach it
/// through [attach], which forwards WebSocket frames unchanged; the hub does
/// its own authentication, so the proxy needs to know nothing about the
/// protocol. Once players have connected peer to peer the hub only carries
/// heartbeats, and it is closed when they leave or [ttl] passes.
class Room {
  Room._(
    this.id,
    this.secret,
    this.mode,
    this.players,
    this._hub,
    this._onClosed,
  );

  final String id;
  final String secret;
  final LobbyMode mode;
  final int players;
  final CoordinationHub _hub;
  final void Function(Room) _onClosed;

  final Set<_Proxy> _proxies = {};
  Timer? _ttlTimer;
  Timer? _idleTimer;
  bool _closed = false;

  /// How long matched players have to connect, and to come back after the
  /// last one drops.
  static const Duration connectGrace = Duration(seconds: 60);
  static const Duration emptyGrace = Duration(seconds: 15);

  bool get isClosed => _closed;
  int get connectionCount => _proxies.length;

  static Future<Room> open({
    required String id,
    required String secret,
    required LobbyMode mode,
    required int players,
    required Duration ttl,
    required void Function(Room) onClosed,
  }) async {
    final hub = await CoordinationHub.serve(
      credentials: HubCredentials(session: id, secret: secret),
      address: InternetAddress.loopbackIPv4,
      limits: WsLimits(
        // A reconnect can briefly overlap the dropped socket.
        maxConnections: players * 2,
        maxPeers: players * 8,
        maxFrameBytes: 64 * 1024,
      ),
      sessionTtl: ttl,
    );
    final room = Room._(id, secret, mode, players, hub, onClosed);
    room._ttlTimer = Timer(ttl, () => room.close('ttl'));
    room._idleTimer = Timer(connectGrace, () => room.close('nobody came'));
    return room;
  }

  /// Forward [client]'s WebSocket to this room's hub.
  Future<void> attach(WebSocketChannel client) async {
    if (_closed || _proxies.length >= players * 2) {
      await client.sink.close(1013, 'room full'); // 1013: try again later
      return;
    }
    final WebSocketChannel upstream;
    try {
      upstream = WebSocketChannel.connect(_hub.uri);
      await upstream.ready;
    } catch (e) {
      _log.warning('Room $id: hub unreachable: $e');
      await client.sink.close(WebSocketStatus.internalServerError);
      return;
    }
    _idleTimer?.cancel();
    late final _Proxy proxy;
    proxy = _Proxy(client, upstream, () {
      _proxies.remove(proxy);
      if (_proxies.isEmpty && !_closed) {
        _idleTimer = Timer(emptyGrace, () => close('empty'));
      }
    });
    _proxies.add(proxy);
  }

  Future<void> close(String reason) async {
    if (_closed) return;
    _closed = true;
    _ttlTimer?.cancel();
    _idleTimer?.cancel();
    _log.info('Room $id closing: $reason');
    for (final proxy in _proxies.toList()) {
      await proxy.close();
    }
    _proxies.clear();
    try {
      await _hub.close();
    } catch (e) {
      _log.warning('Room $id: hub close failed: $e');
    }
    _onClosed(this);
  }
}

/// Two sockets joined back to back.
class _Proxy {
  _Proxy(this._client, this._upstream, this._onDone) {
    _down = _upstream.stream.listen(
      _client.sink.add,
      onDone: close,
      onError: (_) => close(),
      cancelOnError: true,
    );
    _up = _client.stream.listen(
      _upstream.sink.add,
      onDone: close,
      onError: (_) => close(),
      cancelOnError: true,
    );
  }

  final WebSocketChannel _client;
  final WebSocketChannel _upstream;
  final void Function() _onDone;
  late final StreamSubscription<Object?> _up;
  late final StreamSubscription<Object?> _down;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _up.cancel();
    await _down.cancel();
    await _client.sink.close();
    await _upstream.sink.close();
    _onDone();
  }
}
