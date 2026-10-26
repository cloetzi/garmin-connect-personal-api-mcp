# Configuration

The server is configured entirely through environment variables. Invalid configuration stops the server at
startup with a list of every problem. Validate a configuration without starting the server, naming the
transport you run (`http`, the default, or `stdio`, which needs no MCP token):

```sh
docker run --rm --env-file garmin.env ghcr.io/cloetzi/garmin-connect-personal-api-mcp check-config
docker run --rm --env-file garmin.env ghcr.io/cloetzi/garmin-connect-personal-api-mcp check-config stdio
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
| `GARMIN_MCP_HOST` | `127.0.0.1` (image: `0.0.0.0`) | Address to listen on: an IP address or host name. An IPv6 address can be written with or without brackets (`::1` or `[::1]`). The image's health check probes this address, or loopback (`127.0.0.1` or `::1`) when it is `0.0.0.0` or `::`. |
| `GARMIN_MCP_PORT` | `8080` | Port to listen on. |
| `GARMIN_MCP_PATH` | `/mcp` | Path of the MCP endpoint. `/healthz` is always served for health checks, so it cannot be used. |
| `GARMIN_MCP_ALLOWED_HOSTS` | | Comma-separated `Host` header values accepted in addition to `localhost`, `127.0.0.1` and `::1`. Entries are a host name (any port) or `host:port` (an IPv6 address without brackets matches any port). `*` accepts any host and disables only this check: `Origin` is still validated. |
| `GARMIN_MCP_ALLOWED_ORIGINS` | | Comma-separated `Origin` values accepted from browser-based clients in addition to same-origin requests, written as `scheme://host[:port]` (e.g. `https://app.example.com`) and matched exactly, ignoring case. |

Requests to the MCP endpoint are checked before authentication, and rejected ones are answered with HTTP 403
and logged with a hint naming the variable to change:

- The `Host` header must be allowed (protection against DNS rebinding). Requests without one are accepted;
  browsers always send it.
- The `Origin` header, when present, must be same-origin (its host and port equal the `Host` header; the scheme
  is not compared, so this also works behind a TLS-terminating proxy) or listed in `GARMIN_MCP_ALLOWED_ORIGINS`.
  Requests without one come from non-browser clients and are accepted.

With `GARMIN_MCP_ALLOWED_HOSTS=*`, a page served from a name that resolves to the server counts as same-origin,
so DNS rebinding is no longer prevented; use it only when a reverse proxy in front already restricts the host
names it forwards.

The server speaks plain HTTP. Terminate TLS in a reverse proxy if clients connect over a network you do not
trust.

## Tools

| Variable | Default | Description |
| --- | --- | --- |
| `GARMIN_MCP_TOOLS` | all enabled tools | Comma-separated tool names and/or service names (e.g. `sleep-service`) to expose. Naming a tool that is disabled by default (`download_activity`) enables it. |
| `GARMIN_MCP_EXCLUDE_TOOLS` | | Comma-separated tool or service names to hide, applied after `GARMIN_MCP_TOOLS`. |
| `GARMIN_MCP_OVERRIDES_FILE` | | Path to a YAML file merged on top of the bundled overrides; see [overrides.md](overrides.md). |

Unknown names are an error, so a typo cannot silently expose more than intended.

`garmin-mcp tools` prints every tool, including those disabled by default, with `GARMIN_MCP_OVERRIDES_FILE`
applied; it needs no credentials and ignores `GARMIN_MCP_TOOLS` and `GARMIN_MCP_EXCLUDE_TOOLS`, so you can
pick names from it. `check-config` lists the tools a configuration actually exposes.

## Responses and limits

| Variable | Default | Description |
| --- | --- | --- |
| `GARMIN_MCP_MAX_RESPONSE_BYTES` | `100000` | Maximum size of a tool result. JSON results longer than this are truncated with a note asking the assistant to narrow the request. See [activity files](#activity-files) for `download_activity`. |
| `GARMIN_MCP_STRIP_NULLS` | `true` | Remove `null` fields from Garmin responses to save context. |
| `GARMIN_MCP_TIMEOUT` | `30` | Seconds to wait for Garmin per request attempt. |
| `GARMIN_MCP_MAX_CONCURRENCY` | `4` | Maximum concurrent requests to Garmin. |
| `GARMIN_MCP_MAX_DOWNLOAD_BYTES` | `26214400` | Maximum size of a Garmin response the server reads, before it parses and truncates it. Larger responses are abandoned with an error asking the assistant to narrow the request. |

Transient Garmin failures (HTTP 429, 502, 503, 504, DNS and connection errors) are retried twice with backoff,
honoring `Retry-After` up to 10 seconds. Timeouts and TLS failures are not retried; the tool error names the cause.

### Activity files

`download_activity` returns the file as a base64-encoded blob, which is a third larger than the file and cannot
be truncated. A file is returned only if the encoded blob fits `GARMIN_MCP_MAX_RESPONSE_BYTES`, so the largest
file is three quarters of that limit (75 KB by default; never more than `GARMIN_MCP_MAX_DOWNLOAD_BYTES`). Larger
files are refused with an error, and their download stops as soon as the size is exceeded. If your client can
handle files, raise the limit, e.g. to `4000000` for files up to 3 MB; this also lets JSON results grow to that
size.

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
