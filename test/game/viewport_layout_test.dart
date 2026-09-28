import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/rise_together_levels.dart';
import 'package:rise_together_game/src/game/viewport_layout.dart';
import 'package:rise_together_game/src/models/team_context.dart';

ViewportLayout _layout(
  Vector2 canvas,
  TeamDisplayPosition pos, {
  bool singleView = false,
  bool vertical = true,
}) => ViewportLayout.forTeam(
  canvas: canvas,
  pos: pos,
  singleView: singleView,
  vertical: vertical,
);

void main() {
  final canvas = Vector2(800, 600);

  group('split view, vertical', () {
    test('the player takes the top half', () {
      final l = _layout(canvas, TeamDisplayPosition.left);
      expect(l.size, Vector2(800, 300));
      expect(l.position, Vector2.zero());
    });

    test('the opponent takes the bottom half', () {
      final l = _layout(canvas, TeamDisplayPosition.right);
      expect(l.size, Vector2(800, 300));
      expect(l.position, Vector2(0, 300));
    });
  });

  test('split view, horizontal: side by side', () {
    final l = _layout(canvas, TeamDisplayPosition.right, vertical: false);
    expect(l.size, Vector2(400, 600));
    expect(l.position, Vector2(400, 0));
  });

  test('single view covers the whole canvas', () {
    final l = _layout(canvas, TeamDisplayPosition.left, singleView: true);
    expect(l.size, Vector2(800, 600));
    expect(l.position, Vector2.zero());
  });

  test('zoom fits the level width to the viewport width', () {
    final l = _layout(canvas, TeamDisplayPosition.left);
    expect(l.zoom * RiseTogetherLevel.horizontalWidth, closeTo(800, 1e-9));
  });

  test('a resized canvas gives a layout that fits it', () {
    // Regression: the viewports were sized once at load and kept that size,
    // so after a window resize the game drew partly off screen.
    final before = _layout(canvas, TeamDisplayPosition.right);
    final after = _layout(Vector2(400, 900), TeamDisplayPosition.right);
    expect(after.size, Vector2(400, 450));
    expect(after.position, Vector2(0, 450));
    expect(after.zoom, closeTo(before.zoom / 2, 1e-9));
  });
}
