/// Opens the lobby's matchmaking socket, with its inbound size bounded where
/// the platform allows it. See `lobby_socket_io.dart`.
library;

export 'lobby_socket_web.dart' if (dart.library.io) 'lobby_socket_io.dart';
