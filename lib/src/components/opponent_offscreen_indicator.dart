import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/game/opponent_view.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';
import 'package:rise_together_game/src/models/team_context.dart';

/// Distance from the viewport edge to the arrow, in logical pixels.
const double _edgeInset = 32.0;

/// Half-width / height of the arrow triangle, in logical pixels.
const double _arrowHalfWidth = 17.0;
const double _arrowHeight = 22.0;

/// Gap between the arrow's base and the label.
const double _labelGap = 5.0;

/// Reports the opponent whenever they are not simply visible on screen.
///
/// Mounted on the player camera's *viewport*, not on the world: viewport
/// children render in viewport-local space, untouched by the viewfinder, so
/// this stays pinned to the screen edge while the world scrolls past. The
/// blackout rectangle built by `RiseTogetherGameBase.viewportRimGenerator` is
/// the existing example of the same placement.
///
/// It fires in two situations, both decided by [OpponentView.cue]: the
/// opponent is level-matched but off screen, or the teams are on different
/// levels, in which case the ghost is suppressed entirely and this is the only
/// thing reporting them.
///
/// Vertically it pins to whichever edge the opponent is past; horizontally it
/// tracks the opponent ball's x, so the cue points at the column they are
/// climbing rather than at the middle of the screen.
class OpponentOffscreenIndicator extends PositionComponent
    with HasGameRef<RiseTogetherGameBase> {
  OpponentOffscreenIndicator({required this.camera});

  /// The player's camera, for its visible world rect.
  final CameraComponent camera;

  /// Set by individual mode; see [OpponentGhost.suppressed].
  bool suppressed = false;

  late final TextComponent _label;
  final Paint _arrowPaint = Paint()..style = PaintingStyle.fill;

  OpponentCue? _cue;

  /// The last string handed to [_label]. `TextComponent` re-runs its layout on
  /// every assignment to `text`, so at 120 Hz an unconditional write is a
  /// per-frame text layout for a string that changes perhaps twice a second.
  String _lastLabel = '';

  /// The last colour applied. Assigning `textRenderer` re-runs the same layout
  /// that `text` does, and the ramp yields a fractionally different colour on
  /// every frame, so the intensity is quantised (see [_quantise]) and the
  /// renderer rebuilt only when the quantised colour actually moves.
  Color? _lastColour;

  @override
  Future<void> onLoad() async {
    _label = TextComponent(text: '', anchor: Anchor.topCenter);
    _applyColour(OpponentView.aheadNear);
    add(_label);
  }

  /// Snap the ramp to 24 steps: fine enough that the change reads as gradual,
  /// coarse enough that the text layout runs a couple of dozen times over a
  /// whole level rather than once a frame.
  static double _quantise(double intensity) => (intensity * 24).round() / 24;

  void _applyColour(Color colour) {
    if (colour == _lastColour) return;
    _lastColour = colour;
    _arrowPaint.color = colour;
    _label.textRenderer = TextPaint(
      style: TextStyle(
        color: colour,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        shadows: const [
          Shadow(offset: Offset(1, 1), blurRadius: 3, color: Color(0xC0000000)),
        ],
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (suppressed) {
      _cue = null;
      return;
    }

    final mine = gameRef.worldControllers[TeamDisplayPosition.left];
    final opp = gameRef.worldControllers[TeamDisplayPosition.right];
    if (mine == null ||
        opp == null ||
        !mine.world.ball.isMounted ||
        !opp.world.ball.isMounted) {
      _cue = null;
      return;
    }

    final myTeamId = mine.teamContext.teamId;
    final oppTeamId = opp.teamContext.teamId;

    final oppBall = opp.world.ball.body.position;

    // Live heights, not the high-water marks: this cue answers "where is the
    // opponent right now", and a high-water mark does not come back down when
    // the ball does -- an opponent who peaked high and then fell would keep
    // the hot colour and the large gap until the player climbed past their
    // ghost. getLiveTeamDistance still folds in the levels each team has
    // completed, so the gap stays meaningful across a level boundary, which
    // is exactly the case where the ghost is gone and this is all the player
    // has. Read directly rather than subscribing: the tracker notifies at
    // 10 Hz, and we are on the frame clock anyway.
    final metresDelta =
        gameRef.distanceTracker.getLiveTeamDistance(oppTeamId, oppBall.y) -
        gameRef.distanceTracker.getLiveTeamDistance(
          myTeamId,
          mine.world.ball.body.position.y,
        );

    _cue = OpponentView.cue(
      visibleWorldRect: camera.visibleWorldRect,
      oppBallY: oppBall.y,
      levelDelta: opp.currentLevelIndex - mine.currentLevelIndex,
      metresDelta: metresDelta,
      // One level of *my* climb: the span the ramp is measured against, in the
      // same metres the tracker reports.
      levelSpanMetres:
          mine.world.level.verticalHeight *
          gameRef.distanceTracker.distanceMultiplier,
    );

    final cue = _cue;
    if (cue == null) return;

    final text = OpponentView.label(cue);
    if (text != _lastLabel) {
      _lastLabel = text;
      _label.text = text;
    }

    _applyColour(
      OpponentView.colour((
        up: cue.up,
        levelDelta: cue.levelDelta,
        metresDelta: cue.metresDelta,
        intensity: _quantise(cue.intensity),
      )),
    );

    final size = camera.viewport.size;

    // Viewport-local x for the opponent's world x. The viewfinder is
    // anchor-centred and unrotated (see `RiseTogetherGameBase._buildCamera`),
    // so this is the whole projection. Clamped to keep the widest of the arrow
    // and the label fully on screen.
    final viewfinder = camera.viewfinder;
    final margin = math.max(_arrowHalfWidth, _label.size.x / 2) + _labelGap;
    final trackedX =
        size.x / 2 + (oppBall.x - viewfinder.position.x) * viewfinder.zoom;

    if (cue.up) {
      position.setValues(
        trackedX.clamp(margin, math.max(margin, size.x - margin)),
        _edgeInset,
      );
      _label.anchor = Anchor.topCenter;
      _label.position.setValues(0, _arrowHeight / 2 + _labelGap);
    } else {
      position.setValues(
        trackedX.clamp(margin, math.max(margin, size.x - margin)),
        size.y - _edgeInset,
      );
      _label.anchor = Anchor.bottomCenter;
      _label.position.setValues(0, -_arrowHeight / 2 - _labelGap);
    }
  }

  @override
  void render(Canvas canvas) {
    final cue = _cue;
    if (cue == null) return;

    // Local origin is the arrow's centre; the label is a child positioned
    // clear of it above or below.
    final tipY = cue.up ? -_arrowHeight / 2 : _arrowHeight / 2;
    final baseY = -tipY;
    canvas.drawPath(
      Path()
        ..moveTo(0, tipY)
        ..lineTo(-_arrowHalfWidth, baseY)
        ..lineTo(_arrowHalfWidth, baseY)
        ..close(),
      _arrowPaint,
    );
  }

  @override
  void renderTree(Canvas canvas) {
    if (_cue == null) return;
    super.renderTree(canvas);
  }
}
