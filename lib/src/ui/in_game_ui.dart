import 'package:flame/image_composition.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/models/team.dart';
import 'package:rise_together_game/src/attributes/team_color_provider.dart';
import 'package:rise_together_game/src/models/team_context.dart';
import 'package:rise_together_game/src/ui/overlay.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/game/distance_tracker.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';

/// Which on-screen thrust buttons are held, per player.
class ButtonStateController extends ChangeNotifier {
  final Map<String, PaddleAction> _activeActions = {};

  PaddleAction getPlayerAction(String playerId) {
    return _activeActions[playerId] ?? PaddleAction.none;
  }

  void setPlayerAction(String playerId, PaddleAction action) {
    if (_activeActions[playerId] != action) {
      _activeActions[playerId] = action;
      notifyListeners();
    }
  }

  void clearPlayerAction(String playerId) {
    if (_activeActions.containsKey(playerId)) {
      _activeActions.remove(playerId);
      notifyListeners();
    }
  }

  /// Clear all player actions and return list of affected players (for sending NONE actions)
  List<String> clearAllPlayerActionsAndGetAffected() {
    final affectedPlayers = _activeActions.keys
        .where((playerId) => _activeActions[playerId] != PaddleAction.none)
        .toList();

    if (_activeActions.isNotEmpty) {
      _activeActions.clear();
      notifyListeners();
    }

    return affectedPlayers;
  }

  bool isPlayerActionActive(String playerId, PaddleAction action) {
    return _activeActions[playerId] == action;
  }
}

