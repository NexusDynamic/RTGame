import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/app_logging.dart';

/// Countdown states
enum CountdownState {
  message, // Pre-countdown message (e.g., "Level 2, Get Ready")
  three,
  two,
  one,
  go,
  finished,
}

/// Manages the countdown sequence before gameplay starts
///
/// Audio callbacks are optional to support headless mode where audio is not available.
/// Interactive mode should provide audio callbacks, while headless mode can omit them.
///
/// Supports two modes:
/// 1. Local countdown: Runs timer locally (for single player or coordinator)
/// 2. Network-synchronized: State is updated externally via setStateFromNetwork()
class CountdownSystem extends ChangeNotifier with AppLogging {
  CountdownState _currentState = CountdownState.finished;
  Timer? _timer;
  final List<VoidCallback> _onCompleteCallbacks = [];
  bool _networkManaged =
      false; // True when countdown is managed by network coordinator

  /// Optional audio callbacks (for interactive mode)
  final Future<void> Function()? onPlayLo;
  final Future<void> Function()? onPlayHi;

  /// Called the moment a countdown runs out and input unlocks — locally after
  /// GO, or when the coordinator's mirrored countdown reaches finished.
  ///
  /// Not called by [cancel]: a cancel is usually a supersede, with the next
  /// countdown starting in the same breath, and nothing actually unlocked.
  final VoidCallback? onUnlocked;

  CountdownSystem({this.onPlayLo, this.onPlayHi, this.onUnlocked});

  /// Optional message to display before countdown
  String? _message;

  /// Current countdown state
  CountdownState get currentState => _currentState;

  /// Whether countdown is currently active
  bool get isActive => _currentState != CountdownState.finished;

  /// Current message (if in message state)
  String? get message => _message;

  /// Completes when the *current* countdown run ends — whether it reaches GO or
  /// is cancelled.
  ///
  /// Prefer this over [onComplete] when awaiting a countdown you just started:
  ///
  /// ```dart
  /// await countdownSystem.startCountdown();
  /// await countdownSystem.runCompletion;
  /// ```
  ///
  /// It is scoped to one run, so superseding an earlier countdown cannot
  /// release a waiter belonging to the new one — which is exactly the mistake
  /// the register/await/remove pattern around [onComplete] invites.
  Completer<void>? _runCompleter;
  Future<void> get runCompletion =>
      _runCompleter?.future ?? Future<void>.value();

  /// Complete the current run and notify all waiters. Idempotent.
  void _finishRun() {
    final completer = _runCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _notifyComplete();
  }

