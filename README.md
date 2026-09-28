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

## Play

- **In the browser, online:** <https://rt-lobby.nexusdynamic.org>
- **In the browser, offline:** <https://nexusdynamic.github.io/RTGame/>
  (solo and the level editor; no server by default)
- **Downloads** for Windows, macOS, Linux and Android are on the
  [releases page](https://github.com/NexusDynamic/RTGame/releases).
  - **macOS:** the app is not signed. The first time, right-click it and
    choose *Open*.
  - **Linux:** needs GTK 3, GStreamer and PulseAudio (or PipeWire's pulse
    server), which most desktops already have.
  - **Android:** use the APK for your device (`arm64-v8a` for most phones),
    or `universal` if unsure.

### Using another server

Online play uses `https://rt-lobby.nexusdynamic.org` by default. To use
another lobby server, including your own (see `server/deploy/README.md`), go
to Settings → Online → Server. In a browser, the server must list the page's
address in its `ALLOWED_ORIGINS`.

## Development

```sh
flutter pub get
flutter run            # or: flutter run -d chrome
flutter test
flutter test integration_test/real_webrtc_test.dart -d linux   # real WebRTC
scripts/with-weston.sh flutter test integration_test/real_webrtc_test.dart -d linux   # same, headless (as CI)
```

Online play needs the lobby server (`server/`; deploying it, behind Caddy or
an existing nginx, is in `server/deploy/README.md`). Builds use
`https://rt-lobby.nexusdynamic.org` unless you pass
`--dart-define=LOBBY_URL=https://your.host`, or
`--dart-define=LOBBY_URL=none` for a build with no default server. For web
builds, add `--wasm --no-web-resources-cdn`.

## Releasing

1. Set `version:` in `pubspec.yaml` (e.g. `0.2.0+2`; raise the `+build`
   number every release, because Android needs it to increase).
2. Commit, then tag and push: `git tag v0.2.0 && git push origin v0.2.0`.

The [release workflow](.github/workflows/release.yml) checks that the tag
matches `pubspec.yaml`, runs CI, and builds every platform. It then creates a
GitHub release, deploys the offline web build to GitHub Pages, and pushes the
lobby image to `ghcr.io/nexusdynamic/rtgame-lobby`. A tag with a pre-release
part (`v0.2.0-beta.1`) creates a pre-release and leaves Pages and `latest`
alone. To try the builds without releasing, run the *Build* workflow by hand.

Android APKs are signed with the key in the `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`
secrets. Without those secrets they are signed with a debug key.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), and [SECURITY.md](SECURITY.md) for
reporting vulnerabilities.

See [PRIVACY.md](PRIVACY.md) for what online play shares.

## Credits

Code, artwork and music by [zeyus](https://me.zys.im/). Derived from the RiseTogether research
platform.
