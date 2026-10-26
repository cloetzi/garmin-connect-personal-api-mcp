# Security

## Reporting a vulnerability

Please report vulnerabilities privately through
[GitHub private vulnerability reporting](https://github.com/cloetzi/garmin-connect-personal-api-mcp/security/advisories/new),
not in public issues. You will get an answer within a week. Fixes are released as soon as they are ready and
credited in the advisory unless you prefer otherwise.

Only the latest release is supported.

## Threat model

The server holds a credential for one person's Garmin account and returns that person's health data. The design
assumes the network between the client and the server may be shared (a home network, a container network) and
that a browser on the same machine may visit hostile web pages.

| Asset | Protection |
| --- | --- |
| Garmin personal API key | Read only from the environment or a secret file; never logged, never sent to MCP clients, only sent to the fixed Garmin host. |
| Garmin access tokens | Held in memory only; never logged or persisted. |
| Health data | Served only to authenticated clients; never logged. |
| MCP endpoint | Bearer token required by default, compared in constant time; must be at least 32 characters. Disabling authentication requires an explicit setting and is logged as a warning at every start. |
| Local browser attacks | `Host` and `Origin` validation against DNS rebinding and cross-site requests. |

Further design properties:

- **Read-only.** The server only issues `GET` requests to Garmin data endpoints (plus the token exchange).
- **No outbound flexibility.** The Garmin base URL is fixed to an `https` URL; tool arguments are type-checked,
  dates validated, and path values URL-encoded, so arguments cannot redirect requests.
- **Bounded resources.** Request bodies are capped at 1 MiB, Garmin responses at a configurable size, requests
  to Garmin are concurrency-limited and time-limited, and no session state is kept (stateless transport).
- **Minimal container.** Non-root user (65532), no writable paths, works with `--read-only` and
  `--cap-drop ALL`; base images are pinned by digest.

## Out of scope

- TLS: the server speaks plain HTTP. Use a reverse proxy or VPN to reach it over untrusted networks.
- Multi-user access: one server serves one Garmin account. Everyone holding a valid MCP token can read all of
  that account's data the API exposes.
- What an MCP client or model does with the data it receives.

## Recommendations

- Keep the port bound to `127.0.0.1` or a private network; do not expose it to the internet.
- Use Docker secrets (`*_FILE` variables) rather than plain environment variables, which are visible in
  `docker inspect`.
- Give each client its own token (comma-separated) so you can revoke one without touching the others.
- Hide data you do not want assistants to see with `GARMIN_MCP_EXCLUDE_TOOLS` (for example
  `periodichealth-service,nutrition-service`).
- Choose a short Garmin key expiration and delete keys you no longer use on Garmin Connect Web.
