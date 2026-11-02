/// A byte budget beneath a WebSocket: `dart:io` bounds each frame but
/// buffers a fragmented message until its final frame, so a peer streaming
/// small non-final frames could make the receiver hold an unbounded message.
/// Metering the raw socket bounds that whatever the framing.
///
/// `dart:io` only. Shared by the lobby server and the app's native lobby
/// client.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// A [Socket] whose inbound bytes are charged to a [ByteBudget]; the socket
/// is destroyed when the budget runs out. Everything else is delegated.
class MeteredSocket extends Stream<Uint8List> implements Socket {
  MeteredSocket(this._socket, this._budget);

  final Socket _socket;
  final ByteBudget _budget;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final metered = _MeteredSubscription(onData);
    metered._inner = _socket.listen(
      (chunk) {
        if (!_budget.take(chunk.length)) {
          // Destroyed, not closed: a peer over budget gets nothing more.
          _socket.destroy();
          return;
        }
        metered._onData?.call(chunk);
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return metered;
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

/// The subscription [MeteredSocket.listen] returns. Replacing its data
/// handler replaces what metered data is forwarded to, never the metering:
/// `HttpClient` hands an upgraded connection to the WebSocket by calling
/// `onData` on the subscription it had, which on a plain wrapper silently
/// dropped the meter for everything after the handshake.
class _MeteredSubscription implements StreamSubscription<Uint8List> {
  _MeteredSubscription(this._onData);

  void Function(Uint8List data)? _onData;
  late final StreamSubscription<Uint8List> _inner;

  @override
  void onData(void Function(Uint8List data)? handleData) =>
      _onData = handleData;

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  bool get isPaused => _inner.isPaused;

  @override
  Future<void> cancel() => _inner.cancel();

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}
