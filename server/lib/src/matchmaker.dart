import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';

import '../protocol.dart';
import 'room.dart';

final _log = Logger('lobby.matchmaker');

/// One connected lobby client, as the matchmaker sees it.
abstract class LobbyPeer {
  /// Pseudonymous client id, for logs only.
  String get client;

  void send(ServerMessage message);

  /// Close the lobby connection. Called after a match is sent.
  Future<void> close();
}

/// Groups players into matches.
///
/// Quick match fills a queue per (mode, size, custom levels); private rooms
/// fill by code.
/// When a group is complete the matchmaker opens a [Room], sends each player
/// their [MatchFound] (the first to have arrived hosts) and lets them go.
class Matchmaker {
  Matchmaker({
    required this.openRoom,
    required this.credentialsFor,
    this.privateRoomTtl = const Duration(minutes: 15),
  });

  /// Opens a room, or returns null when the server is at capacity.
  final Future<Room?> Function(LobbyMode mode, int players) openRoom;

  /// Builds a player's match message for [room].
  final MatchFound Function(
    Room room, {
    required bool host,
    required bool custom,
  })
  credentialsFor;

  final Duration privateRoomTtl;

  final Map<_QueueKey, List<LobbyPeer>> _queues = {};
  final Map<String, _PrivateRoom> _private = {};

  /// Where each peer is waiting. A peer waits in at most one place.
  final Map<LobbyPeer, Object> _waiting = {};

  final Random _random = Random.secure();

  int get waitingCount => _waiting.length;
  int get privateRoomCount => _private.length;

  Future<void> handle(LobbyPeer peer, ClientMessage message) async {
    if (_waiting.containsKey(peer)) {
      peer.send(const LobbyError(LobbyErrorCode.badRequest));
      return;
    }
    switch (message) {
      case QuickMatch(:final mode, :final players, :final custom):
        await _queue(peer, (mode, players, custom));
      case CreateRoom(:final mode, :final players, :final custom):
        _create(peer, mode, players, custom);
      case JoinRoom(:final code):
        await _join(peer, code);
    }
  }

  /// Forget [peer]: it disconnected.
  void remove(LobbyPeer peer) {
    final where = _waiting.remove(peer);
    if (where is _QueueKey) {
      final queue = _queues[where]!..remove(peer);
      _announceQueue(where, queue);
    } else if (where is _PrivateRoom) {
      if (identical(where.members.first, peer)) {
        _closePrivate(where, const LobbyError(LobbyErrorCode.hostLeft));
      } else {
        where.members.remove(peer);
        where.announce();
      }
    }
  }

  Future<void> _queue(LobbyPeer peer, _QueueKey key) async {
    final (mode, players, custom) = key;
    final queue = _queues.putIfAbsent(key, () => []);
    queue.add(peer);
    _waiting[peer] = key;
    if (queue.length < players) {
      _announceQueue(key, queue);
      return;
    }
    final group = queue.sublist(0, players);
    queue.removeRange(0, players);
    for (final member in group) {
      _waiting.remove(member);
    }
    await _startMatch(group, mode, players, custom: custom);
  }

  void _announceQueue(_QueueKey key, List<LobbyPeer> queue) {
    // Each waiting player sees how full their next match is.
    final (_, players, custom) = key;
    for (var i = 0; i < queue.length; i++) {
      final ahead = i - i % players;
      final joined = min(queue.length - ahead, players);
      queue[i].send(Waiting(joined: joined, players: players, custom: custom));
    }
  }

  void _create(LobbyPeer peer, LobbyMode mode, int players, bool custom) {
    var code = _newCode();
    while (_private.containsKey(code)) {
      code = _newCode();
    }
    final room = _PrivateRoom(code, mode, players, custom, peer);
    room.expiry = Timer(privateRoomTtl, () {
      _closePrivate(room, const LobbyError(LobbyErrorCode.roomNotFound));
    });
    _private[code] = room;
    _waiting[peer] = room;
    room.announce();
  }

  Future<void> _join(LobbyPeer peer, String code) async {
    final room = _private[code];
    if (room == null) {
      peer.send(const LobbyError(LobbyErrorCode.roomNotFound));
      return;
    }
    if (room.members.length >= room.players) {
      peer.send(const LobbyError(LobbyErrorCode.roomFull));
      return;
    }
    room.members.add(peer);
    _waiting[peer] = room;
    if (room.members.length < room.players) {
      room.announce();
      return;
    }
    _private.remove(code);
    room.expiry?.cancel();
    for (final member in room.members) {
      _waiting.remove(member);
    }
    await _startMatch(
      room.members,
      room.mode,
      room.players,
      custom: room.custom,
    );
  }

  void _closePrivate(_PrivateRoom room, LobbyError error) {
    room.expiry?.cancel();
    _private.remove(room.code);
    for (final member in room.members) {
      _waiting.remove(member);
      member.send(error);
      unawaited(member.close());
    }
  }

  Future<void> _startMatch(
    List<LobbyPeer> group,
    LobbyMode mode,
    int players, {
    required bool custom,
  }) async {
    final room = await openRoom(mode, players);
    for (var i = 0; i < group.length; i++) {
      group[i].send(
        room == null
            ? const LobbyError(LobbyErrorCode.busy)
            : credentialsFor(room, host: i == 0, custom: custom),
      );
      unawaited(group[i].close());
    }
    if (room != null) {
      _log.info(
        'Matched ${group.map((p) => p.client).join(', ')} '
        'into room ${room.id}',
      );
    }
  }

  String _newCode() => String.fromCharCodes([
    for (var i = 0; i < roomCodeLength; i++)
      roomCodeAlphabet.codeUnitAt(_random.nextInt(roomCodeAlphabet.length)),
  ]);

  void dispose() {
    for (final room in _private.values) {
      room.expiry?.cancel();
    }
    _private.clear();
    _queues.clear();
    _waiting.clear();
  }
}

/// A quick-match queue: mode, players, and whether on custom levels.
typedef _QueueKey = (LobbyMode, int, bool);

class _PrivateRoom {
  _PrivateRoom(
    this.code,
    this.mode,
    this.players,
    this.custom,
    LobbyPeer creator,
  ) : members = [creator];

  final String code;
  final LobbyMode mode;
  final int players;

  /// Played on the creator's levels. Joiners learn this from [announce]
  /// before the match starts.
  final bool custom;

  /// The creator first: they host.
  final List<LobbyPeer> members;
  Timer? expiry;

  void announce() {
    for (final member in members) {
      member.send(
        Waiting(
          joined: members.length,
          players: players,
          code: code,
          custom: custom,
        ),
      );
    }
  }
}
