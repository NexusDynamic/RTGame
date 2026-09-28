# Security

Please report vulnerabilities privately, through
[GitHub's private vulnerability reporting](https://github.com/NexusDynamic/RTGame/security/advisories/new),
not as a public issue.

Especially relevant:

- **The lobby server** (`server/`): matchmaking, signaling, proof-of-work,
  rate limiting and the TURN credentials.
- **The TURN relay configuration** (`server/deploy/turnserver.conf`), for
  example ways to reach a host's private network through it.
- **The game's network handling**: every message a peer sends, including the
  host's, is untrusted. Any input that crashes another player's game, is
  persisted, or is shown to them as text is a bug.
- **Privacy**: anything that leaks more than [PRIVACY.md](PRIVACY.md) says.

Only the latest release and `main` are supported.
