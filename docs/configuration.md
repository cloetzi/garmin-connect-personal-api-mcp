# Configuration

The server is configured entirely through environment variables. Invalid configuration stops the server at
startup with a list of every problem. Validate a configuration without starting the server:

```sh
docker run --rm --env-file garmin.env ghcr.io/cloetzi/garmin-connect-personal-api-mcp check-config
```

## Secrets

Each secret can be passed directly or as a path to a file (`*_FILE`), which works with Docker and Compose
secrets. Setting both forms of the same secret is an error.

| Variable | Description |
| --- | --- |
| `GARMIN_PERSONAL_API_KEY` / `GARMIN_PERSONAL_API_KEY_FILE` | Garmin personal API key. Required. The same variable name as Garmin's official Python client. |
| `GARMIN_MCP_AUTH_TOKEN` / `GARMIN_MCP_AUTH_TOKEN_FILE` | Token(s) MCP clients must send as `Authorization: Bearer <token>`. Required for the HTTP transport unless authentication is disabled. Each token must be at least 32 characters; separate several with commas to rotate without downtime. |

## Authentication

| Variable | Default | Description |
| --- | --- | --- |
| `GARMIN_MCP_AUTH_DISABLED` | `false` | `true` serves the HTTP transport without authentication. Setting it together with a token is an error, so authentication cannot be switched off by accident. |

The stdio transport never uses MCP authentication: it only talks to the process that launched it.

## HTTP server

| Variable | Default | Description |
| --- | --- | --- |
| `GARMIN_MCP_HOST` | `127.0.0.1` (image: `0.0.0.0`) | Address to listen on. |
| `GARMIN_MCP_PORT` | `8080` | Port to listen on. |
| `GARMIN_MCP_PATH` | `/mcp` | Path of the MCP endpoint. `/healthz` is always served for health checks. |
| `GARMIN_MCP_ALLOWED_HOSTS` | | Comma-separated `Host` header values accepted in addition to `localhost`, `127.0.0.1` and `::1`. Entries are a host name (any port) or `host:port`. `*` disables the check. Requests with other hosts are rejected (protection against DNS rebinding) and logged with a hint. |
| `GARMIN_MCP_ALLOWED_ORIGINS` | | Comma-separated `Origin` values accepted from browser-based clients, in addition to same-origin requests. |

The server speaks plain HTTP. Terminate TLS in a reverse proxy if clients connect over a network you do not
trust.

## Tools

| Variable | Default | Description |
| --- | --- | --- |
| `GARMIN_MCP_TOOLS` | all enabled tools | Comma-separated tool names and/or service names (e.g. `sleep-service`) to expose. Naming a tool that is disabled by default (`download_activity`) enables it. |
| `GARMIN_MCP_EXCLUDE_TOOLS` | | Comma-separated tool or service names to hide, applied after `GARMIN_MCP_TOOLS`. |
| `GARMIN_MCP_OVERRIDES_FILE` | | Path to a YAML file merged on top of the bundled overrides; see [overrides.md](overrides.md). |

Unknown names are an error, so a typo cannot silently expose more than intended.

## Responses and limits

| Variable | Default | Description |
| --- | --- | --- |
| `GARMIN_MCP_MAX_RESPONSE_BYTES` | `100000` | Tool results longer than this are truncated with a note asking the assistant to narrow the request. |
| `GARMIN_MCP_STRIP_NULLS` | `true` | Remove `null` fields from Garmin responses to save context. |
| `GARMIN_MCP_TIMEOUT` | `30` | Seconds to wait for Garmin per request attempt. |
| `GARMIN_MCP_MAX_CONCURRENCY` | `4` | Maximum concurrent requests to Garmin. |
| `GARMIN_MCP_MAX_DOWNLOAD_BYTES` | `26214400` | Maximum size of any Garmin response, including activity file downloads. |

Transient Garmin failures (HTTP 429, 502, 503, 504, DNS and connection errors) are retried twice with backoff,
honoring `Retry-After` up to 10 seconds. Timeouts and TLS failures are not retried; the tool error names the cause.

## Logging

| Variable | Default | Description |
| --- | --- | --- |
| `GARMIN_MCP_LOG_LEVEL` | `info` | `debug`, `info`, `warn` or `error`. |
| `GARMIN_MCP_LOG_FORMAT` | `text` | `text` (key=value) or `json`. |

Logs go to stderr. They contain tool names, HTTP status codes and timings, never keys, tokens or the health
data returned by Garmin.

## Development only

| Variable | Default | Description |
| --- | --- | --- |
| `GARMIN_PERSONAL_API_BASE_URL` | `https://personal.connectapi.garmin.com` | Garmin API base URL. Must be `https`; plain `http` is accepted only for loopback addresses (local test servers). |
