# AGENTS.md

Guidance for AI coding agents working in this repository. Human contributors: see CONTRIBUTING.md.

## What this is

An MCP server (Ruby 4, Falcon, official `mcp` gem) exposing Garmin's Connect Personal API as read-only tools.
Users run it from the Docker image published to GHCR. One server serves one Garmin account.

## Layout

- `data/openapi.json`: Garmin's spec, extracted from their developer site by `bin/fetch-openapi`. Source of truth.
  **Never edit by hand.**
- `data/overrides.yml`: curated tool names, descriptions, required flags, defaults and date range limits layered
  on the spec. Format in `docs/overrides.md`.
- `lib/garmin_mcp/`
  - `openapi/`: spec model (`spec.rb`), extraction from the JS bundle (`extractor.rb`), change summary (`diff.rb`)
  - `overrides.rb`, `catalog.rb`, `tool_definition.rb`: spec + overrides into tool definitions and Garmin requests
  - `garmin/`: fiber-based HTTP client, API-key-to-token exchange, authenticated client
  - `tool_runner.rb`: executes tool calls and shapes responses for the model
  - `config.rb`, `http_app.rb`, `static_token_verifier.rb`, `application.rb`, `cli.rb`: wiring and transports
- `bin/`: `garmin-mcp` (server CLI), `fetch-openapi`, `spec-diff`, `healthcheck`, `docker-smoke-test`
- `test/`: Minitest; `test/support/fake_garmin.rb` is a local fake of the Garmin API;
  `test/fixtures/tools.json` snapshots the generated tool catalog.

## Commands

```sh
bundle exec rake                               # RuboCop + tests; must pass before you finish
UPDATE_SNAPSHOTS=1 bundle exec rake test       # after intentional catalog changes; review the diff
bin/garmin-mcp tools                           # inspect the generated tools
docker build -t garmin-mcp:dev . && bin/docker-smoke-test garmin-mcp:dev
```

## Updating to a new Garmin spec

Use the `sync-garmin-openapi` skill (`.claude/skills/sync-garmin-openapi/SKILL.md`); it lists the steps.

## Rules

- **Security.** Never log, print or include in errors the Garmin API key, Garmin tokens, MCP tokens, or health
  data from Garmin responses. Keep the Garmin host fixed and the server read-only (GET endpoints only). MCP auth
  stays required by default.
- **Never commit real Garmin responses** as fixtures; they are personal health data. Hand-write fixtures.
- **Fibers.** Code runs under the Async fiber scheduler. Use non-blocking IO (async-http, stdlib IO is fine),
  never threads for request work, and keep shared state behind a `Mutex` (fiber-aware).
- **Logs go to stderr**; stdout is the stdio transport's protocol channel.
- **Style.** Follow the surrounding code: small classes, `Data` value objects, endless methods for one-liners,
  comments only where intent is not obvious. RuboCop is the arbiter.
- **Dependencies.** Keep them minimal; the image should stay small. Ask before adding a gem.
- **Commits.** Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`, `test:`); PR titles are
  checked and drive release-please. Do not edit `CHANGELOG.md` or the version by hand.
- **Docs.** Update `docs/configuration.md` when adding or changing environment variables, and the README tool
  table when tools are added, renamed or removed.
