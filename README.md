# Garmin Connect Personal API MCP server

[![CI](https://github.com/cloetzi/garmin-connect-personal-api-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/cloetzi/garmin-connect-personal-api-mcp/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

An [MCP](https://modelcontextprotocol.io) server that gives AI assistants read-only access to your own
health and fitness data through Garmin's official
[Connect Personal API](https://developer.garmin.com/gc-developer-program/personal/personal-api/):
sleep, HRV, heart rate, stress, Body Battery, steps, activities, weight, nutrition and more.

- **Official API only.** Uses your personal API key, no username/password scraping.
- **Read-only.** Every Garmin endpoint it exposes is a `GET`; it cannot change anything in your account.
- **Generated from Garmin's spec.** Tools are built from Garmin's published OpenAPI document, refined by
  [curated overrides](docs/overrides.md) so assistants get clear descriptions and validated inputs.
- **Secure by default.** Bearer-token authentication is required unless explicitly disabled; the image runs
  as an unprivileged user on a read-only filesystem.
- **Lightweight.** Ruby 4 on fibers ([Falcon](https://github.com/socketry/falcon)), ~60 MB of memory.

> [!NOTE]
> This project is not affiliated with or endorsed by Garmin. Garmin and Garmin Connect are trademarks of Garmin Ltd.

## Quick start

1. **Create a Garmin personal API key.** Follow
   [Garmin's instructions](https://developer.garmin.com/gc-developer-program/personal/personal-api/): on Garmin
   Connect Web open the Personal API Key page, accept the terms, pick an expiration and copy the key (it is shown
   only once).

2. **Generate a token** that your MCP clients will use to authenticate to this server:

   ```sh
   openssl rand -hex 32
   ```

3. **Run the server:**

   ```sh
   docker run -d --name garmin-mcp --restart unless-stopped \
     --read-only --cap-drop ALL --security-opt no-new-privileges \
     -p 127.0.0.1:8080:8080 \
     -e GARMIN_PERSONAL_API_KEY='<your Garmin key>' \
     -e GARMIN_MCP_AUTH_TOKEN='<the token from step 2>' \
     ghcr.io/cloetzi/garmin-connect-personal-api-mcp:latest
   ```

   The MCP endpoint is `http://localhost:8080/mcp`. For a long-running setup, prefer
   [Docker Compose with secrets](compose.yaml).

4. **Connect a client** (see below) and ask something like *"How did I sleep this week compared to last week?"*

## Connecting clients

### Claude Code

```sh
claude mcp add --transport http garmin http://localhost:8080/mcp \
  --header "Authorization: Bearer <token>"
```

### Other HTTP clients (Cursor, VS Code, homelab tools)

Point the client at `http://<host>:8080/mcp` (Streamable HTTP) and send the header
`Authorization: Bearer <token>`. If the client reaches the server under a name other than `localhost`
(for example `garmin-mcp.lan` or a Compose service name), add that name to `GARMIN_MCP_ALLOWED_HOSTS`.

### Claude Desktop and other stdio clients

Clients that launch MCP servers as local processes can run the image in stdio mode. No MCP token is needed
because nothing listens on the network:

```json
{
  "mcpServers": {
    "garmin": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "--read-only", "--cap-drop", "ALL",
               "-e", "GARMIN_PERSONAL_API_KEY",
               "ghcr.io/cloetzi/garmin-connect-personal-api-mcp:latest", "stdio"],
      "env": { "GARMIN_PERSONAL_API_KEY": "<your Garmin key>" }
    }
  }
}
```

## Tools

| Area | Tools |
| --- | --- |
| Daily overview | `get_daily_user_summary`, `get_daily_summaries` |
| Sleep | `get_daily_sleep`, `get_daily_sleep_summaries` |
| Heart | `get_daily_heart_rate`, `get_daily_hrv`, `get_daily_hrv_summaries`, `get_heart_rate_zones`, `get_daily_spo2` |
| Stress & energy | `get_daily_stress`, `get_daily_body_battery` |
| Movement | `get_daily_steps`, `get_wellness_activity_summaries` |
| Activities | `search_activities`, `get_activity`, `get_activity_workouts`, `download_activity` (disabled by default) |
| Body | `get_weight_measurements`, `get_weight_entries`, `get_effective_weight_goals`, `get_fitness_age` |
| Nutrition & hydration | `get_daily_food_logs`, `get_daily_hydration` |
| Cycle tracking | `get_menstrual_cycle_summary`, `get_menstrual_cycle_day_view` |
| Profile | `get_user_profile_settings` |

Print the full catalog with descriptions and input schemas with
`docker run --rm ghcr.io/cloetzi/garmin-connect-personal-api-mcp tools`. Limit what is exposed with
`GARMIN_MCP_TOOLS` and `GARMIN_MCP_EXCLUDE_TOOLS`, which accept tool names and service names such as
`periodichealth-service`.

## Configuration

All configuration is through environment variables; every secret also has a `*_FILE` variant for Docker
secrets. The essentials:

| Variable | Default | Description |
| --- | --- | --- |
| `GARMIN_PERSONAL_API_KEY` | (required) | Your Garmin personal API key |
| `GARMIN_MCP_AUTH_TOKEN` | (required for HTTP) | Token(s) clients must send as `Authorization: Bearer`, comma-separated, ≥ 32 characters |
| `GARMIN_MCP_AUTH_DISABLED` | `false` | Set to `true` to run without authentication |
| `GARMIN_MCP_ALLOWED_HOSTS` | | Extra `Host` names the server answers to, besides `localhost` |
| `GARMIN_MCP_TOOLS` / `GARMIN_MCP_EXCLUDE_TOOLS` | | Tool or service names to expose / hide |

See [docs/configuration.md](docs/configuration.md) for everything else (ports, limits, logging, overrides).

## Security

Your Garmin data is personal health data, so treat this server like a password manager:

- Keep authentication enabled, and do not expose the port to the internet. For remote access, put it behind
  a VPN or a reverse proxy that terminates TLS.
- The Garmin key stays inside the server; clients only ever see the MCP token.
- Garmin keys expire (30 days to one year). Garmin emails you a week before; the server reports a rejected key
  clearly in tool results and logs.

See [SECURITY.md](SECURITY.md) for the threat model and how to report vulnerabilities.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: `bundle install`, `bundle exec rake` (lint and tests),
`bin/garmin-mcp` to run locally.

## License

[Apache License 2.0](LICENSE). The bundled OpenAPI document is published by Garmin; see [NOTICE](NOTICE).
