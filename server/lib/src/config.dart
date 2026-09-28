import 'dart:io';

/// Lobby configuration, from the environment (see `deploy/.env.example`).
class LobbyConfig {
  LobbyConfig({
    required this.signingKey,
    this.host = '0.0.0.0',
    this.port = 8080,
    this.allowedOrigins = const [],
    this.trustProxy = false,
    this.powDifficulty = 17,
    this.stunUrls = const [],
    this.turnUrls = const [],
    this.turnSecret,
    this.turnCredentialTtl = const Duration(minutes: 10),
    this.maxRooms = 200,
    this.maxLobbyConnections = 1000,
    this.maxConnectionsPerIp = 8,
    this.roomTtl = const Duration(hours: 2),
    this.privateRoomTtl = const Duration(minutes: 15),
    this.sessionTokenTtl = const Duration(minutes: 15),
    this.challengeTtl = const Duration(minutes: 2),
  }) {
    if (signingKey.length < 32) {
      throw ArgumentError('LOBBY_SIGNING_KEY must be at least 32 characters');
    }
    if (powDifficulty < 1 || powDifficulty > 28) {
      throw ArgumentError.value(powDifficulty, 'powDifficulty');
    }
    if (turnUrls.isNotEmpty && (turnSecret == null || turnSecret!.isEmpty)) {
      throw ArgumentError('TURN_URLS needs TURN_SECRET');
    }
  }

  /// Signs challenges and session tokens. Never leaves the server.
  final String signingKey;

  final String host;
  final int port;

  /// Browser origins allowed to use the lobby, e.g. `https://play.example`.
  /// Requests without an Origin header (native apps) are not affected.
  final List<String> allowedOrigins;

  /// Read the client address from `X-Forwarded-For`. Only enable behind a
  /// proxy that sets it (Caddy does); otherwise clients can spoof it.
  final bool trustProxy;

  /// Proof-of-work difficulty in leading zero bits. Each step doubles the
  /// work; 17 is well under a second on a phone.
  final int powDifficulty;

  final List<String> stunUrls;
  final List<String> turnUrls;

  /// coturn's `static-auth-secret`. Never leaves the server.
  final String? turnSecret;
  final Duration turnCredentialTtl;

  final int maxRooms;
  final int maxLobbyConnections;
  final int maxConnectionsPerIp;
  final Duration roomTtl;
  final Duration privateRoomTtl;
  final Duration sessionTokenTtl;
  final Duration challengeTtl;

  static List<String> _list(String? raw) => (raw ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  factory LobbyConfig.fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    int intOf(String key, int fallback) =>
        int.tryParse(e[key] ?? '') ?? fallback;
    final key = e['LOBBY_SIGNING_KEY'];
    if (key == null) throw ArgumentError('LOBBY_SIGNING_KEY is required');
    return LobbyConfig(
      signingKey: key,
      host: e['LOBBY_HOST'] ?? '0.0.0.0',
      port: intOf('LOBBY_PORT', 8080),
      allowedOrigins: _list(e['ALLOWED_ORIGINS']),
      trustProxy: e['TRUST_PROXY'] == 'true',
      powDifficulty: intOf('POW_DIFFICULTY', 17),
      stunUrls: _list(e['STUN_URLS']),
      turnUrls: _list(e['TURN_URLS']),
      turnSecret: e['TURN_SECRET'],
      turnCredentialTtl: Duration(seconds: intOf('TURN_TTL_SECONDS', 600)),
      maxRooms: intOf('MAX_ROOMS', 200),
      maxLobbyConnections: intOf('MAX_LOBBY_CONNECTIONS', 1000),
      maxConnectionsPerIp: intOf('MAX_CONNECTIONS_PER_IP', 8),
    );
  }
}
