import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/rise_together_game.dart';

void main() {
  test('a timed round counts down and completes', () {
    final time = TimeProvider()..initialize(10);
    time.updateTime(4);
    expect(time.isTimed, isTrue);
    expect(time.formattedTime, '00:06');
    time.updateTime(7);
    expect(time.isComplete, isTrue);
    expect(time.elapsedTime, 10);
  });

  test('an untimed run counts up and never completes', () {
    final time = TimeProvider()..initialize(null);
    expect(time.isTimed, isFalse);
    expect(time.formattedTime, '00:00');
    for (var i = 0; i < 100; i++) {
      time.updateTime(36.5);
    }
    expect(time.isComplete, isFalse);
    expect(time.elapsedTime, closeTo(3650, 1e-6));
    expect(time.formattedTime, '60:50');

    time.reset();
    expect(time.elapsedTime, 0);
    expect(time.isTimed, isFalse);
  });

  test('untimed only notifies when the shown second changes', () {
    final time = TimeProvider()..initialize(null);
    var notified = 0;
    time.addListener(() => notified++);
    for (var i = 0; i < 60; i++) {
      time.updateTime(1 / 60);
    }
    // 00:00 once, then 00:01 once the full second has passed.
    expect(notified, lessThanOrEqualTo(2));
  });
}
