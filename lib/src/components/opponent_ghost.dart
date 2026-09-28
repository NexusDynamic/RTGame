import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/game/game_geometry.dart';
import 'package:rise_together_game/src/game/opponent_view.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/models/team_context.dart';

/// Desaturate to luminance and drop to [_ghostOpacity].
///
/// The alpha scale lives in the matrix rather than in `paint.color` so the two
/// halves of the treatment cannot drift apart: a `paint.color` alpha applies
/// to `drawImage` but not to a `drawRect`, which would have left the ghost
/// ball and the ghost paddle at different opacities.
const double _ghostOpacity = 0.35;

const ColorFilter _ghostFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, _ghostOpacity, 0, //
]);

/// The opponent's ball and paddle, drawn inside the player's own arena.
///
/// Mounted on the player's world when `ui.single_view_opponent` is on. It owns
/// no physics: it is a plain [PositionComponent] that copies the opponent
/// world's body transforms every frame. That single source is correct in every
/// deployment mode, because the opponent world's bodies are already maintained
/// on every device -- authoritatively on a coordinator, and by
/// `_interpolatePhysicsState` (which iterates *both* world controllers) on a
/// follower. Nothing here touches the network.
///
/// It sits at the world origin with no transform, so its children's positions
/// are world coordinates directly. [priority] 0 puts it behind [Ball] and
/// [Paddle], which are both priority 1.
class OpponentGhost extends PositionComponent
    with HasGameRef<RiseTogetherGameBase> {
  OpponentGhost() : super(priority: 0);

  late final SpriteComponent _ball;
  late final RectangleComponent _paddle;

  /// Set by individual mode, where there is no opponent to show.
  ///
  /// The split-screen build blacks the opponent's viewport out instead
  /// (`RiseTogetherWorld.blackout`); with no second viewport to black out,
  /// this is the equivalent lever.
  bool suppressed = false;

  /// Cached so the paddle rectangle is only re-sized when an obstacle actually
  /// changes the opponent's width, not on every frame.
  double _lastWidthMultiplier = double.nan;

  /// Whether the ghost is drawn this frame. Gates [renderTree] rather than
  /// removing the component, so the sprite and rectangle stay allocated across
  /// the level transitions that happen mid-round every time a team finishes a
  /// level.
  bool _visible = false;

  @override
  Future<void> onLoad() async {
    // ball.png is already in the cache -- RiseTogetherGameBase.onLoad() loads
    // it before either world is built.
    _ball = SpriteComponent(
      sprite: Sprite(gameRef.images.fromCache('assets/images/ball.png')),
      size: Vector2.all(GameGeometry.ballRadius * 2),
      anchor: Anchor.center,
    )..paint = (Paint()..colorFilter = _ghostFilter);

    _paddle = RectangleComponent(
      size: Vector2(
        GameGeometry.paddleHalfWidth * 2,
        GameGeometry.paddleThickness,
      ),
      anchor: Anchor.center,
      paint: Paint()
        ..color = const Color(0xFFB0B0B0)
        ..colorFilter = _ghostFilter
        ..style = PaintingStyle.fill,
    );

    // Unfiltered light outlines. The greyed, 35% ghost alone all but vanishes
    // over a control-reversal zone's yellow/black stripe.
    _ball.add(
      CircleComponent(radius: GameGeometry.ballRadius, paint: _outlinePaint()),
    );
    _paddleOutline = RectangleComponent(
      size: _paddle.size,
      paint: _outlinePaint(),
    );
    _paddle.add(_paddleOutline);

    addAll([_ball, _paddle]);
  }

  late final RectangleComponent _paddleOutline;

  static Paint _outlinePaint() => Paint()
    ..color = const Color(0x99FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = GameGeometry.ballRadius * 0.25;

  @override
  void update(double dt) {
    super.update(dt);

    final mine = gameRef.worldControllers[TeamDisplayPosition.left];
    final opp = gameRef.worldControllers[TeamDisplayPosition.right];
    if (mine == null || opp == null) {
      _visible = false;
      return;
    }

    _visible =
        !suppressed &&
        OpponentView.shouldShowGhost(
          myLevelIndex: mine.currentLevelIndex,
          oppLevelIndex: opp.currentLevelIndex,
        );
    if (!_visible) return;

    final oppWorld = opp.world;
    if (!oppWorld.ball.isMounted || !oppWorld.paddle.isMounted) return;

    _ball.position.setFrom(oppWorld.ball.body.position);
    _ball.angle = oppWorld.ball.body.angle;

    // x is pinned at 0 for both teams' paddles; only y and angle move.
    _paddle.position.setValues(0, oppWorld.paddle.body.position.y);
    _paddle.angle = oppWorld.paddle.body.angle;

    final multiplier = oppWorld.paddle.widthMultiplier;
    if (multiplier != _lastWidthMultiplier) {
      _lastWidthMultiplier = multiplier;
      _paddle.size.setValues(
        GameGeometry.paddleHalfWidth * 2 * multiplier,
        GameGeometry.paddleThickness,
      );
      _paddleOutline.size.setFrom(_paddle.size);
    }
  }

  @override
  void renderTree(Canvas canvas) {
    if (!_visible) return;
    super.renderTree(canvas);
  }
}