class InGameUI extends StatelessWidget
    with AppLogging, AppSettings, TeamColorProvider
    implements RiseTogetherOverlay {
  static final String overlayID = 'inGameUI';
  final RiseTogetherGameBase game;
  final ButtonStateController _buttonController = ButtonStateController();

  InGameUI(this.game, {super.key});

  /// Clear UI button states for current player when ball hits wall
  void clearCurrentPlayerUIActions() {
    final currentAssignment = game.currentPlayerAssignment;
    if (currentAssignment == null) return;

    final playerId = currentAssignment.playerId;
    final teamId = currentAssignment.teamId;

    // Get affected players from UI controller and send NONE actions
    final affectedPlayers = _buttonController
        .clearAllPlayerActionsAndGetAffected();

    // Send NONE actions for any buttons that were pressed
    for (final affectedPlayerId in affectedPlayers) {
      if (affectedPlayerId == playerId) {
        _sendAction(teamId, playerId, PaddleAction.none);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return ChangeNotifierProvider.value(
      value: _buttonController,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            _buildTimeDisplay(context, screenWidth, screenHeight),
            _buildTeamControls(context, screenWidth, screenHeight),
            _buildPlayerInputIndicators(context, screenWidth, screenHeight),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeDisplay(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    final currentPlayerTeamId = _getCurrentPlayerTeamId();
    const timeTextLabel = Text(
      'Time Remaining',
      textAlign: TextAlign.center,
      style: TextStyle(
        backgroundColor: Color.fromARGB(150, 0, 0, 0),
        color: Color.fromARGB(200, 255, 255, 255),
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );

    // In the split view this sits on the seam between the two arenas. The
    // single view has no seam, so it goes to the top margin -- the bottom is
    // where the thrust buttons live.
    return Positioned(
      top: (game.singleViewOpponent || !game.verticalOrientation) ? 10 : null,
      bottom: (game.singleViewOpponent || !game.verticalOrientation)
          ? null
          : screenHeight * 0.5,
      width: screenWidth,
      child: Center(
        child: Stack(
          children: [
            ChangeNotifierProvider.value(
              value: game.timeProvider,
              builder: (ctx, _) => Center(
                child: Column(
                  children: [
                    timeTextLabel,
                    Text(
                      Provider.of<TimeProvider>(ctx).formattedTime,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        backgroundColor: Color.fromARGB(150, 0, 0, 0),
                        color: Color.fromARGB(255, 255, 255, 255),
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Distance Display
            ChangeNotifierProvider.value(
              value: game.distanceTracker,
              builder: (ctx, _) {
                final distanceTracker = Provider.of<DistanceTracker>(ctx);
                final leftTeamId = game
                    .worldControllers[TeamDisplayPosition.left]!
                    .teamContext
                    .teamId;
                final leftTeamColor = game
                    .worldControllers[TeamDisplayPosition.left]!
                    .teamContext
                    .baseColor
                    .brighten(0.2);
                final rightTeamId = game
                    .worldControllers[TeamDisplayPosition.right]!
                    .teamContext
                    .teamId;
                final rightTeamColor = game
                    .worldControllers[TeamDisplayPosition.right]!
                    .teamContext
                    .baseColor;
                final leftDistance = distanceTracker.getFormattedDistance(
                  leftTeamId,
                  includeUnit: true,
                );
                final rightDistance = distanceTracker.getFormattedDistance(
                  rightTeamId,
                  includeUnit: true,
                );

                final leftScoreText = Text(
                  currentPlayerTeamId == leftTeamId
                      ? 'Your Peak'
                      : 'Opponent Peak',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    backgroundColor: Color.fromARGB(150, 0, 0, 0),
                    color: leftTeamColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                );

                final rightScoreText = Text(
                  currentPlayerTeamId == rightTeamId
                      ? 'Your Peak'
                      : 'Opponent Peak',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    backgroundColor: Color.fromARGB(150, 0, 0, 0),
                    color: rightTeamColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                );

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        leftScoreText,
                        Text(
                          leftDistance,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            backgroundColor: Color.fromARGB(150, 0, 0, 0),
                            color: Color.fromARGB(255, 255, 255, 255),
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        rightScoreText,
                        Text(
                          rightDistance,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            backgroundColor: Color.fromARGB(150, 0, 0, 0),
                            color: Color.fromARGB(255, 255, 255, 255),
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamControls(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    return Positioned.fill(
      child: Stack(
        children: [
          ..._buildCurrentPlayerControlsPositioned(screenWidth, screenHeight),
        ],
      ),
    );
  }

  List<Widget> _buildCurrentPlayerControlsPositioned(
    double screenWidth,
    double screenHeight,
  ) {
    // Get button height from settings (0.0 = bottom, 1.0 = top)
    final buttonRadius = appSettings.getDouble('ui.button_radius');
    final buttonHeightFraction = appSettings.getDouble('ui.button_height');
    // Convert to bottom position (0.5 means 50% from top = 50% from bottom)
    final buttonTop = screenHeight * buttonHeightFraction - buttonRadius;

    return [
      // Current player controls - Left side
      Positioned(
        left: 20,
        top: buttonTop,
        child: _buildCurrentPlayerControls(
          side: 'left',
          screenHeight: screenHeight,
        ),
      ),
      // Current player controls - Right side
      Positioned(
        right: game.verticalOrientation ? 20 : screenWidth / 2 + 20,
        top: buttonTop,
        child: _buildCurrentPlayerControls(
          side: 'right',
          screenHeight: screenHeight,
        ),
      ),
    ];
  }

  Widget _buildCurrentPlayerControls({
    required String side,
    required double screenHeight,
  }) {
    final currentPlayerTeamId = _getCurrentPlayerTeamId();
    final currentPlayerTeam = Team.fromId(currentPlayerTeamId);
    final currentPlayerId = game.currentPlayerAssignment?.nodeId ?? 'unknown';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          teamId: currentPlayerTeamId, // Always use player's assigned team
          playerId: currentPlayerId,
          action: side == 'left' ? PaddleAction.left : PaddleAction.right,
          icon: Icons.arrow_upward,
          color: getTeamColorWithOpacity(currentPlayerTeam, 0.8),
          size: appSettings.getDouble('ui.button_radius') * 2,
        ),
        const SizedBox(height: 10),
        Text(
          side == 'left' ? 'inGame.liftLeft'.tr() : 'inGame.liftRight'.tr(),
          style: const TextStyle(
            color: Color.fromARGB(150, 255, 255, 255),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            backgroundColor: Color.fromARGB(150, 0, 0, 0),
          ),
        ),
      ],
    );
  }

  int _getCurrentPlayerTeamId() {
    return game.currentPlayerAssignment?.teamId ?? Team.a.id;
  }

  Widget _buildActionButton({
    required int teamId,
    required String playerId,
    required PaddleAction action,
    required IconData icon,
    required Color color,
    double size = 40,
  }) {
    return Consumer<ButtonStateController>(
      builder: (context, controller, child) {
        final isActive = controller.isPlayerActionActive(playerId, action);
        final effectiveColor = isActive ? color : color.withValues(alpha: 0.5);

        return Listener(
          onPointerDown: (_) =>
              _handleActionPress(teamId, playerId, action, controller),
          onPointerPanZoomStart: (_) =>
              _handleActionPress(teamId, playerId, action, controller),
          onPointerPanZoomEnd: (_) =>
              _handleActionRelease(teamId, playerId, action, controller),
          onPointerUp: (_) =>
              _handleActionRelease(teamId, playerId, action, controller),
          onPointerCancel: (_) =>
              _handleActionRelease(teamId, playerId, action, controller),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: effectiveColor,
              shape: BoxShape.circle,
              border: isActive
                  ? Border.all(
                      color: Color.fromARGB(255, 255, 255, 255),
                      width: 2,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Color.fromARGB(150, 0, 0, 0),
                  spreadRadius: 2,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Color.fromARGB(255, 255, 255, 255),
              size: size * 0.6,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  void _handleActionPress(
    int teamId,
    String playerId,
    PaddleAction action,
    ButtonStateController controller,
  ) {
    // Set the action in the controller (this will clear any other action for this player)
    controller.setPlayerAction(playerId, action);
    _sendAction(teamId, playerId, action);
  }

  void _handleActionRelease(
    int teamId,
    String playerId,
    PaddleAction action,
    ButtonStateController controller,
  ) {
    if (controller.getPlayerAction(playerId) != action) {
      // If the action has changed (e.g. from left to right), do not clear
      return;
    }
    // Clear the action in the controller
    controller.clearPlayerAction(playerId);
    // Send none action to the game
    _sendAction(teamId, playerId, PaddleAction.none);
  }

  Widget _buildPlayerInputIndicators(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    return Positioned.fill(
      child: ChangeNotifierProvider.value(
        value: game.bitflagsNotifier,
        child: Consumer<BitflagsNotifier>(
          builder: (context, bitflags, child) {
            return Stack(
              children: [
                // Left team indicators
                _buildTeamInputIndicators(
                  teamId: game
                      .worldControllers[TeamDisplayPosition.left]!
                      .teamContext
                      .teamId,
                  screenWidth: screenWidth,
                  screenHeight: screenHeight,
                  isLeftSide: true,
                ),
                // Right team indicators
                _buildTeamInputIndicators(
                  teamId: game
                      .worldControllers[TeamDisplayPosition.right]!
                      .teamContext
                      .teamId,
                  screenWidth: screenWidth,
                  screenHeight: screenHeight,
                  isLeftSide: false,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTeamInputIndicators({
    required int teamId,
    required double screenWidth,
    required double screenHeight,
    required bool isLeftSide,
  }) {
    final leftBitflags = game.getTeamLeftBitflags(teamId);
    final rightBitflags = game.getTeamRightBitflags(teamId);
    final allPlayers = game.playerBitFlagsList;

    final teamPlayers = allPlayers.where((p) => p['teamId'] == teamId).toList();
    if (teamPlayers.isEmpty) return SizedBox.shrink();

    // Single view: the opponent has no arena of their own for their press
    // indicators to sit under, and a floating row of their presses reads as
    // belonging to the player's paddle. The ghost and the edge cue carry the
    // opponent instead.
    if (game.singleViewOpponent && !isLeftSide) return SizedBox.shrink();

    // Calculate positions - indicators go under the paddles (around 60% down)
    final teamWidth = game.verticalOrientation ? screenWidth : screenWidth / 2;
    final leftOffset = game.verticalOrientation
        ? 0.0
        : isLeftSide
        ? 0.0
        : screenWidth / 2;
    final indicatorY = game.singleViewOpponent
        ? screenHeight * 0.6
        : game.verticalOrientation
        ? isLeftSide
              ? screenHeight * 0.3
              : screenHeight * 0.8
        : screenHeight * 0.6; // Under the paddles

    return Positioned(
      left: leftOffset,
      top: indicatorY,
      width: teamWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Left paddle bar
          _buildPaddleBar(
            teamPlayers: teamPlayers,
            activeBitflags: leftBitflags,
          ),
          SizedBox(width: 20), // Space between left and right sides
          // Right paddle bar
          _buildPaddleBar(
            teamPlayers: teamPlayers,
            activeBitflags: rightBitflags,
          ),
        ],
      ),
    );
  }

  Widget _buildPaddleBar({
    required List<Map<String, dynamic>> teamPlayers,
    required int activeBitflags,
  }) {
    if (teamPlayers.isEmpty) {
      return SizedBox(width: 80, height: 16);
    }

    const paddleWidth = 80.0;
    const paddleHeight = 16.0;
    const segmentSpacing = 1.0;

    final segmentWidth =
        (paddleWidth - (teamPlayers.length - 1) * segmentSpacing) /
        teamPlayers.length;

    return Container(
      width: paddleWidth,
      height: paddleHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            spreadRadius: 1,
            blurRadius: 3,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: teamPlayers.asMap().entries.map((entry) {
            final index = entry.key;
            final player = entry.value;
            final playerBitflag = player['bitflagValue'] as int;
            final playerIndex = player['index'] as int;
            final playerColor = game.getPlayerColor(playerIndex);

            // Check if this player is currently pressing this direction
            final isActive = activeBitflags & playerBitflag != 0;
            final opacity = isActive ? 1.0 : 0.3;

            return Container(
              width: segmentWidth,
              height: paddleHeight,
              margin: EdgeInsets.only(
                right: index < teamPlayers.length - 1 ? segmentSpacing : 0,
              ),
              decoration: BoxDecoration(
                color: playerColor.withValues(alpha: opacity),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _sendAction(int teamId, String playerId, PaddleAction action) {
    game.sendAction(teamId, playerId, action);
  }
}
