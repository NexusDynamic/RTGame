import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/high_water_mark.dart';

/// Negative-up, so climbing means going more negative. Spawn sits just above
/// the floor, as it does in the real world geometry.
const double _spawn = -0.5;

/// Well clear of the default arming band (a tenth of the level width, 1.0).
const double _high = -6.0;

/// A mark with the production defaults, driven frame by frame.
HighWaterMark _mark() => HighWaterMark();

/// Feed a run of heights at a fixed reset count.
void _fly(HighWaterMark mark, List<double> heights, {int resets = 0}) {
  for (final y in heights) {
    mark.observe(ballY: y, spawnY: _spawn, resetCount: resets);
  }
}

void main() {
  group('before the first reset', () {
    test('has no mark to draw', () {
      final mark = _mark();
      _fly(mark, [_spawn, -2.0, -4.0, _high]);
      expect(mark.mark, isNull);
    });

    test('still follows the best height', () {
      final mark = _mark();
      _fly(mark, [_spawn, -2.0, _high, -4.0]);
      expect(mark.best, _high);
    });
  });

  group('publishing', () {
    test('publishes the best reached when the ball returns to spawn', () {
      final mark = _mark();
      _fly(mark, [_spawn, -3.0, _high, -3.0, _spawn]);
      expect(mark.mark, _high);
    });

    test('publishes on a reset count change even without the teleport', () {
      // A follower whose ball is positioned from the network may never be
      // observed at spawn on the frame the reset lands.
      final mark = _mark();
      _fly(mark, [_spawn, -3.0, _high]);
      mark.observe(ballY: -3.0, spawnY: _spawn, resetCount: 1);
      expect(mark.mark, _high);
    });

    test('does not treat the very first frame as a reset', () {
      // The counter is whatever the round left it at; only a *change* counts.
      final mark = _mark();
      mark.observe(ballY: _high, spawnY: _spawn, resetCount: 7);
      expect(mark.mark, isNull);
    });

    test('ignores a best that never cleared the arming band', () {
      // Killed on the way up: a line drawn here would sit across the paddle.
      final mark = _mark();
      _fly(mark, [_spawn, -0.8, _spawn]);
      expect(mark.mark, isNull);
    });
  });

  group('staying put', () {
    test('does not follow the ball on the climb after a reset', () {
      final mark = _mark();
      _fly(mark, [_spawn, _high, _spawn]); // first attempt: best -6
      expect(mark.mark, _high);

      // Second attempt climbs straight past it. The line must not move.
      _fly(mark, [-3.0, -6.0, -9.0, -12.0]);
      expect(mark.mark, _high);
      expect(mark.best, -12.0, reason: 'the best itself still tracks');
    });

    test('publishes the improved best only at the next reset', () {
      final mark = _mark();
      _fly(mark, [_spawn, _high, _spawn]);
      _fly(mark, [-3.0, -12.0]);
      expect(mark.mark, _high);
      _fly(mark, [-3.0, _spawn]);
      expect(mark.mark, -12.0);
    });

    test('keeps the better of two attempts', () {
      final mark = _mark();
      _fly(mark, [_spawn, -12.0, _spawn]); // good attempt
      _fly(mark, [-3.0, _spawn]); // poor attempt, dies low
      expect(mark.mark, -12.0);
    });

    test('a ball bouncing at spawn height does not republish', () {
      final mark = _mark();
      _fly(mark, [_spawn, -12.0, _spawn]);
      // Resting on the paddle, jittering across the tolerance band. Nothing
      // here clears the arming band, so nothing re-arms.
      _fly(mark, [-0.4, -0.6, -0.45, -0.7, -0.5]);
      expect(mark.mark, -12.0);
    });
  });

  group('clear', () {
    test('drops the mark for a new level', () {
      final mark = _mark();
      _fly(mark, [_spawn, _high, _spawn]);
      mark.clear();
      expect(mark.mark, isNull);
      expect(mark.best, isNull);
    });

    test('ignores the old level\'s height until the ball comes home', () {
      // The level index changes a frame or two before the world is rebuilt, so
      // clear() lands while the ball is still up at the finish line. Recording
      // that would publish a mark near the ceiling of the new level.
      final mark = _mark();
      _fly(mark, [_spawn, -30.0]); // at the top of the old level
      mark.clear();
      _fly(mark, [-30.0, -29.5]); // still there while the world rebuilds
      expect(mark.best, isNull);
      _fly(mark, [_spawn, -4.0, _spawn]); // first attempt on the new level
      expect(mark.mark, -4.0);
    });

    test('re-arms cleanly, so the next attempt publishes normally', () {
      final mark = _mark();
      _fly(mark, [_spawn, _high, _spawn]);
      mark.clear();
      _fly(mark, [_spawn, -4.0, _spawn]);
      expect(mark.mark, -4.0);
    });
  });

  group('tuning', () {
    test('the arming band is configurable', () {
      final mark = HighWaterMark(armHeight: 0.2);
      _fly(mark, [_spawn, -0.9, _spawn]);
      expect(
        mark.mark,
        -0.9,
        reason: 'a 0.9 climb clears a 0.2 band, unlike the default 1.0',
      );
    });

    test('the spawn tolerance is configurable', () {
      final mark = HighWaterMark(spawnTolerance: 0.05);
      // -0.8 is 0.3 from spawn: inside the default tolerance of 0.4, outside
      // this one, so the return is not seen and nothing publishes.
      _fly(mark, [_spawn, _high, -0.8]);
      expect(mark.mark, isNull);
    });
  });
}
