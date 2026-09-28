import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/game/high_water_mark.dart';
import 'package:rise_together_game/src/game/opponent_view.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/game/rise_together_levels.dart';
import 'package:rise_together_game/src/models/team_context.dart';

/// Dash and gap along the line, in world units.
const double _dash = 0.30;
const double _gap = 0.22;

/// Line weight and label size in *logical pixels*; both are divided by the
/// camera zoom before use, so the mark reads the same on a phone and on an
/// iPad instead of scaling with the arena.
const double _strokePx = 2.0;
const double _fontPx = 11.0;

/// Label inset from the left wall, and its lift off the line, in pixels.
const double _labelInsetPx = 8.0;
const double _labelLiftPx = 3.0;

/// A team's previous best height, drawn as a dashed line across their arena
/// with a small caption resting on it.
///
/// Mounted in world space, so it scrolls with the level the way a wall does.
/// The y it sits at is published by [HighWaterMark] on reset and frozen in
/// between; see that class for why a live best would be useless.
///
/// One of these is mounted per team per rendered arena:
///
///  * the player's own, in the player's world, in every view and every mode;
///  * the opponent's, in the opponent's world in the split view (where the
///    player can see that arena directly), or in the player's own world in
///    single-view mode, alongside the ghost it belongs to.
///
/// The last case is the only one that can straddle a level boundary, and
/// [crossLevelAware] handles it: two teams' y are measured from their own
/// level's floor, so a mark copied across a level boundary would be drawn at
/// a height the opponent never reached. It is hidden instead, on the same
/// rule as the ghost ([OpponentView.shouldShowGhost]).
class PreviousBestLine extends PositionComponent
    with HasGameRef<RiseTogetherGameBase> {
  PreviousBestLine({
    required this.source,
    required this.label,
    required this.camera,
    this.captionOnRight = false,
    this.crossLevelAware = false,
  }) : super(priority: 0);

  /// Whose best this is.
  final TeamDisplayPosition source;

  /// The caption resting on the line.
  final String label;

  /// The camera that renders the world this is mounted in -- its zoom converts
  /// the pixel sizes above into world units.
  final CameraComponent camera;

  /// Which wall the caption sits against. The two marks can land at the same
  /// height, and in single-view mode they share an arena, so they are parked
  /// at opposite ends: the lines may overlap (they are different colours, and
  /// moving either one would misreport a height) but the words never do.
  final bool captionOnRight;

  /// See the class docs: set for the opponent's mark drawn inside the player's
  /// own arena.
  final bool crossLevelAware;

  /// Set by individual mode, where there is no opponent. Mirrors
  /// [OpponentGhost.suppressed].
  bool suppressed = false;

  final HighWaterMark _mark = HighWaterMark();
  final Paint _linePaint = Paint()..style = PaintingStyle.stroke;

  late final TextComponent _caption;

  /// Cached so the caption is only rebuilt when the colour or the zoom
  /// actually changes; assigning `textRenderer` re-runs the text layout.
  Color? _lastColour;
  double _lastZoom = double.nan;

  int _lastLevelIndex = -1;
  double _lastDistance = 0.0;

  /// The y the line is drawn at this frame, or null for nothing to draw.
  double? _lineY;

  @override
  Future<void> onLoad() async {
    _caption = TextComponent(
      text: label,
      anchor: captionOnRight ? Anchor.bottomRight : Anchor.bottomLeft,
    );
    add(_caption);
  }

  @override
  void update(double dt) {
    super.update(dt);

    _lineY = null;
    if (suppressed) return;

    final controller = gameRef.worldControllers[source];
    if (controller == null || !controller.world.ball.isMounted) return;

    if (crossLevelAware) {
      final mine = gameRef.worldControllers[TeamDisplayPosition.left];
      if (mine == null ||
          !OpponentView.shouldShowGhost(
            myLevelIndex: mine.currentLevelIndex,
            oppLevelIndex: controller.currentLevelIndex,
          )) {
        return;
      }
    }

    final teamId = controller.teamContext.teamId;

    // Two things invalidate a mark, and neither shows up in the ball's own
    // position. A level change moves the floor the y is measured from; a new
    // round starts the climb over, and shows up as the tracker's cumulative
    // distance going backwards (it only ever grows within a round).
    final distance = gameRef.distanceTracker.getTeamDistance(teamId);
    if (controller.currentLevelIndex != _lastLevelIndex ||
        distance < _lastDistance) {
      _mark.clear();
    }
    _lastLevelIndex = controller.currentLevelIndex;
    _lastDistance = distance;

    _mark.observe(
      ballY: controller.world.ball.body.position.y,
      spawnY: controller.world.ball.startPosition.y,
      resetCount: gameRef.tournamentManager.getTeamResets(teamId),
    );

    final y = _mark.mark;
    if (y == null) return;
    _lineY = y;

    final zoom = camera.viewfinder.zoom;
    final colour = controller.teamContext.baseColor.withValues(alpha: 0.8);
    if (colour != _lastColour || zoom != _lastZoom) {
      _lastColour = colour;
      _lastZoom = zoom;
      _linePaint
        ..color = colour
        ..strokeWidth = _strokePx / zoom;
      _caption.textRenderer = TextPaint(
        style: TextStyle(
          color: colour,
          fontSize: _fontPx,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(
              offset: Offset(1, 1),
              blurRadius: 2,
              color: Color(0x99000000),
            ),
          ],
        ),
      );
      // The caption is laid out in pixels and shrunk into world units, rather
      // than laid out at a world-unit font size: a fontSize of 11/zoom would
      // rasterise an 11-world-unit glyph down to nothing legible.
      _caption.scale.setAll(1 / zoom);
    }

    // Negative-up: subtracting lifts the caption clear of the line.
    const half = RiseTogetherLevel.horizontalWidth / 2;
    final inset = _labelInsetPx / zoom;
    _caption.position.setValues(
      captionOnRight ? half - inset : -half + inset,
      y - _labelLiftPx / zoom,
    );
  }

  @override
  void render(Canvas canvas) {
    final y = _lineY;
    if (y == null) return;

    const half = RiseTogetherLevel.horizontalWidth / 2;
    for (double x = -half; x < half; x += _dash + _gap) {
      final end = (x + _dash).clamp(-half, half);
      canvas.drawLine(Offset(x, y), Offset(end, y), _linePaint);
    }
  }

  @override
  void renderTree(Canvas canvas) {
    if (_lineY == null) return;
    super.renderTree(canvas);
  }
}
