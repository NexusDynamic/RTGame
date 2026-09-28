import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/net/host_away.dart';

void main() {
  var now = Duration.zero;
  var exhausted = 0;
  late HostAwayTracker tracker;

  setUp(() {
    now = Duration.zero;
    exhausted = 0;
    tracker = HostAwayTracker(
      allowance: const Duration(seconds: 30),
      clock: () => now,
      onExhausted: () => exhausted++,
    );
  });
  tearDown(() => tracker.dispose());

  void advance(int seconds) {
    now += Duration(seconds: seconds);
    tracker.check();
  }

  test('counts down only while the host is away', () {
    expect(tracker.remaining.value, isNull);
    tracker.hostAway(true);
    advance(10);
    expect(tracker.remaining.value, const Duration(seconds: 20));
    tracker.hostAway(false);
    expect(tracker.remaining.value, isNull);
    advance(100);
    expect(exhausted, 0);
  });

  test('the allowance is shared by every pause in the match', () {
    tracker.hostAway(true);
    advance(20);
    tracker.hostAway(false);
    advance(60);
    tracker.hostAway(true);
    expect(tracker.remaining.value, const Duration(seconds: 10));
    advance(10);
    expect(exhausted, 1);
  });

  test('fires once, and ignores the host after that', () {
    tracker.hostAway(true);
    advance(31);
    advance(5);
    tracker
      ..hostAway(false)
      ..hostAway(true);
    advance(60);
    expect(exhausted, 1);
  });

  test('repeated reports of the same state change nothing', () {
    tracker.hostAway(true);
    advance(10);
    tracker.hostAway(true); // must not restart the clock
    advance(10);
    expect(tracker.remaining.value, const Duration(seconds: 10));
    tracker
      ..hostAway(false)
      ..hostAway(false);
    expect(tracker.remaining.value, isNull);
  });
}
