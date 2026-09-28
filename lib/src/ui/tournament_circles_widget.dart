import 'package:flutter/material.dart';

/// Displays tournament standings as a row of circles.
///
/// Team 0 fills circles from the left; team 1 fills from the right.
/// Unfilled circles remain as grey outlines.
class TournamentCirclesWidget extends StatelessWidget {
  final int totalRounds;
  final int team0Wins;
  final int team1Wins;
  final Color team0Color;
  final Color team1Color;
  final double circleSize;
  final double spacing;

  const TournamentCirclesWidget({
    super.key,
    required this.totalRounds,
    required this.team0Wins,
    required this.team1Wins,
    this.team0Color = const Color(0xFF4FC3F7),
    this.team1Color = const Color(0xFFEF9A9A),
    this.circleSize = 28,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalRounds, (i) {
        Color? fill;
        if (i < team0Wins) {
          fill = team0Color;
        } else if (i >= totalRounds - team1Wins) {
          fill = team1Color;
        }
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing / 2),
          child: Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill ?? Colors.transparent,
              border: Border.all(
                color: fill ?? const Color(0xFF757575),
                width: 2.5,
              ),
            ),
          ),
        );
      }),
    );
  }
}
