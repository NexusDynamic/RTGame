/// The lobby server. Server-only (`dart:io`); the app imports
/// `protocol.dart` and `pow.dart` instead.
library;

export 'src/config.dart';
export 'src/lobby_server.dart';
export 'src/turn.dart' show turnCredentials;
