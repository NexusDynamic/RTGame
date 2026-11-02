import 'dart:io';

import 'package:meta/meta.dart';
import 'package:rise_together_lobby/metered_socket.dart';
import 'package:rise_together_lobby/protocol.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The most a lobby may send this app, in bytes: a burst, then a trickle.
/// Lobby messages are a few hundred bytes; anything near this is hostile.
const int lobbyBurstBytes = 64 * 1024;
const int lobbyBytesPerSecond = 4 * 1024;

/// The port to dial for [url]. `WebSocket.connect` hands the connection
/// factory a URL whose port is 0 when the lobby address has none (the usual
/// `https://host`); HttpClient defaults it itself, a custom factory must too.
@visibleForTesting
int lobbySocketPort(Uri url) {
  if (url.port != 0) return url.port;
  return url.scheme == 'https' || url.scheme == 'wss' ? 443 : 80;
}

/// Opens [uri] with the inbound bytes metered.
///
/// The lobby URL is a setting, so the server may be anyone's. The message
/// length check in `LobbyConnection` runs only once dart:io has assembled a
/// message, and dart:io bounds frames, not messages: a hostile lobby could
/// stream one endless fragmented message. The socket under the WebSocket is
/// metered instead, and a single frame is capped too.
WebSocketChannel connectLobbySocket(Uri uri) {
  final client = HttpClient()
    ..connectionFactory = (url, proxyHost, proxyPort) async {
      final secure = url.scheme == 'https' || url.scheme == 'wss';
      final port = lobbySocketPort(url);
      final task = secure
          ? await SecureSocket.startConnect(url.host, port)
          : await Socket.startConnect(url.host, port);
      return ConnectionTask.fromSocket(
        task.socket.then<Socket>(
          (socket) => MeteredSocket(
            socket,
            ByteBudget(
              capacity: lobbyBurstBytes,
              perSecond: lobbyBytesPerSecond,
            ),
          ),
        ),
        task.cancel,
      );
    };
  final socket = WebSocket.connect(
    uri.toString(),
    customClient: client,
    maxPayloadLength: maxLobbyMessageLength * 4,
  ).whenComplete(() => client.close());
  return IOWebSocketChannel(socket);
}
