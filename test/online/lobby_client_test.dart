import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/online/lobby_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The lobby URL is a setting, so the lobby may be hostile.
void main() {
  test('a lobby streaming one endless fragmented message is cut off', () async {
    // dart:io bounds frames, not messages: without a byte meter under the
    // socket the app buffered all of it. A raw server, because no WebSocket
    // library sends this.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    // `sent` counts what the server's kernel accepted, not what the client
    // read: loopback TCP buffers auto-tune to several MB on Linux, so the
    // server gets well past the client's 64 KB budget before the reset comes
    // back. The bound is just far above any socket buffering.
    const limit = 64 * 1024 * 1024;
    var sent = 0;
    server.listen((socket) {
      final request = <int>[];
      var upgraded = false;
      socket.listen((bytes) async {
        if (upgraded) return;
        request.addAll(bytes);
        final text = latin1.decode(request);
        if (!text.contains('\r\n\r\n')) return;
        upgraded = true;
        final key = RegExp(
          r'sec-websocket-key:\s*(\S+)',
          caseSensitive: false,
        ).firstMatch(text)!.group(1)!;
        socket.write(
          'HTTP/1.1 101 Switching Protocols\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Accept: ${WebSocketChannel.signKey(key)}\r\n\r\n',
        );
        await socket.flush();
        // Let the client finish the handshake first: this is about an
        // established connection.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        // Unmasked server frames without FIN: text, then continuations.
        List<int> frame(int opcode) => [
          opcode,
          126,
          4000 >> 8,
          4000 & 0xff,
          ...List.filled(4000, 0x61),
        ];
        try {
          socket.add(frame(0x1));
          while (sent < limit) {
            socket.add(frame(0x0));
            sent += 4000;
            await socket.flush();
          }
        } catch (_) {
          // The client hung up: the point.
        }
      }, onError: (_) {});
    });

    final client = LobbyClient(Uri.parse('http://127.0.0.1:${server.port}'));
    addTearDown(client.close);
    final connection = await client.connect('token');
    // The message stream ends when the socket is cut. Unmetered, dart:io
    // would buffer the message for as long as the server sends, and this
    // would time out.
    await connection.messages.drain<void>().timeout(
      const Duration(seconds: 10),
    );
    expect(sent, lessThan(limit));
  });
}