  /// Start the countdown sequence
  /// Sequence: [message (optional)] -> 3 (lo) -> 2 (lo) -> 1 (lo) -> GO (hi)
  /// Each step is 1 second apart, except message which uses [messageDuration]
  ///
  /// [message] Optional message to display before countdown (e.g., "Level 2, Get Ready")
  /// [messageDuration] Duration in seconds to display message (default: 2.0)
  /// [onAnyComplete] Optional callback for when countdown completes (in addition to registered onComplete callbacks)
  ///                 IMPORTANT: must be safe to call multiple times or after countdown has already completed!
  Future<void> startCountdown({
    String? message,
    double messageDuration = 2.0,
    FutureOr<void> Function()? onSuccessfulStart,
    FutureOr<void> Function()? onAnyComplete,
  }) async {
    if (isActive) {
      appLog.warning(
        'Countdown already in progress, cancelling existing countdown',
      );
      cancel();
    }

    // Fresh run identity, created *after* the supersede-cancel above so that
    // cancel's completion cannot leak into this run's waiters.
    _runCompleter = Completer<void>();

    _message = message;
    // Set active state BEFORE notifying overlay so isActive == true the moment
    // onSuccessfulStart adds the overlay, ensuring the input guard blocks immediately.
    _currentState = (message != null && message.isNotEmpty)
        ? CountdownState.message
        : CountdownState.three;
    notifyListeners();
    onSuccessfulStart?.call();
    // If there's a message, start with message state
    if (message != null && message.isNotEmpty) {
      appLog.info(
        'Starting countdown with message: "$message" (${messageDuration}s)',
      );
      // _currentState already set to message above

      // Wait for message duration, then start normal countdown
      await Future.delayed(
        Duration(milliseconds: (messageDuration * 1000).toInt()),
      );
      if (_currentState != CountdownState.message) {
        // Countdown was cancelled during message display. cancel() has already
        // finished the run; just fire this call's own completion hook.
        onAnyComplete?.call();
        return;
      }
    } else {
      appLog.info('Starting countdown sequence (no message)');
    }

    // Start normal countdown
    _currentState = CountdownState.three;
    notifyListeners();
    if (onPlayLo != null) {
      appLog.info('Playing first countdown sound (3)');
      await onPlayLo!();
      appLog.info('First countdown sound played');
    }

    // Schedule countdown steps
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      switch (_currentState) {
        case CountdownState.message:
          // Should not reach here, but handle gracefully
          timer.cancel();
          break;
        case CountdownState.three:
          _currentState = CountdownState.two;
          notifyListeners();
          if (onPlayLo != null) await onPlayLo!();
          break;
        case CountdownState.two:
          _currentState = CountdownState.one;
          notifyListeners();
          if (onPlayLo != null) await onPlayLo!();
          break;
        case CountdownState.one:
          _currentState = CountdownState.go;
          notifyListeners();
          if (onPlayHi != null) await onPlayHi!();
          break;
        case CountdownState.go:
          _currentState = CountdownState.finished;
          _message = null; // Clear message
          notifyListeners();
          timer.cancel();
          appLog.info('Countdown complete');
          onUnlocked?.call();
          _finishRun();
          onAnyComplete?.call();
          break;
        case CountdownState.finished:
          timer.cancel();
          onAnyComplete?.call();
          break;
      }
    });
  }

  /// Register a callback to be called when countdown completes
  void onComplete(VoidCallback callback) {
    _onCompleteCallbacks.add(callback);
  }

  /// Remove a completion callback
  void removeOnComplete(VoidCallback callback) {
    _onCompleteCallbacks.remove(callback);
  }

  /// Cancel the current countdown.
  ///
  /// Registered completion callbacks are still invoked. They are the only way
  /// waiters such as `RiseTogetherWorld.restartLevel()` are released, and a
  /// cancelled countdown is just as final as a finished one from their point of
  /// view. Not calling them left `_isRestartingLevel` stuck true, which silently
  /// disabled every subsequent restart for the rest of the session.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _currentState = CountdownState.finished;
    _message = null; // Clear message
    _networkManaged = false;
    notifyListeners();
    appLog.info('Countdown cancelled');
    _finishRun();
  }

  /// Set countdown state from network coordinator (for synchronized countdowns)
  /// This is used by participants to mirror the coordinator's countdown state
  Future<void> setStateFromNetwork(
    CountdownState state, {
    String? message,
  }) async {
    if (!_networkManaged && state != CountdownState.finished) {
      _networkManaged = true;
      appLog.info('Countdown now managed by network coordinator');
    }

    final previousState = _currentState;
    _currentState = state;
    _message = message;

    // Play audio for state transitions
    if (state != previousState) {
      if (state == CountdownState.three ||
          state == CountdownState.two ||
          state == CountdownState.one) {
        if (onPlayLo != null) {
          await onPlayLo!();
        }
      } else if (state == CountdownState.go) {
        if (onPlayHi != null) {
          await onPlayHi!();
        }
      } else if (state == CountdownState.finished) {
        _networkManaged = false;
        _message = null;
        appLog.info('Network-managed countdown complete');
        _finishRun();
      }
    }

    notifyListeners();
    // After the notification, as on the local path: this is when the input
    // guard (`isActive`) first lets a paddle action through.
    if (state == CountdownState.finished && previousState != state) {
      onUnlocked?.call();
    }
  }

  /// Notify all registered callbacks that countdown is complete.
  ///
  /// Iterates a copy: callbacks commonly call [removeOnComplete] on themselves,
  /// which would otherwise throw ConcurrentModificationError.
  void _notifyComplete() {
    for (final callback in List<VoidCallback>.of(_onCompleteCallbacks)) {
      callback();
    }
  }

  /// Dispose resources
  @override
  void dispose() {
    cancel();
    _onCompleteCallbacks.clear();
    super.dispose();
  }

  /// Get display text for current countdown state
  String getDisplayText() {
    switch (_currentState) {
      case CountdownState.message:
        return _message ?? '';
      case CountdownState.three:
        return '3';
      case CountdownState.two:
        return '2';
      case CountdownState.one:
        return '1';
      case CountdownState.go:
        return 'GO!';
      case CountdownState.finished:
        return '';
    }
  }
}
