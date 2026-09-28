/// Token buckets keyed by client address.
class RateLimiter {
  RateLimiter({required this.capacity, required this.perSecond});

  /// Burst allowance.
  final double capacity;

  /// Sustained rate.
  final double perSecond;

  final Map<String, ({double tokens, DateTime at})> _buckets = {};

  /// Spend one token for [key]; false when the bucket is empty.
  bool allow(String key, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final bucket = _buckets[key];
    var tokens = capacity;
    if (bucket != null) {
      final elapsed = at.difference(bucket.at).inMicroseconds / 1e6;
      tokens = (bucket.tokens + elapsed * perSecond).clamp(0, capacity);
    }
    if (tokens < 1) {
      _buckets[key] = (tokens: tokens, at: at);
      return false;
    }
    _buckets[key] = (tokens: tokens - 1, at: at);
    return true;
  }

  /// Forget buckets that have refilled, so the map cannot grow unbounded.
  void prune({DateTime? now}) {
    final at = now ?? DateTime.now();
    final full = Duration(microseconds: (capacity / perSecond * 1e6).ceil());
    _buckets.removeWhere((_, b) => at.difference(b.at) > full);
  }

  int get trackedKeys => _buckets.length;
}
