import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:peer_coordinator/testing.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/net/game_session.dart';
import 'package:rise_together_game/src/net/peer_game_session.dart';
import 'package:webrtc_coordinator_flutter/webrtc_coordinator_flutter.dart';

/// Two PeerGameSessions in one process over REAL WebRTC (flutter_webrtc on
/// this desktop) and a real hub. The unit tests use a fake adapter; this is
/// what catches the differences.
///
///   flutter test integration_test/real_webrtc_test.dart -d linux
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen(
    // ignore: avoid_print
    (r) => print('${r.time.toIso8601String().substring(11)} '
        '${r.level.name} ${r.loggerName}: ${r.message}'),
  );

  testWidgets('a host and a player connect and exchange input and physics', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final hub = await startTestHub();
      final sessions = <PeerGameSession>[];
      try {
        Future<PeerGameSession> connect({required bool host}) =>
            PeerGameSession.connect(
              transport: RtcTransportConfig(
                hubUri: hub.uri,
                credentials: hub.credentials,
                adapterFactory: flutterWebrtcAdapterFactory,
                dataOrdered: false,
                dataMaxRetransmits: 1,
              ),
              roomName: 'real-rtc',
              nickname: host ? 'host' : 'guest',
              playerCount: 2,
              host: host,
              timeout: const Duration(seconds: 20),
            );

        final hostSession = await connect(host: true);
        sessions.add(hostSession);
        final guestSession = await connect(host: false);
        sessions.add(guestSession);

        const rules = MatchRules(
          mode: MatchMode.versus,
          roundDurationSeconds: 60,
          seed: 7,
        );
        await Future.wait([
          hostSession.startMatch(hostRules: rules),
          guestSession.startMatch(hostRules: rules),
        ]).timeout(const Duration(seconds: 40));

        final input = hostSession.actions.firstWhere(
          (a) => a.action == PaddleAction.left,
        );
        guestSession.sendAction(PaddleAction.left);
        final action = await input.timeout(const Duration(seconds: 5));
        expect(action.playerId, guestSession.localAssignment.playerId);

        final physics = guestSession.physics.first;
        final pump = Timer.periodic(
          const Duration(milliseconds: 20),
          (_) => hostSession.broadcastPhysics(List.filled(16, 1.5)),
        );
        try {
          expect(
            await physics.timeout(const Duration(seconds: 5)),
            List.filled(16, 1.5),
          );
        } finally {
          pump.cancel();
        }
      } finally {
        for (final s in sessions) {
          await s.leave();
        }
        await hub.close();
      }
    });
  });
}
