import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../metered_socket.dart';

export '../../metered_socket.dart' show ByteBudget;

/// `shelf_web_socket`'s `webSocketHandler`, with an inbound [ByteBudget].
///
/// The length checks the lobby made on a message ran only after dart:io had
/// assembled the whole message, and dart:io bounds frames, never messages: a
/// client could send one message as an unbounded run of small continuation
/// frames and the server buffered all of it. Metering the raw bytes beneath
/// the WebSocket bounds what any client can make the server hold, however it
/// frames it, and [maxFrameBytes] rejects an oversized single frame early.
Handler meteredWebSocketHandler(
  void Function(WebSocketChannel socket) onConnection, {
  required ByteBudget Function() budget,
  required int maxFrameBytes,
  Iterable<String>? allowedOrigins,
  Duration? pingInterval,
}) {
  final origins = allowedOrigins?.map((o) => o.toLowerCase()).toSet();
  return (Request request) {
    if (request.method != 'GET') return Response.notFound(null);
    final connection = request.headers['connection'];
    final upgrade = request.headers['upgrade'];
    if (connection == null ||
        upgrade == null ||
        !connection
            .toLowerCase()
            .split(',')
            .map((t) => t.trim())
            .contains('upgrade') ||
        upgrade.toLowerCase() != 'websocket') {
      return Response.notFound(null);
    }
    if (request.headers['sec-websocket-version'] != '13') {
      return Response(426, headers: {'sec-websocket-version': '13'});
    }
    final key = request.headers['sec-websocket-key'];
    if (key == null || request.protocolVersion != '1.1') {
      return Response.badRequest();
    }
    // Browsers always send Origin; refusing unexpected ones stops a hostile
    // page from opening a socket with the visitor's network position.
    final origin = request.headers['origin'];
    if (origin != null &&
        origins != null &&
        !origins.contains(origin.toLowerCase())) {
      return Response.forbidden('origin not allowed');
    }

    request.hijack((channel) {
      final socket = channel.sink as Socket;
      socket.add(
        utf8.encode(
          'HTTP/1.1 101 Switching Protocols\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Accept: ${WebSocketChannel.signKey(key)}\r\n'
          '\r\n',
        ),
      );
      final webSocket = WebSocket.fromUpgradedSocket(
        MeteredSocket(socket, budget()),
        serverSide: true,
        maxPayloadLength: maxFrameBytes,
      )..pingInterval = pingInterval;
      onConnection(IOWebSocketChannel(webSocket));
    });
  };
}
