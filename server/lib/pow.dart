/// Proof-of-work for lobby admission. Web-safe: no `dart:io`.
///
/// The server hands out a signed challenge string; the client finds a
/// [solve] counter whose `sha256("$challenge:$counter")` starts with
/// `difficulty` zero bits. Cheap for one honest player (a fraction of a
/// second), expensive for anyone trying to open thousands of sessions — and
/// it needs no key in the app.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Leading zero bits of [bytes].
int leadingZeroBits(List<int> bytes) {
  var count = 0;
  for (final byte in bytes) {
    if (byte == 0) {
      count += 8;
      continue;
    }
    for (var bit = 7; bit >= 0; bit--) {
      if (byte & (1 << bit) != 0) return count;
      count++;
    }
  }
  return count;
}

/// Whether [counter] solves [challenge] at [difficulty].
bool checkSolution(String challenge, int counter, int difficulty) {
  if (counter < 0) return false;
  final digest = sha256.convert(utf8.encode('$challenge:$counter'));
  return leadingZeroBits(digest.bytes) >= difficulty;
}

/// Find a counter that solves [challenge], trying [batch] at a time.
///
/// Yields to the event loop between batches so a UI stays responsive on
/// platforms without isolates (the web). Returns null if [maxAttempts] pass
/// without a solution, which at sane difficulties does not happen.
Future<int?> solve(
  String challenge,
  int difficulty, {
  int batch = 2000,
  int maxAttempts = 1 << 26,
}) async {
  for (var start = 0; start < maxAttempts; start += batch) {
    for (var counter = start; counter < start + batch; counter++) {
      if (checkSolution(challenge, counter, difficulty)) return counter;
    }
    await Future<void>.delayed(Duration.zero);
  }
  return null;
}
