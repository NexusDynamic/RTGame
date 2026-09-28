# Privacy

Rise Together has no accounts and collects no personal data.

**Solo play** happens locally. Settings, your nickname and
your best score are stored locally and never sent anywhere.

**Online play:**
- **Your nickname** is shown to the players in your match. It passes through
  the server while the connection is set up, and the server does not store it.
- **Your IP address.** The lobby server and the players you are matched with
  see it, because that is how devices connect over the internet. If a direct
  connection is not possible, a relay server passes your game traffic along
  and also sees your IP address. That traffic is encrypted end to end and
  cannot be read by the relay.
- **Kept only while needed.** The lobby keeps your IP address in memory for
  rate limiting, and a match's connection details until the match ends.
- The server's logs never contain your IP address or
  your nickname. To trace abuse, they record a pseudonymous id computed from
  your IP address with a secret key. Other deployments of the server may
  follow a different policy.
- **No analytics and no ads**
