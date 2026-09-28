/// The lobby's wire protocol, shared by server and app. Web-safe.
///
/// Everything here decodes defensively: both sides treat the other as
/// untrusted, so a decoder returns null for anything it does not fully
/// understand and never throws.
library;

/// How players are split across teams. Mirrors the app's `MatchMode`.
enum LobbyMode { coop, versus }

/// Players per match. Small by design: the host's device runs the physics
/// and relays to everyone, and the press indicators have a fixed bit budget.
const int minPlayers = 2;
const int maxPlayers = 4;

/// Private room codes: no 0/O or 1/I/L, so they can be read out loud.
const String roomCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const int roomCodeLength = 6;

/// Longest lobby message either side accepts, in characters.
const int maxLobbyMessageLength = 4096;

bool isValidRoomCode(Object? code) =>
    code is String &&
    code.length == roomCodeLength &&
    code.split('').every(roomCodeAlphabet.contains);

LobbyMode? _mode(Object? value) =>
    LobbyMode.values.where((m) => m.name == value).firstOrNull;

/// The optional custom-levels flag: absent means false, anything but a bool
/// is invalid (null).
bool? _custom(Object? value) =>
    value == null ? false : (value is bool ? value : null);

int? _players(Object? value) =>
    value is int && value >= minPlayers && value <= maxPlayers ? value : null;

// --- client -> server --------------------------------------------------------

sealed class ClientMessage {
  const ClientMessage();

  Map<String, dynamic> toJson();

  static ClientMessage? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    switch (json['t']) {
      case QuickMatch.type:
        final mode = _mode(json['mode']);
        final players = _players(json['players']);
        final custom = _custom(json['custom']);
        if (mode == null || players == null || custom == null) return null;
        return QuickMatch(mode: mode, players: players, custom: custom);
      case CreateRoom.type:
        final mode = _mode(json['mode']);
        final players = _players(json['players']);
        final custom = _custom(json['custom']);
        if (mode == null || players == null || custom == null) return null;
        return CreateRoom(mode: mode, players: players, custom: custom);
      case JoinRoom.type:
        final code = json['code'];
        if (!isValidRoomCode(code)) return null;
        return JoinRoom(code: code as String);
      default:
        return null;
    }
  }
}

/// Match me with strangers.
///
/// [custom] asks for a match on player-made levels. Those players have their
/// own queue, so nobody gets custom levels without asking for them.
final class QuickMatch extends ClientMessage {
  const QuickMatch({
    required this.mode,
    required this.players,
    this.custom = false,
  });

  static const type = 'quick';

  final LobbyMode mode;
  final int players;
  final bool custom;

  @override
  Map<String, dynamic> toJson() => {
    't': type,
    'mode': mode.name,
    'players': players,
    if (custom) 'custom': true,
  };
}

/// Open a private room; the server replies with its code.
///
/// [custom] marks the room as played on the creator's own levels; everyone
/// who joins is told before the match starts.
final class CreateRoom extends ClientMessage {
  const CreateRoom({
    required this.mode,
    required this.players,
    this.custom = false,
  });

  static const type = 'create';

  final LobbyMode mode;
  final int players;
  final bool custom;

  @override
  Map<String, dynamic> toJson() => {
    't': type,
    'mode': mode.name,
    'players': players,
    if (custom) 'custom': true,
  };
}

/// Join a private room by its code.
final class JoinRoom extends ClientMessage {
  const JoinRoom({required this.code});

  static const type = 'join';

  final String code;

  @override
  Map<String, dynamic> toJson() => {'t': type, 'code': code};
}

// --- server -> client --------------------------------------------------------

sealed class ServerMessage {
  const ServerMessage();

  Map<String, dynamic> toJson();

  static ServerMessage? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    switch (json['t']) {
      case Waiting.type:
        final joined = json['joined'];
        final players = _players(json['players']);
        final code = json['code'];
        final custom = _custom(json['custom']);
        if (joined is! int || players == null || custom == null) return null;
        if (joined < 0 || joined > players) return null;
        if (code != null && !isValidRoomCode(code)) return null;
        return Waiting(
          joined: joined,
          players: players,
          code: code as String?,
          custom: custom,
        );
      case MatchFound.type:
        return MatchFound.tryFromJson(json);
      case LobbyError.type:
        final code = LobbyErrorCode.values
            .where((c) => c.name == json['code'])
            .firstOrNull;
        return code == null ? null : LobbyError(code);
      default:
        return null;
    }
  }
}

