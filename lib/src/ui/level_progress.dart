import 'package:flutter/material.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/models/team_context.dart';

/// A widget that displays a level progress meter
/// This is a vertical "elevator" style progress bar (similar to a scrollbar)
/// that shows how much distance the player has travelled. This will be
/// used to show and compare progress between the two teams.
class LevelProgressMeter extends StatelessWidget {
  final TeamDisplayPosition teamPos;
  final RiseTogetherGameBase game;

  const LevelProgressMeter({
    required this.game,
    this.teamPos = TeamDisplayPosition.left,
    super.key,
  }) : super();
  @override
  Widget build(BuildContext context) {
    final height =
        MediaQuery.of(context).size.height * 0.75; // 80% of screen height

    return SizedBox(
      width: 20,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 20,
            height: height,
            color: const Color.fromARGB(150, 127, 127, 127),
            child: Stack(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable:
                      game.worldControllers[teamPos]!.paddle.positionNotifier,
                  builder: (context, position, child) {
                    final progress = game.worldControllers[teamPos]!
                        .levelProgress(position);

                    return Positioned(
                      bottom: (height - (height * 0.05)) * progress,
                      left: 1,
                      child: Container(
                        width: 8,
                        height: height * 0.05,

                        color: Color.fromARGB(255, 255, 255, 255),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
