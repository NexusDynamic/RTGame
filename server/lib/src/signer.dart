import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Signs and verifies short-lived tokens: `base64url(json).base64url(hmac)`.
///
/// Used for both proof-of-work challenges and session tokens, each tagged
/// with a distinct [purpose] so one can never be replayed as the other.
class Signer {
  Signer(String key) : _hmac = Hmac(sha256, utf8.encode(key));

  final Hmac _hmac;
  final Random _random = Random.secure();

  String sign(String purpose, Duration ttl, {DateTime? now}) {
    final expires = (now ?? DateTime.now()).add(ttl).millisecondsSinceEpoch;
    final body = base64Url.encode(
      utf8.encode(jsonEncode({'p': purpose, 'e': expires, 'n': randomHex(8)})),
    );
    return '$body.${_mac(body)}';
  }

  /// The token's unique id if it is authentic, for [purpose] and unexpired;
  /// otherwise null.
  String? verify(String token, String purpose, {DateTime? now}) {
    if (token.length > 512) return null;
    final dot = token.indexOf('.');
    if (dot <= 0) return null;
    final body = token.substring(0, dot);
    if (!_constantTimeEquals(_mac(body), token.substring(dot + 1))) {
      return null;
    }
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(body)));
      if (json is! Map<String, dynamic>) return null;
      if (json['p'] != purpose) return null;
      final expires = json['e'];
      if (expires is! int) return null;
      final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
      if (nowMs > expires) return null;
      final id = json['n'];
      return id is String ? id : null;
    } on FormatException {
      return null;
    }
  }

  String randomHex(int bytes) => [
    for (var i = 0; i < bytes; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  String randomBase64(int bytes) => base64Url
      .encode([for (var i = 0; i < bytes; i++) _random.nextInt(256)])
      .replaceAll('=', '');

  String _mac(String body) =>
      base64Url.encode(_hmac.convert(utf8.encode(body)).bytes);

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
