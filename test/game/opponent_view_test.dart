import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/opponent_view.dart';

/// A view spanning y in [-50, -30] -- i.e. 20 world units of a level, well
/// above the floor. Negative-up, so `top` (-50) is the HIGHER point on screen.
const _view = Rect.fromLTRB(-5.0, -50.0, 5.0, -30.0);

/// One level's worth of climb, in the metres the distance tracker reports.
const _levelSpan = 1000.0;

void main() {
  group('shouldShowGhost', () {
    test('shows the ghost when both teams are on the same level', () {
      expect(
        OpponentView.shouldShowGhost(myLevelIndex: 2, oppLevelIndex: 2),
        isTrue,
      );
    });

    test('hides the ghost when the opponent is ahead a level', () {
      expect(
        OpponentView.shouldShowGhost(myLevelIndex: 2, oppLevelIndex: 3),
        isFalse,
      );
    });

    test('hides the ghost when the opponent is behind a level', () {
      expect(
        OpponentView.shouldShowGhost(myLevelIndex: 3, oppLevelIndex: 2),
        isFalse,
      );
    });
  });

  group('cue, same level', () {
    test('is null while the opponent is on screen', () {
      expect(
        OpponentView.cue(
          visibleWorldRect: _view,
          oppBallY: -40.0,
          levelDelta: 0,
          metresDelta: 12.0,
          levelSpanMetres: _levelSpan,
        ),
        isNull,
      );
    });

    test('points up when the opponent is above the top edge', () {
      // Negative-up: -60 is ABOVE the view's top of -50. Written the intuitive
      // way (oppBallY > top) this case returns null and the arrow never fires.
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -60.0,
        levelDelta: 0,
        metresDelta: 1000.0,
        levelSpanMetres: _levelSpan,
      );
      expect(cue, isNotNull);
      expect(cue!.up, isTrue);
    });

    test('points down when the opponent is below the bottom edge', () {
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -10.0,
        levelDelta: 0,
        metresDelta: -2000.0,
        levelSpanMetres: _levelSpan,
      );
      expect(cue, isNotNull);
      expect(cue!.up, isFalse);
    });

    test('treats the edges themselves as on screen', () {
      for (final y in [_view.top, _view.bottom]) {
        expect(
          OpponentView.cue(
            visibleWorldRect: _view,
            oppBallY: y,
            levelDelta: 0,
            metresDelta: 0.0,
            levelSpanMetres: _levelSpan,
          ),
          isNull,
          reason: 'y=$y sits exactly on an edge',
        );
      }
    });
  });

  group('cue, different level', () {
    test('always emits, even with the opponent inside the visible rect', () {
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -40.0, // squarely on screen
        levelDelta: 1,
        metresDelta: 573.0,
        levelSpanMetres: _levelSpan,
      );
      expect(cue, isNotNull);
      expect(cue!.levelDelta, 1);
    });

    test('takes direction from the level delta, not from y', () {
      // The classic case: the opponent cleared a level and restarted at its
      // floor, so their y is far BELOW the player's while they are a whole
      // level AHEAD. The arrow must follow the level.
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -2.0,
        levelDelta: 1,
        metresDelta: 573.0,
        levelSpanMetres: _levelSpan,
      );
      expect(cue!.up, isTrue);
    });

    test('points down when the opponent is a level behind', () {
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -90.0, // far above, but on an earlier level
        levelDelta: -1,
        metresDelta: -420.0,
        levelSpanMetres: _levelSpan,
      );
      expect(cue!.up, isFalse);
    });
  });

  group('label', () {
    test('omits the level field when the levels match', () {
      const cue = (up: true, levelDelta: 0, metresDelta: 573.4, intensity: 0.5);
      expect(OpponentView.label(cue), '573 m');
    });

    test('separates the level delta from the metres with a comma', () {
      const cue = (up: true, levelDelta: 1, metresDelta: 573.4, intensity: 1.0);
      expect(OpponentView.label(cue), '+1, 573 m');
    });

    test('renders a negative level delta', () {
      const cue = (
        up: false,
        levelDelta: -2,
        metresDelta: -420.0,
        intensity: 1.0,
      );
      expect(OpponentView.label(cue), '-2, 420 m');
    });

    test('shows the metre gap unsigned, leaving the sign to the arrow', () {
      const behind = (
        up: false,
        levelDelta: 0,
        metresDelta: -573.4,
        intensity: 0.5,
      );
      expect(OpponentView.label(behind), '573 m');
    });
  });

  group('intensity', () {
    test('starts near zero as the opponent slips off the edge', () {
      // Just above the top edge, and only a few metres of the level ahead.
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -50.1,
        levelDelta: 0,
        metresDelta: 10.0,
        levelSpanMetres: _levelSpan,
      );
      expect(cue!.intensity, closeTo(0.01, 1e-9));
    });

    test('reaches the top of the ramp at one level of climb', () {
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -60.0,
        levelDelta: 0,
        metresDelta: _levelSpan,
        levelSpanMetres: _levelSpan,
      );
      expect(cue!.intensity, 1.0);
    });

    test('clamps rather than overshooting past a level', () {
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -60.0,
        levelDelta: 0,
        metresDelta: _levelSpan * 4,
        levelSpanMetres: _levelSpan,
      );
      expect(cue!.intensity, 1.0);
    });

    test('is unsigned: being behind ramps as fast as being ahead', () {
      final behind = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -10.0,
        levelDelta: 0,
        metresDelta: -_levelSpan / 2,
        levelSpanMetres: _levelSpan,
      );
      expect(behind!.intensity, closeTo(0.5, 1e-9));
    });

    test('pins at the top whenever a level separates the teams', () {
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -40.0,
        levelDelta: 1,
        metresDelta: 1.0, // tiny gap, but a whole level apart
        levelSpanMetres: _levelSpan,
      );
      expect(cue!.intensity, 1.0);
    });

    test('saturates rather than dividing by zero on an unmeasurable span', () {
      // A tracker read before initialize(), or a level height of zero: the
      // ramp has no scale, so show the strongest reading rather than NaN.
      final cue = OpponentView.cue(
        visibleWorldRect: _view,
        oppBallY: -60.0,
        levelDelta: 0,
        metresDelta: 100.0,
        levelSpanMetres: 0.0,
      );
      expect(cue!.intensity, 1.0);
    });
  });

  group('colour', () {
    test('runs yellow to red as the opponent pulls ahead', () {
      const near = (up: true, levelDelta: 0, metresDelta: 5.0, intensity: 0.0);
      const far = (up: true, levelDelta: 1, metresDelta: 900.0, intensity: 1.0);
      expect(OpponentView.colour(near), OpponentView.aheadNear);
      expect(OpponentView.colour(far), OpponentView.aheadFar);
    });

    test('runs blue-green to green as the opponent drops behind', () {
      const near = (
        up: false,
        levelDelta: 0,
        metresDelta: -5.0,
        intensity: 0.0,
      );
      const far = (
        up: false,
        levelDelta: -1,
        metresDelta: -900.0,
        intensity: 1.0,
      );
      expect(OpponentView.colour(near), OpponentView.behindNear);
      expect(OpponentView.colour(far), OpponentView.behindFar);
    });

    test('interpolates between the two ends of the ramp', () {
      const mid = (up: true, levelDelta: 0, metresDelta: 500.0, intensity: 0.5);
      final colour = OpponentView.colour(mid);
      expect(colour, isNot(OpponentView.aheadNear));
      expect(colour, isNot(OpponentView.aheadFar));
      // Warming: redder and less green than the yellow end.
      expect(colour.g, lessThan(OpponentView.aheadNear.g));
    });

    test('never mixes the ahead and behind ramps', () {
      const ahead = (
        up: true,
        levelDelta: 0,
        metresDelta: 300.0,
        intensity: 0.3,
      );
      const behind = (
        up: false,
        levelDelta: 0,
        metresDelta: -300.0,
        intensity: 0.3,
      );
      expect(OpponentView.colour(ahead), isNot(OpponentView.colour(behind)));
    });
  });
}
