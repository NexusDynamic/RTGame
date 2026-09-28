import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Gives a class an [appLog] for diagnostic logging.
///
/// A thin wrapper over `package:logging`: messages go to the root logger and
/// [configureLogging] prints them in debug builds. There is no file output,
/// so this works on every platform, web included.
mixin class AppLogging {
  AppLogger get appLog => AppLogger.instance;
}

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const String defaultLoggerName = 'RiseTogether';

  void finest(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(Level.FINEST, message, error, stackTrace);

  void finer(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(Level.FINER, message, error, stackTrace);

  void fine(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(Level.FINE, message, error, stackTrace);

  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(Level.INFO, message, error, stackTrace);

  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(Level.WARNING, message, error, stackTrace);

  void severe(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(Level.SEVERE, message, error, stackTrace);

  void _log(Level level, String message, Object? error, StackTrace? st) {
    // Checked before touching the Logger so filtered-out messages cost nothing
    // beyond building the string at the call site.
    if (!Logger.root.isLoggable(level)) return;
    Logger(defaultLoggerName).log(level, message, error, st);
  }
}

/// Route log records to the console. Call once from `main`.
///
/// Release builds log warnings and above only.
void configureLogging({Level? level}) {
  Logger.root.level = level ?? (kReleaseMode ? Level.WARNING : Level.INFO);
  Logger.root.onRecord.listen((record) {
    final buffer = StringBuffer()
      ..write('[${record.level.name}] ${record.time.toIso8601String()} ')
      ..write(record.message);
    if (record.error != null) buffer.write(' | ${record.error}');
    debugPrint(buffer.toString());
    if (record.stackTrace != null) debugPrint(record.stackTrace.toString());
  });
}
