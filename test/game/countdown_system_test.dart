import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/game/countdown_system.dart';
import '../helpers/test_helpers.dart';

void main() {
  setUpAll(() {
    silenceLogs();
  });
  group('CountdownSystem', () {
    test('runCompletion resolves when a countdown is cancelled', () async {
      // Regression: cancel() used to notify listeners but never release
      // completion waiters. RiseTogetherWorld.restartLevel() awaits that
      // signal, so a superseding countdown left _isRestartingLevel stuck true
      // and silently disabled every restart for the rest of the session.
      final system = CountdownSystem();
      addTearDown(system.dispose);

      unawaited(system.startCountdown());
      final completion = system.runCompletion;

      system.cancel();

      await completion.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('cancel() did not release runCompletion'),
      );
      expect(system.isActive, isFalse);
    });

    test('registered onComplete callbacks fire on cancel', () async {
      final system = CountdownSystem();
      addTearDown(system.dispose);

      var fired = false;
      system.onComplete(() => fired = true);

      unawaited(system.startCountdown());
      system.cancel();

      expect(fired, isTrue);
    });

    test(
      'superseding a countdown does not release the new run early',
      () async {
        // startCountdown() cancels any in-flight countdown. That cancel must
        // release the *old* run's waiters only — releasing the new run's would
        // make the caller skip a countdown it just asked for.
        final system = CountdownSystem();
        addTearDown(system.dispose);

        unawaited(system.startCountdown());
        final firstRun = system.runCompletion;

        // Supersede it.
        unawaited(system.startCountdown());
        final secondRun = system.runCompletion;

        // First run released by the supersede.
        await firstRun.timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('superseded run was never released'),
        );

        // Second run is still pending — it only just started.
        var secondResolved = false;
        unawaited(secondRun.then((_) => secondResolved = true));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          secondResolved,
          isFalse,
          reason: 'new run was released by the cancel that superseded the old',
        );
      },
    );

    test('dispose stops the periodic timer', () async {
      // The contract RiseTogetherGameBase.onRemove() relies on. The defect was
      // at the call site, not here — see game_teardown_test.dart — but a
      // dispose() that stopped releasing the timer would put it back.
      var los = 0;
      final system = CountdownSystem(
        onPlayLo: () async => los++,
        onPlayHi: () async {},
      );

      unawaited(system.startCountdown());
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(los, greaterThan(0), reason: 'countdown never started ticking');

      system.dispose();
      final afterDispose = los;
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(los, afterDispose, reason: 'timer kept ticking after dispose');
    });

    test('dispose releases a pending runCompletion', () async {
      final system = CountdownSystem();
      final run = system.startCountdown().then((_) => system.runCompletion);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      system.dispose();
      await run.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('dispose left restartLevel awaiting forever'),
      );
    });

    test('a callback removing itself during notify does not throw', () async {
      final system = CountdownSystem();
      addTearDown(system.dispose);

      late final void Function() cb;
      cb = () => system.removeOnComplete(cb);
      system.onComplete(cb);

      unawaited(system.startCountdown());
      expect(system.cancel, returnsNormally);
    });

    group('onUnlocked', () {
      testWidgets('fires once when a local countdown runs out', (tester) async {
        var unlocks = 0;
        final system = CountdownSystem(onUnlocked: () => unlocks++);
        addTearDown(system.dispose);

        unawaited(system.startCountdown());
        await tester.pump(const Duration(seconds: 3));
        expect(unlocks, equals(0), reason: 'still counting');

        await tester.pump(const Duration(seconds: 2));
        expect(system.isActive, isFalse);
        expect(unlocks, equals(1));
      });

      test('never fires on cancel, supersede or dispose', () async {
        var unlocks = 0;
        final system = CountdownSystem(onUnlocked: () => unlocks++);

        unawaited(system.startCountdown());
        unawaited(system.startCountdown()); // supersede-cancels the first
        system.cancel();
        system.dispose();

        expect(unlocks, equals(0));
      });

      test('fires when a mirrored countdown reaches finished', () async {
        var unlocks = 0;
        final system = CountdownSystem(onUnlocked: () => unlocks++);
        addTearDown(system.dispose);

        for (final state in [
          CountdownState.three,
          CountdownState.two,
          CountdownState.one,
          CountdownState.go,
        ]) {
          await system.setStateFromNetwork(state);
        }
        expect(unlocks, equals(0));

        await system.setStateFromNetwork(CountdownState.finished);
        await system.setStateFromNetwork(CountdownState.finished);
        expect(unlocks, equals(1), reason: 'a repeated state is not an edge');
      });
    });
  });
}
