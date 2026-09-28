# Rise Together

A cooperative and competitive physics game. Keep the ball in the air by
lifting the left and right sides of your paddle, climb through the levels, and
race the other team to the top.

- **Solo**: play offline and beat your best height.
- **Online**: team up (co-op) or play against another team (versus). Use quick
  match or a private room code. Players connect peer to peer, and the host
  player's device runs the physics.

Built with Flutter, Flame and Forge2D. It runs on Android, iOS, macOS, Windows,
Linux and the web.

## Development

```sh
flutter pub get
flutter run            # or: flutter run -d chrome
flutter test
flutter test integration_test/real_webrtc_test.dart -d linux   # real WebRTC
```

Online play needs the lobby server (`server/`, see its README). Point a build
at it with `--dart-define=LOBBY_URL=https://your.host`. For web builds, add
`--wasm --no-web-resources-cdn`.

See [PRIVACY.md](PRIVACY.md) for what online play shares.

Derived from the RiseTogether research platform by NexusDynamic.
