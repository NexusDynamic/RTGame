import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/net/physics_state_broadcaster.dart';

/// Tests for the highest-frequency decision in the system.
///
/// The first group is the direct regression suite for the 1v1 blackout: the
/// broadcaster was gated on a flag that one code path never set, so zero
/// samples went out while inputs kept flowing and logging. Nothing asserted
/// that anything was ever actually sent.
///
/// The throttling group covers a second, quieter failure: the rate limit used
/// to read a wall clock, which halved the recorded rate whenever the fixed-step
/// pump ran more than one step per timer callback. See
/// `docs/handoff/2026-08-14-session-findings.md`.
void main() {
  late List<List<double>> sent;
  late bool playing;

  /// One simulation step at the configured 120 Hz tick.
  const tick = 1 / 120;

  PhysicsStateBroadcaster build({int minIntervalMs = 8}) {
    sent = [];
    return PhysicsStateBroadcaster(
      sendSample: sent.add,
      isPlaying: () => playing,
      minIntervalMs: minIntervalMs,
    );
  }

  List<double> sample([double v = 1]) => List.filled(16, v);

  setUp(() => playing = true);

  group('arming', () {
    test('sends nothing until started', () {
      final b = build()..setProvider(sample);

      expect(b.broadcastOnChange(tick), isFalse);
      expect(
        sent,
        isEmpty,
        reason:
            'this exact gate, left unset by the 1v1 path, made the '
            'coordinator send zero physics samples for a whole round',
      );
    });

    test('sends once started', () {
      final b = build()
        ..setProvider(sample)
        ..start();

      expect(b.broadcastOnChange(tick), isTrue);
      expect(sent, hasLength(1));
      expect(b.sentCount, equals(1));
    });

    test('stop halts sending', () {
      final b = build()
        ..setProvider(sample)
        ..start();
      b.broadcastOnChange(tick);
      b.stop();

      expect(b.broadcastOnChange(tick), isFalse);
      expect(sent, hasLength(1));
    });

    test('reset disarms and drops the provider', () {
      final b = build()
        ..setProvider(sample)
        ..start();
      b.reset();

      expect(b.isEnabled, isFalse);
      expect(b.hasProvider, isFalse);
      expect(b.broadcastOnChange(tick), isFalse);
    });
  });

  group('preconditions', () {
    test('no provider means nothing to send', () {
      final b = build()..start();
      expect(b.broadcastOnChange(tick), isFalse);
    });

    test('a paused game suppresses sending', () {
      final b = build()
        ..setProvider(sample)
        ..start();
      playing = false;

      expect(b.broadcastOnChange(tick), isFalse);
      expect(sent, isEmpty);
    });

    test('a provider returning null is a normal no-op', () {
      // "Nothing changed" — not a failure.
      final b = build()
        ..setProvider(() => null)
        ..start();

      expect(b.broadcastOnChange(tick), isFalse);
      expect(sent, isEmpty);
    });
  });

  group('throttling', () {
    test('every step at the configured tick is sent', () {
      // The regression this file's second failure was about. At 120 Hz the
      // step period (8.33 ms) sits just above the 8 ms limit, so every step
      // must go out — a full-resolution record of the simulation.
      final b = build()
        ..setProvider(sample)
        ..start();

      for (var i = 0; i < 120; i++) {
        b.broadcastOnChange(tick);
      }

      expect(sent, hasLength(120));
    });

    test('steps taken back-to-back in one callback are all sent', () {
      // The actual 2026-08-14 defect. The pump earns steps from real elapsed
      // time and runs however many it owes per timer callback: on a Pi
      // delivering ~60 callbacks a second it ran two 8.33 ms steps microseconds
      // apart in wall time. A wall-clock throttle dropped the second one every
      // time, so a 120 Hz simulation was recorded and transmitted at 60 Hz.
      // Simulated time cannot see the difference, which is the point.
      final b = build()
        ..setProvider(sample)
        ..start();

      // Two callbacks, two steps each, no wall time passing at all.
      b.broadcastOnChange(tick);
      b.broadcastOnChange(tick);
      b.broadcastOnChange(tick);
      b.broadcastOnChange(tick);

      expect(sent, hasLength(4));
    });

    test('sub-interval steps are rate limited', () {
      // A tick faster than the limit must still be capped: the limit exists to
      // bound what goes on the wire.
      final b = build(minIntervalMs: 8)
        ..setProvider(sample)
        ..start();

      const fastTick = 1 / 1000; // 1 ms steps
      for (var i = 0; i < 40; i++) {
        b.broadcastOnChange(fastTick);
      }

      // First step sends immediately, then one per 8 ms of simulated time.
      expect(sent, hasLength(5));
    });

    test('a zero interval lets every call through', () {
      final b = build(minIntervalMs: 0)
        ..setProvider(sample)
        ..start();

      for (var i = 0; i < 5; i++) {
        b.broadcastOnChange(tick);
      }

      expect(sent, hasLength(5));
    });

    test('the throttle only resets on an actual send', () {
      // A long quiet period (provider returning null) must not leave the next
      // real change waiting out a stale interval.
      List<double>? next;
      final b = build(minIntervalMs: 20)
        ..setProvider(() => next)
        ..start();

      next = sample();
      expect(b.broadcastOnChange(tick), isTrue);

      next = null;
      for (var i = 0; i < 10; i++) {
        b.broadcastOnChange(tick);
      }

      next = sample(2);
      expect(
        b.broadcastOnChange(tick),
        isTrue,
        reason: 'simulated time accumulated across the quiet period',
      );
      expect(sent, hasLength(2));
    });

    test('the default interval is the ~120Hz ceiling', () {
      expect(PhysicsStateBroadcaster.defaultMinIntervalMs, equals(8));
    });
  });

  group('sample delivery', () {
    test('the provider value is handed through unchanged', () {
      final payload = sample(7);
      final b = build(minIntervalMs: 0)
        ..setProvider(() => payload)
        ..start();

      b.broadcastOnChange(tick);

      expect(sent.single, equals(payload));
    });

    test('sentCount tracks only real sends', () {
      final b = build(minIntervalMs: 1000)
        ..setProvider(sample)
        ..start();

      for (var i = 0; i < 10; i++) {
        b.broadcastOnChange(tick);
      }

      expect(b.sentCount, equals(1));
    });
  });
}
