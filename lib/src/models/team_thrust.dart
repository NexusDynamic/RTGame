/// Aggregated thrust data for a team
class TeamThrust {
  final double leftThrust;
  final double rightThrust;
  final double netThrust;
  final int activePlayerCount;
  final int leftBitflags;
  final int rightBitflags;

  const TeamThrust({
    required this.leftThrust,
    required this.rightThrust,
    required this.activePlayerCount,
    this.leftBitflags = 0,
    this.rightBitflags = 0,
  }) : netThrust = rightThrust - leftThrust;

  @override
  String toString() =>
      'TeamThrust(left: $leftThrust, right: $rightThrust, net: $netThrust, players: $activePlayerCount, leftBits: $leftBitflags, rightBits: $rightBitflags)';
}
