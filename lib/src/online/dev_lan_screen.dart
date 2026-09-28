import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:peer_coordinator/websocket.dart' show HubCredentials;
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/peer_game_session.dart';
import 'package:rise_together_game/src/online/online_game_screen.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:webrtc_coordinator_flutter/webrtc_coordinator_flutter.dart';

/// Debug-only: join a room on a local `peer_coordinator` hub, skipping the
/// lobby. For testing online play before the lobby server exists.
///
/// Configured at build time, and compiled out of release builds (see
/// [isAvailable]) so the hub secret never ships:
///
/// ```sh
/// dart run peer_coordinator:hub --session rt-dev --secret-file secret.txt \
///   --host 0.0.0.0 --port 8787
/// flutter run --dart-define=DEV_HUB_URL=ws://192.168.1.10:8787 \
///   --dart-define=DEV_HUB_SESSION=rt-dev --dart-define=DEV_HUB_SECRET=...
/// ```
class DevLanScreen extends StatefulWidget {
  const DevLanScreen({super.key});

  static const _url = String.fromEnvironment('DEV_HUB_URL');
  static const _session = String.fromEnvironment('DEV_HUB_SESSION');
  static const _secret = String.fromEnvironment('DEV_HUB_SECRET');

  static bool get isAvailable =>
      !kReleaseMode &&
      _url.isNotEmpty &&
      _session.isNotEmpty &&
      _secret.isNotEmpty;

  @override
  State<DevLanScreen> createState() => _DevLanScreenState();
}

class _DevLanScreenState extends State<DevLanScreen> with AppSettings {
  final _room = TextEditingController(text: 'dev');
  int _players = 2;
  MatchMode _mode = MatchMode.versus;
  bool _host = true;
  String? _status;
  bool _busy = false;
  PeerGameSession? _pending;

  @override
  void dispose() {
    _room.dispose();
    _pending?.leave();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _status = 'Connecting…';
    });
    final navigator = Navigator.of(context);
    try {
      final session = _pending = await PeerGameSession.connect(
        transport: RtcTransportConfig(
          hubUri: Uri.parse(DevLanScreen._url),
          credentials: HubCredentials(
            session: DevLanScreen._session,
            secret: DevLanScreen._secret,
          ),
          adapterFactory: flutterWebrtcAdapterFactory,
          // Physics is sent 60 times a second: a late sample is worthless, so
          // don't wait for retransmits or reorder.
          dataOrdered: false,
          dataMaxRetransmits: 1,
        ),
        roomName: _room.text.trim(),
        nickname: appSettings.getString('player.nickname'),
        playerCount: _players,
        host: _host,
      );
      if (!mounted) return;
      setState(
        () => _status = session.isAuthority
            ? 'Hosting. Waiting for players…'
            : 'Joined. Waiting for the host…',
      );
      await session.startMatch(
        hostRules: MatchRules(
          mode: _mode,
          roundDurationSeconds: appSettings.getDouble('game.round_duration'),
          seed: DateTime.now().millisecondsSinceEpoch % MatchRules.maxSeed,
        ),
      );
      _pending = null;
      if (!mounted) {
        await session.leave();
        return;
      }
      await navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OnlineGameScreen(session: session),
        ),
      );
    } catch (e) {
      _pending = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LAN test (debug)')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Hub: ${DevLanScreen._url}'),
        TextField(
          controller: _room,
          decoration: const InputDecoration(labelText: 'Room'),
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Host')),
            ButtonSegment(value: false, label: Text('Join')),
          ],
          selected: {_host},
          onSelectionChanged: (s) => setState(() => _host = s.single),
        ),
        const SizedBox(height: 16),
        SegmentedButton<MatchMode>(
          segments: const [
            ButtonSegment(value: MatchMode.coop, label: Text('Co-op')),
            ButtonSegment(value: MatchMode.versus, label: Text('Versus')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.single),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Players'),
            Expanded(
              child: Slider(
                value: _players.toDouble(),
                min: 2,
                max: 4,
                divisions: 2,
                label: '$_players',
                onChanged: (v) => setState(() => _players = v.round()),
              ),
            ),
            Text('$_players'),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _join,
          child: const Text('Join'),
        ),
        if (_status != null) ...[const SizedBox(height: 16), Text(_status!)],
      ],
    ),
  );
}
