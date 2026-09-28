import 'dart:math' as math;

import 'package:rise_together_game/src/game/game_geometry.dart';
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
/// Resets and level loads teleport a team's ball and paddle back to the start.
/// Blending or projecting across that jump draws them sweeping through the
/// level for a frame or two, so a team whose samples jump further than
/// [maxJump] snaps to the newer one instead.
///
/// Times are this device's arrival times, in seconds; no clock sync is needed.
class SnapshotInterpolator {
  SnapshotInterpolator({
    this.delay = 0.06,
    this.maxExtrapolation = 0.1,
    this.capacity = 32,
    this.maxJump = GameGeometry.levelWidth * 0.5,
  });

  /// How far behind real time the follower renders.
  final double delay;

  /// Longest projection past the newest sample.
  final double maxExtrapolation;

  /// Samples kept. Only the two around the render time are ever needed; the
  /// rest absorb bursts.
  final int capacity;

  /// Movement between two consecutive samples beyond which a team counts as
  /// teleported. Half a level width is far beyond any real per-sample motion
  /// and far below a reset's jump.
  final double maxJump;

  final List<double> _times = [];
  final List<List<double>> _states = [];

  /// Reused output, reallocated only if the channel count changes.
  List<double> _out = const [];

  List<double> _outFor(int length) {
    if (_out.length != length) _out = List<double>.filled(length, 0);
    return _out;
  }

  bool get isEmpty => _states.isEmpty;

  /// Arrival time of the newest sample behind the last [sample] result, or
  /// null before the first. A follower that has just loaded a level uses it
  /// to tell the previous level's poses from the new one's.
  double? get lastSampleTime => _lastSampleTime;
  double? _lastSampleTime;

  List<bool> _snap = const [];

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
    _lastSampleTime = null;
  }

  /// Whether the team whose channels start at [offset] jumped between [a] and
  /// [b], judged by its ball and paddle.
  bool _teleported(List<double> a, List<double> b, int offset) {
    double delta(int channel) => b[offset + channel] - a[offset + channel];
    return isDiscontinuity(
          dx: delta(PhysicsChannels.ballX),
          dy: delta(PhysicsChannels.ballY),
          maxJump: maxJump,
        ) ||
        isDiscontinuity(
          dx: 0,
          dy: delta(PhysicsChannels.paddleY),
          maxJump: maxJump,
        );
  }

  /// Per channel of [b]: whether its team teleported since [a]. Teams [a]
  /// does not cover count as teleported, so they take [b] as is.
  ///
  /// The returned list is reused by the next call.
  List<bool> _snapMask(List<double> a, List<double> b) {
    if (_snap.length != b.length) _snap = List<bool>.filled(b.length, true);
    final mask = _snap..fillRange(0, b.length, true);
    for (
      var offset = 0;
      offset + PhysicsChannels.perTeam <= b.length;
      offset += PhysicsChannels.perTeam
    ) {
      if (offset + PhysicsChannels.perTeam > a.length) continue;
      final snap = _teleported(a, b, offset);
      mask.fillRange(offset, offset + PhysicsChannels.perTeam, snap);
    }
    return mask;
  }

  /// The state to show at [now], or null with no samples.
  ///
  /// The returned list is reused by the next call; copy it to keep it.
  List<double>? sample(double now) {
    if (_states.isEmpty) return null;
    final renderTime = now - delay;

    // Before the oldest sample: nothing to blend from yet.
    if (renderTime <= _times.first) {
      _lastSampleTime = _times.first;
      return _outFor(_states.first.length)..setAll(0, _states.first);
    }

    // Past the newest: project briefly, then hold.
    if (renderTime >= _times.last) {
      final newest = _states.last;
      final out = _outFor(newest.length);
      _lastSampleTime = _times.last;
      if (_states.length < 2) return out..setAll(0, newest);
      final previous = _states[_states.length - 2];
      final snap = _snapMask(previous, newest);
      final span = _times.last - _times[_times.length - 2];
      final lead = math.min(renderTime - _times.last, maxExtrapolation);
      for (var i = 0; i < newest.length; i++) {
        out[i] = isContinuous(i) && !isWrappingAngle(i) && !snap[i]
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
    _lastSampleTime = _times[i + 1];
    final snap = _snapMask(a, b);
    final out = _outFor(b.length);
    for (var c = 0; c < b.length; c++) {
      if (!isContinuous(c) || c >= a.length || snap[c]) {
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
