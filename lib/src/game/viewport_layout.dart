import 'package:flame/components.dart' show Vector2;
import 'package:rise_together_game/src/game/rise_together_levels.dart';
import 'package:rise_together_game/src/models/team_context.dart';

/// Where on the canvas a team's camera draws, and at what zoom.
///
/// Recomputed from the canvas on every resize: Flame's `FixedSizeViewport`
/// does not follow its parent's size on its own.
class ViewportLayout {
  /// Viewport size in logical pixels.
  final Vector2 size;

  /// Viewport's top-left corner on the canvas.
  final Vector2 position;

  /// Viewfinder zoom that fits the level's width to the viewport's.
  final double zoom;

  const ViewportLayout._(this.size, this.position, this.zoom);

  /// The layout for [pos] on a canvas of [canvas].
  ///
  /// Split view: the player's team takes the first half along the long axis
  /// (the top, when [vertical]) and the opponent the second. Single view: one
  /// camera covers the whole canvas.
  factory ViewportLayout.forTeam({
    required Vector2 canvas,
    required TeamDisplayPosition pos,
    required bool singleView,
    required bool vertical,
  }) {
    final longFraction = singleView ? 1.0 : 0.5;
    final size = vertical
        ? Vector2(canvas.x, canvas.y * longFraction)
        : Vector2(canvas.x * longFraction, canvas.y);
    final offset = singleView || pos == TeamDisplayPosition.left ? 0.0 : 0.5;
    final position = vertical
        ? Vector2(0, canvas.y * offset)
        : Vector2(canvas.x * offset, 0);
    return ViewportLayout._(
      size,
      position,
      size.x / RiseTogetherLevel.horizontalWidth,
    );
  }
}
