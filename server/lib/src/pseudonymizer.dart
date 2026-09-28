import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Turns client IP addresses into log-safe ids.
///
/// A plain hash of an IP is not anonymous: there are only ~4 billion IPv4
/// addresses, so hashing them all reverses it in minutes. This is keyed
/// instead (HMAC-SHA256) with a random key that lives only in memory and is
/// replaced every [rotation]. Within one period the same address gets the same
/// id, which is what tracing abuse needs; without the key, which is never
/// written anywhere, an id cannot be turned back into an address, and ids from
/// different periods cannot be linked.
class IpPseudonymizer {
  IpPseudonymizer({
    this.rotation = const Duration(hours: 24),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _rotate();
  }

  final Duration rotation;
  final DateTime Function() _clock;
  final Random _random = Random.secure();

  late Hmac _hmac;
  late DateTime _rotatedAt;

  void _rotate() {
    _hmac = Hmac(sha256, [for (var i = 0; i < 32; i++) _random.nextInt(256)]);
    _rotatedAt = _clock();
  }

  /// A short, stable-for-today id for [ip].
  String idFor(String ip) {
    if (_clock().difference(_rotatedAt) >= rotation) _rotate();
    final digest = _hmac.convert(utf8.encode(ip));
    // 48 bits: unique enough to tell clients apart, short enough to read.
    return digest.toString().substring(0, 12);
  }
}
