# Rise Together server

A lobby, one signaling hub per match, and a TURN relay. It **never runs the
game**: the host player's device runs the physics and everyone connects to it
peer to peer over WebRTC.

| Piece | Role |
|---|---|
| Caddy | TLS, serves the web build, proxies `/api/*` and `/room/*` |
| lobby | proof-of-work admission, matchmaking, per-match hubs |
| coturn | relays encrypted packets for players who cannot connect directly |

## Why nothing needs a key in the app

1. `GET /api/challenge`, then solve a small proof-of-work, then `POST /api/admit`,
   which returns a session token valid for 15 minutes. Each challenge works once.
2. The lobby socket (`/api/lobby?token=`) matches players. Each match gets a
   fresh hub with a random secret, sent only to that match's players.
3. TURN credentials expire after 10 minutes and are only issued inside a match.

The limits:
- Rate limits per address.
- A browser Origin allow-list.
- Caps on lobby connections per address and in total.
- A cap on the number of rooms.
- Message size limits.
- Room lifetimes.

## Logs

The lobby never logs IP addresses. Connection events (admitted, rate-limited,
lobby connect/disconnect, room join, matched) name the client by a
pseudonymous id: HMAC-SHA256 of the address under a random key that lives only
in memory and rotates every 24 hours. The same client is traceable within a
day and unlinkable across days, and the id cannot be reversed without the key.
Caddy's access log and coturn's allocation log are off, because both would
record raw addresses.

## Deploy

```sh
cd server/deploy
cp .env.example .env            # fill in DOMAIN, PUBLIC_IP and the two secrets
mkdir -p web && cp -r ../../build/web/* web/   # after `flutter build web --wasm`
docker compose up -d --build              # add --profile turn for the bundled coturn
```

Open TCP 80 and 443. For TURN, also open TCP/UDP `TURN_PORT` (default 3478) and the UDP relay range (default 49160–49400).

## TURN: bundled or shared

The lobby only needs a TURN URL and the coturn's `static-auth-secret`. It
mints short-lived credentials from that secret, and coturn checks them
without storing anything.

- **Share an existing coturn (simplest).** Set `TURN_HOST`, `TURN_PORT` and
  `TURN_SECRET` to match it and start without the `turn` profile. This works
  when it already uses `use-auth-secret`: coturn allows one auth mechanism and,
  in its config file, one static secret, so the lobby reuses that secret. The
  secret never leaves the VPS. Check that the existing config has the
  `denied-peer-ip` ranges and quotas from `turnserver.conf` here, since they
  now protect this game too.
- **Run a second coturn.** Use `docker compose --profile turn up -d` with a
  different `TURN_PORT` (e.g. 3479) and a relay range (`TURN_MIN_PORT`–
  `TURN_MAX_PORT`) that does not overlap the existing one. TLS, DTLS and the
  CLI are off in this instance, so it claims no other ports.

A TURN server cannot be limited to a domain name. Clients reach it by IP and
port over UDP, which carries no hostname. Separating by address only works if
the VPS has a second IP (`--listening-ip` / `--relay-ip`).

Build the app with the lobby's address:
`flutter build <platform> --dart-define=LOBBY_URL=https://play.example.com`.

## Development

```sh
dart test
LOBBY_SIGNING_KEY=$(openssl rand -base64 48) POW_DIFFICULTY=12 \
  ALLOWED_ORIGINS=http://localhost:5000 dart run bin/lobby.dart
```
