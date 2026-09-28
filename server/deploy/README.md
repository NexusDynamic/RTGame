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

There are two builds, and you only run one of them yourself:

- **The lobby** (`server/bin/lobby.dart`) is compiled by the Dockerfile when
  you pass `--build`. There is nothing to build for it by hand. Each release
  also publishes the image as `ghcr.io/nexusdynamic/rtgame-lobby:<version>`
  (and `:latest`); to use it, set `image:` on the `lobby` service instead of
  `build:`.
- **The web app** is the game itself (`lib/main.dart` at the repository
  root). Build it from the **repository root**, not from `server/`. That is
  why `flutter build` reports `Target file "lib/main.dart" not found` when it
  runs in here:

  ```sh
  # from the repository root
  flutter build web --wasm --no-web-resources-cdn \
    --dart-define=LOBBY_URL=https://play.example.com \
    --dart-define=GIT_SHA=$(git rev-parse HEAD)
  ```

  `LOBBY_URL` is the same host that serves the web app. The lobby only
  accepts browsers from `https://$DOMAIN` (`ALLOWED_ORIGINS`), so serve both
  from one domain. Native builds use the same `--dart-define`. Without it,
  builds default to `https://rt-lobby.nexusdynamic.org`; players can also
  point any build at your server in Settings → Online → Server.

  Each GitHub release also has a ready-made web build
  (`RiseTogether-<version>-web.zip`) that uses the default lobby. Only use
  it if you are running rt-lobby.nexusdynamic.org itself.

  A web app served from somewhere else (another domain, GitHub Pages) can
  only use your lobby if you add its origin to `ALLOWED_ORIGINS`, e.g.
  `https://play.example.com,https://you.github.io`. Native apps send no
  Origin and are not affected.

Then `cp .env.example .env` in this directory, and fill in `DOMAIN`,
`PUBLIC_IP` and the two secrets. After that, pick one of the two options
below.

### A. Caddy (a VPS with nothing on 80/443)

```sh
cd server/deploy
mkdir -p web && cp -r ../../build/web/* web/
docker compose up -d --build              # add --profile turn for the bundled coturn
```

Caddy gets the certificate itself. Open TCP 80 and 443.

### B. An existing nginx

Run only the lobby, published on `127.0.0.1:8080`, and let nginx do TLS and
serve the web build:

```sh
cd server/deploy
docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d --build lobby
# with the bundled coturn:
#   docker compose -f docker-compose.yml -f docker-compose.nginx.yml --profile turn up -d --build lobby coturn

sudo mkdir -p /var/www/rise-together
sudo cp -r ../../build/web/* /var/www/rise-together/
sudo cp nginx.conf.example /etc/nginx/sites-available/rise-together   # edit the hostname
sudo ln -s ../sites-available/rise-together /etc/nginx/sites-enabled/
sudo certbot --nginx -d play.example.com      # or point the ssl_* lines at existing certs
sudo nginx -t && sudo systemctl reload nginx
```

`nginx.conf.example` does what the Caddyfile does, and all of it matters:

- WebSocket upgrades for `/api/*` and `/room/*`, with long read timeouts.
- `X-Forwarded-For` **overwritten** with `$remote_addr`, not appended. The
  lobby rate-limits by it (`TRUST_PROXY=true`).
- COOP/COEP headers on the web app. Without them the wasm build loses
  multithreading.
- Access log off.

If port 8080 is taken on the host, set `LOBBY_HOST_PORT` in `.env` and change
`proxy_pass` to match.

### Either way

For TURN, also open TCP/UDP `TURN_PORT` (default 3478) and the UDP relay
range (default 49160–49400). Check with `curl https://play.example.com/health`,
which should print `ok`.

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

## Development

```sh
dart test
LOBBY_SIGNING_KEY=$(openssl rand -base64 48) POW_DIFFICULTY=12 \
  ALLOWED_ORIGINS=http://localhost:5000 dart run bin/lobby.dart
```
