import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:rise_together_lobby/lobby.dart';
import 'package:rise_together_lobby/pow.dart';
import 'package:rise_together_lobby/protocol.dart';
import 'package:rise_together_lobby/src/pseudonymizer.dart';
import 'package:rise_together_lobby/src/rate_limiter.dart';
import 'package:rise_together_lobby/src/signer.dart';
import 'package:test/test.dart';

void main() {
  group('proof of work', () {
    test('counts leading zero bits', () {
      expect(leadingZeroBits([0, 0, 0x80]), 16);
      expect(leadingZeroBits([0x0f]), 4);
      expect(leadingZeroBits([0xff]), 0);
    });

    test('a solution verifies and a wrong one does not', () async {
      final counter = await solve('challenge', 10);
      expect(counter, isNotNull);
      expect(checkSolution('challenge', counter!, 10), isTrue);
      expect(checkSolution('other', counter, 10), isFalse);
      expect(checkSolution('challenge', -1, 1), isFalse);
    });
  });

  group('Signer', () {
    final signer = Signer('k' * 32);

    test('round trips for the right purpose only', () {
      final token = signer.sign('session', const Duration(minutes: 1));
      expect(signer.verify(token, 'session'), isNotNull);
      expect(signer.verify(token, 'pow'), isNull);
    });

    test('rejects expired, tampered and foreign tokens', () {
      final now = DateTime(2030);
      final token = signer.sign(
        'session',
        const Duration(minutes: 1),
        now: now,
      );
      expect(
        signer.verify(
          token,
          'session',
          now: now.add(const Duration(minutes: 2)),
        ),
        isNull,
      );
      expect(signer.verify('${token}x', 'session'), isNull);
      expect(signer.verify('garbage', 'session'), isNull);
      expect(
        Signer('other-key-that-is-long-enough-00').verify(token, 'session'),
        isNull,
      );
    });
  });

  group('RateLimiter', () {
    test('allows a burst, then refills over time', () {
      final limiter = RateLimiter(capacity: 2, perSecond: 1);
      final t = DateTime(2030);
      expect(limiter.allow('a', now: t), isTrue);
      expect(limiter.allow('a', now: t), isTrue);
      expect(limiter.allow('a', now: t), isFalse);
      expect(limiter.allow('b', now: t), isTrue, reason: 'keys are separate');
      expect(
        limiter.allow('a', now: t.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('prune forgets refilled buckets', () {
      final limiter = RateLimiter(capacity: 2, perSecond: 1);
      final t = DateTime(2030);
      limiter.allow('a', now: t);
      limiter.prune(now: t.add(const Duration(seconds: 10)));
      expect(limiter.trackedKeys, 0);
    });
  });

  group('IpPseudonymizer', () {
    test('stable within a period, distinct across addresses', () {
      final p = IpPseudonymizer();
      expect(p.idFor('203.0.113.7'), p.idFor('203.0.113.7'));
      expect(p.idFor('203.0.113.7'), isNot(p.idFor('203.0.113.8')));
      expect(p.idFor('203.0.113.7'), hasLength(12));
    });

    test('is keyed: not a plain hash, and unlinkable across instances', () {
      final ip = '203.0.113.7';
      final plain = sha256.convert(utf8.encode(ip)).toString();
      final id = IpPseudonymizer().idFor(ip);
      expect(plain, isNot(startsWith(id)));
      expect(IpPseudonymizer().idFor(ip), isNot(id));
    });

    test('rotates its key after the period', () {
      var now = DateTime(2030);
      final p = IpPseudonymizer(clock: () => now);
      final before = p.idFor('203.0.113.7');
      now = now.add(const Duration(hours: 25));
      expect(p.idFor('203.0.113.7'), isNot(before));
    });
  });

  test('TURN credentials follow the coturn REST scheme', () {
    final creds = turnCredentials(
      secret: 'turn-secret',
      label: 'room',
      ttl: const Duration(seconds: 600),
      now: DateTime.fromMillisecondsSinceEpoch(1000000 * 1000),
    );
    expect(creds.username, '1000600:room');
    expect(
      creds.credential,
      base64.encode(
        Hmac(
          sha1,
          utf8.encode('turn-secret'),
        ).convert(utf8.encode('1000600:room')).bytes,
      ),
    );
  });

  group('protocol decoding', () {
    test('client messages round trip and junk is rejected', () {
      for (final m in const <ClientMessage>[
        QuickMatch(mode: LobbyMode.versus, players: 4),
        QuickMatch(mode: LobbyMode.versus, players: 2, custom: true),
        CreateRoom(mode: LobbyMode.coop, players: 2),
        CreateRoom(mode: LobbyMode.coop, players: 3, custom: true),
        JoinRoom(code: 'ABC234'),
      ]) {
        expect(
          ClientMessage.fromJson(jsonDecode(jsonEncode(m.toJson())))?.toJson(),
          m.toJson(),
        );
      }
      for (final junk in [
        null,
        'x',
        {'t': 'quick', 'mode': 'versus', 'players': 99},
        {'t': 'quick', 'mode': 'chaos', 'players': 2},
        {'t': 'join', 'code': 'abc234'},
        {'t': 'join', 'code': 'ABC10O'},
        {'t': 'quick', 'mode': 'coop', 'players': 2, 'custom': 'yes'},
        {'t': 'create', 'mode': 'coop', 'players': 2, 'custom': 1},
        {'t': 'admin'},
      ]) {
        expect(ClientMessage.fromJson(junk), isNull, reason: '$junk');
      }
    });

    test('ICE servers only accept STUN/TURN URLs', () {
      expect(
        IceServer.tryFromJson({
          'urls': ['turn:x:3478'],
        }),
        isNotNull,
      );
      expect(
        IceServer.tryFromJson({
          'urls': ['javascript:alert(1)'],
        }),
        isNull,
      );
      expect(
        IceServer.tryFromJson({
          'urls': ['https://evil'],
        }),
        isNull,
      );
      expect(IceServer.tryFromJson({'urls': []}), isNull);
    });

    test('a match must carry a well-formed room id', () {
      Map<String, dynamic> match(String room) => {
        't': 'match',
        'room': room,
        'secret': 's',
        'host': true,
        'mode': 'coop',
        'players': 2,
        'ice': [],
      };
      expect(ServerMessage.fromJson(match('0' * 32)), isA<MatchFound>());
      expect(ServerMessage.fromJson(match('../../etc')), isNull);
    });

    test('the custom-levels flag defaults to false and must be a bool', () {
      final plain = ClientMessage.fromJson({
        't': 'quick',
        'mode': 'coop',
        'players': 2,
      });
      expect((plain! as QuickMatch).custom, isFalse);
      final match = {
        't': 'match',
        'room': '0' * 32,
        'secret': 's',
        'host': false,
        'mode': 'coop',
        'players': 2,
        'ice': [],
      };
      expect((ServerMessage.fromJson(match)! as MatchFound).custom, isFalse);
      expect(
        (ServerMessage.fromJson({...match, 'custom': true})! as MatchFound)
            .custom,
        isTrue,
      );
      expect(ServerMessage.fromJson({...match, 'custom': 'true'}), isNull);
      expect(
        (ServerMessage.fromJson({
                  't': 'waiting',
                  'joined': 1,
                  'players': 2,
                  'custom': true,
                })!
                as Waiting)
            .custom,
        isTrue,
      );
    });
  });

  test('config refuses a short signing key and TURN without a secret', () {
    expect(() => LobbyConfig(signingKey: 'short'), throwsArgumentError);
    expect(
      () => LobbyConfig(signingKey: 'k' * 32, turnUrls: ['turn:x']),
      throwsArgumentError,
    );
  });
}
