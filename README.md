# Rise Together

A cooperative and competitive physics game. Keep the ball in the air by
lifting the left and right sides of your paddle, climb through the levels, and
race the other team to the top.

This is a hard fork from the RiseTogether research platform, the RiseTogether version
is an experimental paradigm for researching group social dynamics. This version of the
game is much more game-like and does not have all of the logging and multimodal
integration that are used in the experiments.

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
scripts/with-weston.sh flutter test integration_test/real_webrtc_test.dart -d linux   # same, headless (as CI)
```

Online play needs the lobby server (`server/`; deploying it, behind Caddy or
an existing nginx, is in `server/deploy/README.md`). Point a build
at it with `--dart-define=LOBBY_URL=https://your.host`. For web builds, add
`--wasm --no-web-resources-cdn`.

See [PRIVACY.md](PRIVACY.md) for what online play shares.

Derived from the RiseTogether research platform by NexusDynamic.
