import 'package:package_info_plus/package_info_plus.dart';

/// App version, read once at startup.
class RiseTogetherPackageInfo {
  static final instance = RiseTogetherPackageInfo._internal();
  static String get version => instance._version;
  static String get buildNumber => instance._buildNumber;
  String _version = 'unknown';
  String _buildNumber = '0';

  /// Git commit this build was made from.
  ///
  /// Populated at build time with
  /// `--dart-define=GIT_SHA=$(git rev-parse --short HEAD)`; falls back to
  /// 'unknown' for builds that do not pass it.
  static const String gitSha = String.fromEnvironment(
    'GIT_SHA',
    defaultValue: 'unknown',
  );

  RiseTogetherPackageInfo._internal();

  factory RiseTogetherPackageInfo() => instance;

  Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    _version = info.version;
    _buildNumber = info.buildNumber;
  }

  @override
  String toString() => '$_version+$_buildNumber ($gitSha)';
}
