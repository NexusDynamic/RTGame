# Contributing

Issues and pull requests are welcome.

## Before opening a pull request

```sh
flutter analyze
flutter test
(cd server && dart analyze && dart test)   # if you touched the lobby
```

Add or update tests for what you change. New player-facing text goes in
both `assets/translations/en.json` and `da.json`.

## Network rules

Online play is peer to peer: one player's device (the host) runs the physics
and the others send inputs. Code that touches the network has to follow
these rules:

- **Every message is untrusted, including the host's.** Decoders
  (`lib/src/net/game_session.dart`) check type *and* range and return null.
  Callers drop nulls and never throw on bad input.
- **Nothing received from the network is persisted.** Match rules chosen by
  the host are held in memory for one match. Physics constants are not
  negotiable.
- **No free text for display crosses the wire.** Send indices and render
  them locally. Nicknames are the exception: they are sanitised and
  length-limited on receipt (`peer_game_session.dart`).
- **Attribution comes from the transport's authenticated sender**, never
  from the message body.
- **The lobby server is untrusted too**, and no keys ship in the app.

## Relationship to RiseTogether

This game is a fork of the RiseTogether research platform. Changes here are
not sent back to that project.
