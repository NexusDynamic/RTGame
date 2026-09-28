import 'package:rise_together_game/src/net/player_assignment.dart';

/// Who is playing, and on which team.
///
/// Pure bookkeeping — no session, no broadcasting. The coordinator owns one of
/// these and publishes changes; participants replace theirs wholesale from the
/// `player_assignments` broadcast. Splitting it out makes team balancing and
/// the start precondition testable without standing up a network.
class PlayerRoster {
  final Map<String, PlayerAssignment> _assignments = {};

  /// Team ids in play. Two teams, always.
  static const List<int> teamIds = [0, 1];

  List<PlayerAssignment> get assignments =>
      List.unmodifiable(_assignments.values);

  Map<String, PlayerAssignment> get byNodeId => Map.unmodifiable(_assignments);

  int get length => _assignments.length;

  bool get isEmpty => _assignments.isEmpty;

  PlayerAssignment? forNode(String nodeId) => _assignments[nodeId];

  bool contains(String nodeId) => _assignments.containsKey(nodeId);

  void put(PlayerAssignment assignment) =>
      _assignments[assignment.nodeId] = assignment;

  PlayerAssignment? remove(String nodeId) => _assignments.remove(nodeId);

  void clear() => _assignments.clear();

  /// Replace the whole roster, as a participant does on each broadcast.
  void replaceAll(Map<String, PlayerAssignment> incoming) {
    _assignments
      ..clear()
      ..addAll(incoming);
  }

  /// Players per team, keyed by team id as a string.
  ///
  /// String keys because this goes straight onto the wire as
  /// `game_configuration`'s `teams` field, and JSON object keys are strings.
  Map<String, int> teamCounts() {
    final counts = <String, int>{};
    for (final assignment in _assignments.values) {
      final key = assignment.teamId.toString();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// Players on [teamId], excluding the coordinator.
  ///
  /// The coordinator is never a player, but it can still appear in a roster
  /// received from an older recording or a stale broadcast, so filtering is
  /// kept rather than assumed.
  int playerCountForTeam(int teamId) => _assignments.values
      .where((a) => a.teamId == teamId && !a.isCoordinator)
      .length;

  /// The team a joining node should go to: whichever has fewer players.
  ///
  /// Ties go to team 0, so a fresh session fills teams in a stable order
  /// rather than a run-dependent one.
  int balancedTeamFor() {
    final counts = {for (final id in teamIds) id: 0};
    for (final assignment in _assignments.values) {
      counts[assignment.teamId] = (counts[assignment.teamId] ?? 0) + 1;
    }
    return counts[0]! <= counts[1]! ? 0 : 1;
  }

  /// Whether there are enough players to begin: at least one, anywhere.
  ///
  /// Deliberately **or**, not **and** — a session with everyone on one team
  /// can start. Confirmed intentional: teams are assigned manually for real
  /// sessions, and the permissive check is what makes solo testing possible.
  /// An earlier comment claimed "at least one player per team", which the code
  /// never did.
  bool canStart() => playerCountForTeam(0) > 0 || playerCountForTeam(1) > 0;

  /// Serialised form for the `player_assignments` broadcast.
  Map<String, dynamic> toWire() =>
      _assignments.map((k, v) => MapEntry(k, v.toMap()));

  @override
  String toString() =>
      'PlayerRoster(${_assignments.length} assigned, teams=${teamCounts()})';
}
