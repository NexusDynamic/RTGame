import 'package:rise_together_game/src/settings/app_settings.dart';

/// Where the lobby lives.
///
/// A player can set their own server in Settings (`online.server_url`);
/// otherwise the build's default is used. The default is set at build time
/// with `--dart-define=LOBBY_URL=https://play.example.com`, and
/// `--dart-define=LOBBY_URL=none` builds with no default server (offline
/// unless the player picks one).
///
/// Not a secret: it is the public address of the lobby, which gates itself
/// with proof-of-work (see server/README.md).
abstract final class OnlineConfig {
  static const String _buildDefault = String.fromEnvironment(
    'LOBBY_URL',
    defaultValue: 'https://rt-lobby.nexusdynamic.org',
  );

  /// The setting holding the player's own server; empty for the default.
  static const settingKey = 'online.server_url';

  /// A lobby address the player typed, or null when it is not one: http(s)
  /// with a host, and nothing that could smuggle credentials or parameters.
  static Uri? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return null;
    }
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }

  /// The player's server when it is valid, else the build default (null
  /// when the build has none).
  static Uri? resolve({required String custom, required String buildDefault}) {
    if (custom.trim().isNotEmpty) {
      final uri = parse(custom);
      if (uri != null) return uri;
    }
    if (buildDefault == 'none') return null;
    return parse(buildDefault);
  }

  /// This build's server, ignoring the player's setting.
  static Uri? get defaultUrl =>
      resolve(custom: '', buildDefault: _buildDefault);

  static Uri? get lobbyUrl => resolve(
    custom: Settings.instance.appSettings.getString(settingKey),
    buildDefault: _buildDefault,
  );

  static bool get isAvailable => lobbyUrl != null;
}
