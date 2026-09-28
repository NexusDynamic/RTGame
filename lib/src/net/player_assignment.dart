/// Which team and player slot a node occupies.
///
/// Sent by the authority as part of the roster; each peer looks itself up by
/// node id.
class PlayerAssignment {
  final String nodeId;
  final String nodeName;
  final int teamId;
  final String playerId;
  final bool isCoordinator;

  PlayerAssignment({
    required this.nodeId,
    required this.nodeName,
    required this.teamId,
    required this.playerId,
    required this.isCoordinator,
  });

  Map<String, dynamic> toMap() => {
    'nodeId': nodeId,
    'nodeName': nodeName,
    'teamId': teamId,
    'playerId': playerId,
    'isCoordinator': isCoordinator,
  };

  /// Longest id or display name accepted from the network.
  static const int maxStringLength = 64;

  /// Decode a roster entry received from the network.
  ///
  /// Returns null unless every field is present, correctly typed and within
  /// bounds: the roster comes from another peer and is not trusted.
  static PlayerAssignment? tryFromMap(Object? map) {
    if (map is! Map<String, dynamic>) return null;
    final nodeId = map['nodeId'];
    final nodeName = map['nodeName'];
    final teamId = map['teamId'];
    final playerId = map['playerId'];
    final isCoordinator = map['isCoordinator'];
    bool validString(Object? v) =>
        v is String && v.isNotEmpty && v.length <= maxStringLength;
    if (!validString(nodeId) || !validString(playerId)) return null;
    if (nodeName is! String || nodeName.length > maxStringLength) return null;
    if (teamId != 0 && teamId != 1) return null;
    if (isCoordinator is! bool) return null;
    return PlayerAssignment(
      nodeId: nodeId as String,
      nodeName: nodeName,
      teamId: teamId as int,
      playerId: playerId as String,
      isCoordinator: isCoordinator,
    );
  }

  @override
  String toString() =>
      'PlayerAssignment($nodeName team=$teamId player=$playerId'
      '${isCoordinator ? ' coordinator' : ''})';
}
