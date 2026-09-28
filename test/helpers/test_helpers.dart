import 'package:logging/logging.dart';

/// Silence logging for the whole test file. Call from `setUpAll`.
void silenceLogs() => Logger.root.level = Level.OFF;
