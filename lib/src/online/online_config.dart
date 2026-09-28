/// Where the lobby lives, fixed at build time:
/// `--dart-define=LOBBY_URL=https://play.example.com`.
///
/// Not a secret: it is the public address of the lobby, which gates itself
/// with proof-of-work (see server/README.md).
abstract final class OnlineConfig {
  static const String _lobbyUrl = String.fromEnvironment('LOBBY_URL');

  static Uri? get lobbyUrl {
    if (_lobbyUrl.isEmpty) return null;
    final uri = Uri.tryParse(_lobbyUrl);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return null;
    }
    return uri;
  }

  static bool get isAvailable => lobbyUrl != null;
}
