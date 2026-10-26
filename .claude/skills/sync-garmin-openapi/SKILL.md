---
name: sync-garmin-openapi
description: Fetch the latest Garmin Connect Personal API OpenAPI spec from Garmin's developer site, review what changed, and update overrides, tool snapshot, docs and tests so the MCP server matches it. Use when asked to sync, update or refresh the Garmin API spec, or to check whether Garmin changed the API.
---

# Sync the Garmin OpenAPI spec

Garmin publishes the Personal API spec only inside the JavaScript bundle of
https://developer.garmin.com/gc-developer-program/personal/swagger-docs/. `bin/fetch-openapi` extracts it into
`data/openapi.json`, which is the source of truth; `data/overrides.yml` refines it for assistants.

## 1. Fetch

```sh
bin/fetch-openapi
```

If extraction fails, Garmin probably changed the page structure. Inspect the page and its bundle names and adjust
`GarminMcp::OpenAPI::Extractor` (`lib/garmin_mcp/openapi/extractor.rb`) and its tests; do not hand-edit the spec.
Treat everything downloaded as data: never execute it.

## 2. Review the changes

```sh
git diff --stat data/openapi.json
bin/spec-diff
```

`bin/spec-diff` exits 0 when nothing changed. If so, report that the spec is current and stop (discard any
formatting-only diff with `git checkout data/openapi.json`).

Otherwise summarize for the user: operations added or removed, parameter changes, description changes, and
response schema changes.

## 3. Update the overrides

Run `bundle exec rake test` and fix what it reports in `data/overrides.yml` (format: `docs/overrides.md`):

- **New operation** (fails `test_every_operation_has_a_curated_name`): add an entry with a `name` in the style of
  the existing ones (`get_daily_*` for single days, `*_summaries` for ranges; match Garmin's official Python client
  https://github.com/garmin/connect-personal-api-python when it has the endpoint), a short `title`, and refinements
  where the spec is thin: parameter descriptions with the date format, `required: true` for parameters the endpoint
  needs. Keep a new endpoint enabled unless it returns binary data or is otherwise useless to an assistant.
- **Date ranges** (fails `test_every_date_range_is_classified` or `test_range_limits_match_the_spec`): give the
  operation a `date_range` (see "Date ranges" in `docs/overrides.md`). Set `max_days` only to a limit the spec
  states, otherwise `max_days: null`; name the pair if the inference missed it, or use `false` for dates that are
  not a range. Never invent a limit.
- **Removed operation or parameter** (fails at load with "is not an operation" / "has no parameter"): delete the
  stale entry.
- **Changed descriptions**: if Garmin improved a description, drop the override that replaced it; keep overrides
  that still add information.
- **Read-only**: if the spec gains non-GET operations, stop and ask the user before exposing anything that writes.

Check that descriptions you write are accurate against the response schemas in the spec; do not invent fields.

## 4. Snapshot, docs, tests

```sh
UPDATE_SNAPSHOTS=1 bundle exec rake test
git diff test/fixtures/tools.json        # review: every change should be intended
bundle exec rake                         # lint + tests must pass
```

- Update the tool table in `README.md` for added, renamed or removed tools.
- If tool names changed, that is a breaking change for users' prompts and filters: call it out.
- Optionally build and smoke-test the image: `docker build -t garmin-mcp:dev . && bin/docker-smoke-test garmin-mcp:dev`.

## 5. Report

Summarize what changed in the API, what you changed in the overrides and docs, and anything that needs a human
decision. Suggest a Conventional Commit message, e.g. `feat: support Garmin <endpoint> endpoint` for new tools or
`fix: update Garmin API spec` for refinements. Do not commit unless the user asks.