/// Still gathering players. [code] is set for a private room, and [custom]
/// when the match will be played on the host's own levels.
final class Waiting extends ServerMessage {
  const Waiting({
    required this.joined,
    required this.players,
    this.code,
    this.custom = false,
  });

  static const type = 'waiting';

  final int joined;
  final int players;
  final String? code;
  final bool custom;

  @override
  Map<String, dynamic> toJson() => {
    't': type,
    'joined': joined,
    'players': players,
    if (code != null) 'code': code,
    if (custom) 'custom': true,
  };
}

/// A STUN or TURN server for WebRTC.
final class IceServer {
  const IceServer({required this.urls, this.username, this.credential});

  final List<String> urls;
  final String? username;
  final String? credential;

  /// The map shape `RTCPeerConnection` takes.
  Map<String, dynamic> toJson() => {
    'urls': urls,
    if (username != null) 'username': username,
    if (credential != null) 'credential': credential,
  };

  static IceServer? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final urls = json['urls'];
    final username = json['username'];
    final credential = json['credential'];
    if (urls is! List || urls.isEmpty || urls.length > 4) return null;
    final parsed = <String>[];
    for (final url in urls) {
      // Only ICE URL schemes; anything else is not ours to hand to WebRTC.
      if (url is! String || url.length > 256) return null;
      if (!RegExp(r'^(stun|stuns|turn|turns):').hasMatch(url)) return null;
      parsed.add(url);
    }
    if (username != null && (username is! String || username.length > 128)) {
      return null;
    }
    if (credential != null &&
        (credential is! String || credential.length > 128)) {
      return null;
    }
    return IceServer(
      urls: parsed,
      username: username as String?,
      credential: credential as String?,
    );
  }
}

/// Everything a player needs to join their match, sent once, after which
/// the lobby closes the socket.
final class MatchFound extends ServerMessage {
  const MatchFound({
    required this.room,
    required this.secret,
    required this.host,
    required this.mode,
    required this.players,
    required this.iceServers,
    this.custom = false,
  });

  static const type = 'match';

  /// Room id: the hub's session name and the path `/room/<room>`.
  final String room;

  /// The room hub's credential. Only players matched into the room get it.
  final String secret;

  /// Whether this player hosts: runs the physics and sets the match up.
  final bool host;
  final LobbyMode mode;
  final int players;
  final List<IceServer> iceServers;

  /// Played on the host's own levels, which the host sends in the match
  /// setup. A follower refuses a setup that does not agree with this.
  final bool custom;

  /// Path of the room's signaling hub on the lobby server.
  String get path => '/room/$room';

  static final _roomId = RegExp(r'^[0-9a-f]{32}$');

  @override
  Map<String, dynamic> toJson() => {
    't': type,
    'room': room,
    'secret': secret,
    'host': host,
    'mode': mode.name,
    'players': players,
    'ice': [for (final s in iceServers) s.toJson()],
    if (custom) 'custom': true,
  };

  static MatchFound? tryFromJson(Map<String, dynamic> json) {
    final room = json['room'];
    final secret = json['secret'];
    final host = json['host'];
    final mode = _mode(json['mode']);
    final players = _players(json['players']);
    final ice = json['ice'];
    final custom = _custom(json['custom']);
    if (custom == null) return null;
    if (room is! String || !_roomId.hasMatch(room)) return null;
    if (secret is! String || secret.isEmpty || secret.length > 128) return null;
    if (host is! bool || mode == null || players == null) return null;
    if (ice is! List || ice.length > 4) return null;
    final servers = <IceServer>[];
    for (final entry in ice) {
      final server = IceServer.tryFromJson(entry);
      if (server == null) return null;
      servers.add(server);
    }
    return MatchFound(
      room: room,
      secret: secret,
      host: host,
      mode: mode,
      players: players,
      iceServers: servers,
      custom: custom,
    );
  }
}

enum LobbyErrorCode {
  /// A message the server could not understand.
  badRequest,

  /// No private room with that code (or it expired).
  roomNotFound,

  /// The private room filled up first.
  roomFull,

  /// The room's creator left before it filled.
  hostLeft,

  /// Too many rooms or players right now; try again later.
  busy,

  /// Too many requests from this address.
  rateLimited,
}

final class LobbyError extends ServerMessage {
  const LobbyError(this.code);

  static const type = 'error';

  final LobbyErrorCode code;

  @override
  Map<String, dynamic> toJson() => {'t': type, 'code': code.name};
}
