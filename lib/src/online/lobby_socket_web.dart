import 'package:web_socket_channel/web_socket_channel.dart';

/// On the web the browser owns the socket and buffers each message whole
/// before Dart sees it, so there is nothing to meter; `LobbyConnection` still
/// drops oversized messages.
WebSocketChannel connectLobbySocket(Uri uri) => WebSocketChannel.connect(uri);
