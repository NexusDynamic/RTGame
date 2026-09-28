import 'dart:async';

import 'package:flutter/foundation.dart';

/// How long a follower waits for a host that paused the match.
///
/// The allowance is for the whole match, not each pause: a host (or a modified
/// client posing as one) toggling the pause could otherwise hold everyone
/// forever. When it runs out, [onExhausted] fires once and the follower
/// leaves.
class HostAwayTracker {
  HostAwayTracker({
    required this.onExhausted,
    this.allowance = const Duration(seconds: 30),
    Duration Function()? clock,
  }) : _clock = clock ?? _stopwatch();

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  final Duration allowance;
  final VoidCallback onExhausted;
  final Duration Function() _clock;

  /// Time left while the host is away, updated every second; null while the
  /// host is present.
  final ValueNotifier<Duration?> remaining = ValueNotifier(null);

  Duration _used = Duration.zero;
  Duration? _awaySince;
  Timer? _ticker;
  bool _exhausted = false;

  /// The host paused ([away]) or resumed the match.
  void hostAway(bool away) {
    if (_exhausted || away == (_awaySince != null)) return;
    if (away) {
      _awaySince = _clock();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => check());
      check();
    } else {
      _used += _clock() - _awaySince!;
      _awaySince = null;
      _ticker?.cancel();
      _ticker = null;
      remaining.value = null;
    }
  }

  /// Update [remaining] and fire [onExhausted] if the allowance is spent.
  /// Runs every second while the host is away.
  @visibleForTesting
  void check() {
    final since = _awaySince;
    if (since == null || _exhausted) return;
    final left = allowance - _used - (_clock() - since);
    if (left > Duration.zero) {
      remaining.value = left;
      return;
    }
    _exhausted = true;
    _ticker?.cancel();
    remaining.value = Duration.zero;
    onExhausted();
  }

  void dispose() {
    _ticker?.cancel();
    remaining.dispose();
  }
}
