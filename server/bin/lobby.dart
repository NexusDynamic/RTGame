import 'dart:io';

import 'package:logging/logging.dart';
import 'package:rise_together_lobby/lobby.dart';

Future<void> main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    stdout.writeln(
      '${r.time.toIso8601String()} ${r.level.name} ${r.loggerName}: '
      '${r.message}${r.error == null ? '' : ' ${r.error}'}',
    );
  });

  final LobbyConfig config;
  try {
    config = LobbyConfig.fromEnvironment();
  } on ArgumentError catch (e) {
    stderr.writeln('Configuration error: ${e.message}');
    exit(64);
  }

  final server = LobbyServer(config);
  await server.start();

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await server.stop();
      exit(0);
    });
  }
}
