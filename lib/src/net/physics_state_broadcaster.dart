/// Decides when the authoritative physics state goes out on the wire.
///
/// Pulled out of [NetworkCoordinator] because this is the highest-frequency
/// path in the system — it is consulted on every physics frame, up to 120 Hz,
/// on a Raspberry Pi — and because its gating is what silently broke 1v1: a
/// flag that nothing enabled meant zero samples were ever sent, while the
/// input path kept working and logging, so the failure looked like a rendering
/// bug rather than a broadcast one.
///
/// Owns only the decision. The stream's lifecycle stays with the coordinator,
/// which hands in [sendSample].
class PhysicsStateBroadcaster {
  PhysicsStateBroadcaster({
    required this.sendSample,
    required this.isPlaying,
    this.minIntervalMs = defaultMinIntervalMs,
  });

  /// ~120 Hz ceiling.
  static const int defaultMinIntervalMs = 8;

  /// Hands a sample to the transport. Must copy synchronously — the provider
  /// reuses its output buffer.
  final void Function(List<double> sample) sendSample;

  /// Whether a game is actually running.
  final bool Function() isPlaying;

  final int minIntervalMs;

  /// Supplies the sample, or null when nothing changed since the last call.
  List<double>? Function()? _provider;

  bool _enabled = false;

  /// Simulated time since the last sample was sent, in seconds.
  ///
  /// Deliberately *simulated* rather than wall-clock. This throttle used to
  /// read a monotonic `Stopwatch`, which quietly halved the recorded rate on
  /// the coordinator: the fixed-step pump earns its steps from real elapsed
  /// time and runs however many are owed per timer callback, so when the Pi's
  /// event loop delivered ~60 callbacks a second the pump correctly ran two
  /// 8.33 ms steps back to back — microseconds apart in wall time. The second
  /// one was then always inside the 8 ms window and dropped. The simulation
  /// was a true 120 Hz (zero dropped steps all session); the wire and the log
  /// were 60 Hz, and the 2026-08-14 recording's inter-sample intervals show it
  /// exactly: 8800 of 11677 in the 15–18 ms band.
  ///
  /// Simulated time has no such coupling. It also has no jitter, which matters
  /// independently: at a 120 Hz tick the step period (8.33 ms) sits right on
  /// this threshold (8 ms), and the comparison truncates to whole
  /// milliseconds — so a callback arriving 7.9 ms after the last send would be
  /// rejected and the next sample would land 16 ms later.
  double _simSinceSent = 0;
  bool _sentAny = false;

  /// Samples actually sent. Exposed for diagnostics and tests — "did anything
  /// go out at all" is precisely the question the 1v1 blackout raised.
  int sentCount = 0;

  bool get isEnabled => _enabled;
  bool get hasProvider => _provider != null;

  void setProvider(List<double>? Function()? provider) => _provider = provider;

  /// Arm broadcasting. Must be called by every path that owns a game — the
  /// regression was a caller that started a game without reaching this.
  void start() => _enabled = true;

  void stop() => _enabled = false;

  /// Reset for a fresh round: disarmed, no provider, throttle cleared.
  void reset() {
    _enabled = false;
    _provider = null;
    _simSinceSent = 0;
    _sentAny = false;
  }

  /// Offer the current state, subject to arming, a running game, and the rate
  /// limit. Safe to call every simulation step; that is the intended usage.
  ///
  /// [dt] is the simulation step just taken, in seconds — the same `dt` the
  /// physics world was advanced by.
  ///
  /// Returns whether a sample was sent.
  bool broadcastOnChange(double dt) {
    if (!_enabled || !isPlaying()) return false;

    _simSinceSent += dt;
    // `* 1000 <` against whole milliseconds keeps the accept/reject boundary
    // where it was: a step lands exactly on the limit and is accepted.
    if (_sentAny && _simSinceSent * 1000 < minIntervalMs) return false;

    final provider = _provider;
    if (provider == null) return false;

    final state = provider();
    // Null means "nothing changed" — a normal outcome, not a failure. Note the
    // throttle only resets when a sample is actually sent, so a quiet period
    // cannot delay the next real update.
    if (state == null) return false;

    _simSinceSent = 0;
    _sentAny = true;
    sendSample(state);
    sentCount++;
    return true;
  }
}
