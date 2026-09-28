import 'dart:math' as math;

import 'package:rise_together_game/src/game/physics_channels.dart';
import 'package:rise_together_game/src/game/physics_extrapolation.dart';

/// Smooths the authority's physics samples for display on a follower.
///
/// Samples arrive unevenly over the internet: bunched, late, occasionally
/// lost. Applying each one as it lands makes the ball stutter. Instead the
/// follower renders a fixed [delay] in the past and blends between the two
/// samples either side of that moment, so jitter smaller than [delay] is
/// invisible. When samples run out it projects the last motion forward for at
/// most [maxExtrapolation], then holds still.
///
/// Times are this device's arrival times, in seconds; no clock sync is needed.
class SnapshotInterpolator {
  SnapshotInterpolator({
    this.delay = 0.06,
    this.maxExtrapolation = 0.1,
    this.capacity = 32,
  });

  /// How far behind real time the follower renders.
  final double delay;

  /// Longest projection past the newest sample.
  final double maxExtrapolation;

  /// Samples kept. Only the two around the render time are ever needed; the
  /// rest absorb bursts.
  final int capacity;

  final List<double> _times = [];
  final List<List<double>> _states = [];

  /// Reused output, reallocated only if the channel count changes.
  List<double> _out = const [];

  List<double> _outFor(int length) {
    if (_out.length != length) _out = List<double>.filled(length, 0);
    return _out;
  }

  bool get isEmpty => _states.isEmpty;

  int get length => _states.length;

  /// Positions and angles blend; the paddle width and the press bitflags are
  /// discrete and take the newer sample's value.
  static bool isContinuous(int index) {
    final channel = index % PhysicsChannels.perTeam;
    return channel == PhysicsChannels.ballX ||
        channel == PhysicsChannels.ballY ||
        channel == PhysicsChannels.ballRotation ||
        channel == PhysicsChannels.paddleY ||
        channel == PhysicsChannels.paddleAngle;
  }

  /// Ball rotation wraps at ±π, so it must blend the short way round.
  static bool isWrappingAngle(int index) =>
      index % PhysicsChannels.perTeam == PhysicsChannels.ballRotation;

  /// Record a sample that arrived at [arrivedAt]. Takes ownership of [state].
  void add(List<double> state, double arrivedAt) {
    // Arrival times must increase for the search below; two samples handled
    // in the same instant are nudged apart rather than dropped.
    final time = _times.isNotEmpty && arrivedAt <= _times.last
        ? _times.last + 1e-6
        : arrivedAt;
    _times.add(time);
    _states.add(state);
    if (_states.length > capacity) {
      _times.removeAt(0);
      _states.removeAt(0);
    }
  }

  void clear() {
    _times.clear();
    _states.clear();
  }

  /// The state to show at [now], or null with no samples.
  ///
  /// The returned list is reused by the next call; copy it to keep it.
  List<double>? sample(double now) {
    if (_states.isEmpty) return null;
    final renderTime = now - delay;

    // Before the oldest sample: nothing to blend from yet.
    if (renderTime <= _times.first) {
      return _outFor(_states.first.length)..setAll(0, _states.first);
    }

    // Past the newest: project briefly, then hold.
    if (renderTime >= _times.last) {
      final newest = _states.last;
      final out = _outFor(newest.length);
      if (_states.length < 2) return out..setAll(0, newest);
      final previous = _states[_states.length - 2];
      final span = _times.last - _times[_times.length - 2];
      final lead = math.min(renderTime - _times.last, maxExtrapolation);
      for (var i = 0; i < newest.length; i++) {
        out[i] = isContinuous(i) && !isWrappingAngle(i)
            ? projectChannel(
                value: newest[i],
                previousValue: previous[i],
                span: span,
                lead: lead,
              )
            : newest[i];
      }
      return out;
    }

    // Between two samples. Everything older than the earlier one can go.
    var i = _times.length - 2;
    while (_times[i] > renderTime) {
      i--;
    }
    if (i > 0) {
      _times.removeRange(0, i);
      _states.removeRange(0, i);
      i = 0;
    }
    final a = _states[i];
    final b = _states[i + 1];
    final t = (renderTime - _times[i]) / (_times[i + 1] - _times[i]);
    final out = _outFor(b.length);
    for (var c = 0; c < b.length; c++) {
      if (!isContinuous(c) || c >= a.length) {
        out[c] = b[c];
      } else if (isWrappingAngle(c)) {
        out[c] = _lerpAngle(a[c], b[c], t);
      } else {
        out[c] = a[c] + (b[c] - a[c]) * t;
      }
    }
    return out;
  }

  static double _lerpAngle(double a, double b, double t) {
    var delta = (b - a) % (2 * math.pi);
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    return a + delta * t;
  }
}
