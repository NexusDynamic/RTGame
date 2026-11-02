import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// How many bytes a client may send on one socket: a burst of [capacity],
/// refilled at [perSecond]. Exceeding it closes the socket.
class ByteBudget {
  ByteBudget({required this.capacity, required this.perSecond})
    : _tokens = capacity.toDouble();

  final int capacity;
  final int perSecond;

  double _tokens;
  final Stopwatch _clock = Stopwatch()..start();

  /// Spend [bytes]; false once the budget is exhausted.
  bool take(int bytes) {
    final elapsed = _clock.elapsedMicroseconds / 1e6;
    _clock.reset();
    _tokens = (_tokens + elapsed * perSecond).clamp(0, capacity.toDouble());
    _tokens -= bytes;
    return _tokens >= 0;
  }
}

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
        _MeteredSocket(socket, budget()),
        serverSide: true,
        maxPayloadLength: maxFrameBytes,
      )..pingInterval = pingInterval;
      onConnection(IOWebSocketChannel(webSocket));
    });
  };
}

/// A [Socket] whose inbound bytes are charged to a [ByteBudget]; the socket
/// is destroyed when the budget runs out. Everything else is delegated.
class _MeteredSocket extends Stream<Uint8List> implements Socket {
  _MeteredSocket(this._socket, this._budget);

  final Socket _socket;
  final ByteBudget _budget;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    late final StreamSubscription<Uint8List> subscription;
    subscription = _socket.listen(
      (chunk) {
        if (!_budget.take(chunk.length)) {
          // Destroyed, not closed: a client over budget gets nothing more.
          _socket.destroy();
          return;
        }
        onData?.call(chunk);
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return subscription;
  }

  // --- delegated ------------------------------------------------------------

  @override
  Encoding get encoding => _socket.encoding;

  @override
  set encoding(Encoding value) => _socket.encoding = value;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> flush() => _socket.flush();

  @override
  void write(Object? object) => _socket.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _socket.writeln(object);

  @override
  InternetAddress get address => _socket.address;

  @override
  int get port => _socket.port;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  int get remotePort => _socket.remotePort;

  @override
  void destroy() => _socket.destroy();

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);
}
