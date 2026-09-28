import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Short-lived TURN credentials in coturn's `use-auth-secret` scheme.
///
/// The username carries its own expiry and coturn recomputes the password
/// from the shared secret, so nothing is stored and a leaked credential dies
/// on its own.
({String username, String credential}) turnCredentials({
  required String secret,
  required String label,
  required Duration ttl,
  DateTime? now,
}) {
  final expires =
      (now ?? DateTime.now()).add(ttl).millisecondsSinceEpoch ~/ 1000;
  final username = '$expires:$label';
  final credential = base64.encode(
    Hmac(sha1, utf8.encode(secret)).convert(utf8.encode(username)).bytes,
  );
  return (username: username, credential: credential);
}
