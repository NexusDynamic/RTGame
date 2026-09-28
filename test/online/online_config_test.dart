import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/online/online_config.dart';

void main() {
  group('OnlineConfig.parse', () {
    test('accepts http(s) addresses with a host', () {
      expect(
        OnlineConfig.parse('https://lobby.example'),
        Uri.parse('https://lobby.example'),
      );
      expect(
        OnlineConfig.parse('  http://127.0.0.1:8080  '),
        Uri.parse('http://127.0.0.1:8080'),
      );
      expect(
        OnlineConfig.parse('https://example.org/rt/'),
        Uri.parse('https://example.org/rt/'),
      );
    });

    test('rejects anything else', () {
      for (final bad in [
        '',
        'lobby.example',
        'ftp://lobby.example',
        'javascript:alert(1)',
        'https://',
        'https://user:pass@lobby.example',
        'https://lobby.example/?x=1',
        'https://lobby.example/#frag',
        'wss://lobby.example',
      ]) {
        expect(OnlineConfig.parse(bad), isNull, reason: bad);
      }
    });
  });

  group('OnlineConfig.resolve', () {
    const def = 'https://rt-lobby.example';

    test('the build default when nothing is set', () {
      expect(
        OnlineConfig.resolve(custom: '', buildDefault: def),
        Uri.parse(def),
      );
    });

    test("the player's server wins", () {
      expect(
        OnlineConfig.resolve(custom: 'https://mine.example', buildDefault: def),
        Uri.parse('https://mine.example'),
      );
    });

    test('an invalid custom server falls back to the default', () {
      expect(
        OnlineConfig.resolve(custom: 'not a url', buildDefault: def),
        Uri.parse(def),
      );
    });

    test('a build without a default is offline unless the player sets one', () {
      expect(OnlineConfig.resolve(custom: '', buildDefault: 'none'), isNull);
      expect(OnlineConfig.resolve(custom: '', buildDefault: ''), isNull);
      expect(
        OnlineConfig.resolve(
          custom: 'https://mine.example',
          buildDefault: 'none',
        ),
        Uri.parse('https://mine.example'),
      );
    });
  });
}
